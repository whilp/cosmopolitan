-- cosmo.embed - Embed pure Lua libraries into the Lua executable
-- Copyright 2025 Justine Alexandra Roberts Tunney
-- SPDX-License-Identifier: ISC

local embed = {}

local cosmo = require("cosmo")
local unix = require("cosmo.unix")
local zip = require("cosmo.zip")

-- Configuration
local LUAROCKS_API = "https://luarocks.org"
local USER_AGENT = "cosmo-lua/1.0"

--------------------------------------------------------------------------------
-- Utilities
--------------------------------------------------------------------------------

local function log(msg)
  io.stderr:write(msg .. "\n")
  io.stderr:flush()
end

local function errorf(fmt, ...)
  error(string.format(fmt, ...))
end

local function get_executable_path()
  -- Try /proc/self/exe first (Linux)
  local fd = unix.open("/proc/self/exe", unix.O_RDONLY)
  if fd then
    unix.close(fd)
    return "/proc/self/exe"
  end

  -- Fall back to arg[0] or arg[-1]
  return arg[0] or arg[-1] or error("Cannot determine executable path")
end

local function basename(path)
  return path:match("([^/]+)$") or path
end

--------------------------------------------------------------------------------
-- ZIP Writing (Pure Lua)
--------------------------------------------------------------------------------

local function pack_u16(n)
  return string.char(n & 0xFF, (n >> 8) & 0xFF)
end

local function pack_u32(n)
  return string.char(
    n & 0xFF,
    (n >> 8) & 0xFF,
    (n >> 16) & 0xFF,
    (n >> 24) & 0xFF
  )
end

-- Write ZIP local file header + data
local function write_zip_entry(fd, name, content, crc)
  local name_bytes = #name
  local data_bytes = #content

  -- Local file header (30 bytes + filename)
  local header =
    "\x50\x4B\x03\x04" ..  -- signature
    pack_u16(20) ..         -- version needed
    pack_u16(0) ..          -- flags
    pack_u16(0) ..          -- compression (none)
    pack_u16(0) ..          -- mod time
    pack_u16(0) ..          -- mod date
    pack_u32(crc) ..        -- crc32
    pack_u32(data_bytes) .. -- compressed size
    pack_u32(data_bytes) .. -- uncompressed size
    pack_u16(name_bytes) .. -- filename length
    pack_u16(0)             -- extra field length

  unix.write(fd, header)
  unix.write(fd, name)
  unix.write(fd, content)

  return 30 + name_bytes + data_bytes
end

-- Write ZIP central directory entry
local function write_central_dir_entry(fd, name, content_size, crc, offset)
  local name_bytes = #name

  local header =
    "\x50\x4B\x01\x02" ..  -- signature
    pack_u16((3 << 8) | 20) .. -- version made by (Unix, v2.0)
    pack_u16(20) ..         -- version needed
    pack_u16(0) ..          -- flags
    pack_u16(0) ..          -- compression
    pack_u16(0) ..          -- mod time
    pack_u16(0) ..          -- mod date
    pack_u32(crc) ..        -- crc32
    pack_u32(content_size) .. -- compressed size
    pack_u32(content_size) .. -- uncompressed size
    pack_u16(name_bytes) .. -- filename length
    pack_u16(0) ..          -- extra field length
    pack_u16(0) ..          -- comment length
    pack_u16(0) ..          -- disk number
    pack_u16(0) ..          -- internal attrs
    pack_u32(0x81A40000) .. -- external attrs (mode 0644)
    pack_u32(offset)        -- offset of local header

  unix.write(fd, header)
  unix.write(fd, name)

  return 46 + name_bytes
end

-- Write ZIP end of central directory
local function write_eocd(fd, num_entries, cdir_size, cdir_offset)
  local eocd =
    "\x50\x4B\x05\x06" ..  -- signature
    pack_u16(0) ..          -- disk number
    pack_u16(0) ..          -- disk with central dir
    pack_u16(num_entries) .. -- entries on this disk
    pack_u16(num_entries) .. -- total entries
    pack_u32(cdir_size) ..   -- central directory size
    pack_u32(cdir_offset) .. -- central directory offset
    pack_u16(0)              -- comment length

  unix.write(fd, eocd)
end

-- Append files to existing ZIP (executable)
local function append_to_zip(exe_path, files)
  -- Open for appending
  local fd = unix.open(exe_path, unix.O_WRONLY | unix.O_APPEND)
  if not fd then
    errorf("Failed to open for append: %s", exe_path)
  end

  -- Get starting offset
  local stat = unix.fstat(fd)
  if not stat then
    unix.close(fd)
    errorf("Failed to stat: %s", exe_path)
  end
  local start_offset = stat.size

  -- Write all local file headers + data
  local entries = {}
  local offset = start_offset

  for zippath, content in pairs(files) do
    local crc = cosmo.Crc32(content)
    local size = write_zip_entry(fd, zippath, content, crc)

    table.insert(entries, {
      name = zippath,
      content_size = #content,
      crc = crc,
      offset = offset,
    })

    offset = offset + size
  end

  -- Write central directory
  local cdir_offset = offset
  local cdir_size = 0

  for _, entry in ipairs(entries) do
    local size = write_central_dir_entry(
      fd,
      entry.name,
      entry.content_size,
      entry.crc,
      entry.offset
    )
    cdir_size = cdir_size + size
  end

  -- Write EOCD
  write_eocd(fd, #entries, cdir_size, cdir_offset)

  unix.close(fd)
  return true
end

--------------------------------------------------------------------------------
-- LuaRocks Integration
--------------------------------------------------------------------------------

local function fetch_url(url)
  log("Fetching: " .. url)

  local response = cosmo.Fetch(url, {
    headers = {
      ["User-Agent"] = USER_AGENT,
    },
  })

  if response.status ~= 200 then
    errorf("HTTP %d: %s", response.status, url)
  end

  return response.body
end

local function find_latest_version(package_name)
  -- Fetch the package page
  local url = LUAROCKS_API .. "/modules/" .. package_name
  local html = fetch_url(url)

  -- Extract version from HTML (look for version links)
  -- Format: /modules/author/package-version
  local versions = {}
  for version in html:gmatch(package_name .. "/([-%.%d]+)") do
    table.insert(versions, version)
  end

  if #versions == 0 then
    errorf("No versions found for package: %s", package_name)
  end

  -- Return the first one (usually latest)
  return versions[1]
end

local function fetch_rockspec(package_name, version)
  -- Try to fetch rockspec from the repository
  -- LuaRocks uses: /manifests/author/package-version.rockspec

  -- First, get the module page to find the author
  local url = LUAROCKS_API .. "/modules/" .. package_name
  local html = fetch_url(url)

  -- Extract author (look for /modules/author/ pattern)
  local author = html:match('/modules/([^/]+)/' .. package_name)
  if not author then
    errorf("Could not determine author for package: %s", package_name)
  end

  -- Fetch rockspec
  local rockspec_url = string.format("%s/manifests/%s/%s-%s.rockspec",
                                     LUAROCKS_API, author, package_name, version)

  local rockspec_content = fetch_url(rockspec_url)
  return rockspec_content, author
end

local function parse_rockspec(content)
  -- Rockspec is Lua code, so we can load it
  -- But we need to be careful - wrap in a sandbox

  local env = {
    package = {},
    version = nil,
    source = {},
    build = {},
    dependencies = {},
    description = {},
  }

  -- Load the rockspec in our environment
  local chunk, err = load(content, "rockspec", "t", env)
  if not chunk then
    errorf("Failed to parse rockspec: %s", err)
  end

  local ok, result = pcall(chunk)
  if not ok then
    errorf("Failed to execute rockspec: %s", result)
  end

  return env
end

local function find_rock_download_url(rockspec_data, author, package_name, version)
  -- Check source.url in rockspec
  if rockspec_data.source and rockspec_data.source.url then
    return rockspec_data.source.url
  end

  -- Try standard LuaRocks rock location
  local rock_url = string.format("%s/manifests/%s/%s-%s.%s.rock",
                                 LUAROCKS_API, author, package_name, version, "all")
  return rock_url
end

--------------------------------------------------------------------------------
-- Package Extraction
--------------------------------------------------------------------------------

local function extract_lua_files_from_zip(zip_content, package_name)
  -- Write to temp file
  local tmpfile = "/tmp/cosmo-embed-" .. package_name .. ".zip"
  local fd = unix.open(tmpfile, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
  if not fd then
    errorf("Failed to create temp file: %s", tmpfile)
  end
  unix.write(fd, zip_content)
  unix.close(fd)

  -- Open ZIP
  local reader, err = zip.open(tmpfile)
  if not reader then
    unix.unlink(tmpfile)
    errorf("Failed to open ZIP: %s", err)
  end

  -- Extract all .lua files
  local files = {}
  local entries = reader:list()

  for _, entry in ipairs(entries) do
    if entry:match("%.lua$") and not entry:match("/$") then
      local content, err = reader:read(entry)
      if content then
        files[entry] = content
      else
        log("Warning: Failed to read " .. entry .. ": " .. tostring(err))
      end
    end
  end

  reader:close()
  unix.unlink(tmpfile)

  return files
end

local function normalize_paths(files, package_name)
  -- Map extracted paths to /zip/.lua/ structure
  local normalized = {}

  for path, content in pairs(files) do
    local zippath = path

    -- Remove common prefixes
    zippath = zippath:gsub("^[^/]+/lua/", "")  -- package-1.0/lua/ -> ""
    zippath = zippath:gsub("^lua/", "")         -- lua/ -> ""

    -- If path doesn't start with package name, prepend it
    if not zippath:match("^" .. package_name .. "/") and
       not zippath:match("^" .. package_name .. "%.lua$") then
      zippath = package_name .. "/" .. zippath
    end

    -- Ensure .lua/ prefix for ZIP
    if not zippath:match("^%.lua/") then
      zippath = ".lua/" .. zippath
    end

    normalized[zippath] = content
  end

  return normalized
end

--------------------------------------------------------------------------------
-- Main Embed Functions
--------------------------------------------------------------------------------

function embed.install(package_name, output_path)
  log("Installing package: " .. package_name)

  -- Step 1: Find latest version
  log("Finding latest version...")
  local version = find_latest_version(package_name)
  log("Found version: " .. version)

  -- Step 2: Fetch rockspec
  log("Fetching rockspec...")
  local rockspec_content, author = fetch_rockspec(package_name, version)
  local rockspec_data = parse_rockspec(rockspec_content)

  -- Step 3: Find download URL
  log("Finding download URL...")
  local download_url = find_rock_download_url(rockspec_data, author, package_name, version)
  log("Download URL: " .. download_url)

  -- Step 4: Download package
  log("Downloading package...")
  local package_content = fetch_url(download_url)
  log("Downloaded " .. #package_content .. " bytes")

  -- Step 5: Extract Lua files
  log("Extracting Lua files...")
  local files = extract_lua_files_from_zip(package_content, package_name)
  local file_count = 0
  for _ in pairs(files) do file_count = file_count + 1 end
  log("Found " .. file_count .. " Lua files")

  if file_count == 0 then
    errorf("No Lua files found in package")
  end

  -- Step 6: Normalize paths for embedding
  log("Normalizing paths...")
  local normalized = normalize_paths(files, package_name)

  -- Debug: show what will be embedded
  log("Will embed:")
  for zippath in pairs(normalized) do
    log("  " .. zippath)
  end

  -- Step 7: Get current executable path
  local exe_path = get_executable_path()

  -- Step 8: Copy executable
  log("Copying executable to: " .. output_path)
  local src_fd = unix.open(exe_path, unix.O_RDONLY)
  if not src_fd then
    errorf("Failed to open source: %s", exe_path)
  end

  local stat = unix.fstat(src_fd)
  if not stat then
    unix.close(src_fd)
    errorf("Failed to stat source")
  end

  local dest_fd = unix.open(output_path, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0755)
  if not dest_fd then
    unix.close(src_fd)
    errorf("Failed to create destination: %s", output_path)
  end

  -- Copy in chunks
  local chunk_size = 65536
  local remaining = stat.size
  while remaining > 0 do
    local to_read = math.min(remaining, chunk_size)
    local chunk = unix.read(src_fd, to_read)
    if not chunk or #chunk == 0 then break end

    unix.write(dest_fd, chunk)
    remaining = remaining - #chunk
  end

  unix.close(src_fd)
  unix.close(dest_fd)

  -- Step 9: Append files to ZIP
  log("Embedding files...")
  local ok, err = pcall(append_to_zip, output_path, normalized)
  if not ok then
    unix.unlink(output_path)
    errorf("Failed to append files: %s", err)
  end

  log("Success! Created: " .. output_path)
  return true
end

return embed
