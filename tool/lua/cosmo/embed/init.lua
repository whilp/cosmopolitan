-- cosmo.embed - Embed pure Lua libraries into the Lua executable
-- Copyright 2025 Justine Alexandra Roberts Tunney
-- SPDX-License-Identifier: ISC

local embed = {}

local cosmo = require("cosmo")
local unix = require("cosmo.unix")
local zip = require("cosmo.zip")
local luarocks = require("cosmo.embed.luarocks")

local function log(msg)
  io.stderr:write(msg .. "\n")
  io.stderr:flush()
end

local function errorf(fmt, ...)
  error(string.format(fmt, ...))
end

local function get_executable_path()
  return arg[-1] or arg[0] or error("Cannot determine executable path")
end

local function extract_lua_files_from_zip(zip_content)
  local tmpdir = unix.mkdtemp("/tmp/cosmo-embed-XXXXXX")
  if not tmpdir then
    errorf("Failed to create temp directory")
  end
  local tmpfile = tmpdir .. "/package.zip"
  local fd = unix.open(tmpfile, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
  if not fd then
    unix.rmdir(tmpdir)
    errorf("Failed to create temp file")
  end
  unix.write(fd, zip_content)
  unix.close(fd)
  local reader, err = zip.open(tmpfile)
  if not reader then
    unix.unlink(tmpfile)
    unix.rmdir(tmpdir)
    errorf("Failed to open ZIP: %s", err)
  end
  local files = {}
  local entries = reader:list()
  for _, entry in ipairs(entries) do
    if entry:match("%.lua$") and not entry:match("/$") then
      local content, read_err = reader:read(entry)
      if content then
        files[entry] = content
      end
    end
  end
  reader:close()
  unix.unlink(tmpfile)
  unix.rmdir(tmpdir)
  return files
end

local function normalize_paths(files, package_name)
  local normalized = {}
  for path, content in pairs(files) do
    local zippath = path
    zippath = zippath:gsub("^[^/]+/lua/", "")
    zippath = zippath:gsub("^lua/", "")
    if not zippath:match("^" .. package_name .. "/") and
       not zippath:match("^" .. package_name .. "%.lua$") then
      zippath = package_name .. "/" .. zippath
    end
    if not zippath:match("^%.lua/") then
      zippath = ".lua/" .. zippath
    end
    normalized[zippath] = content
  end
  return normalized
end

local function copy_executable(src_path, dest_path)
  local src_fd = unix.open(src_path, unix.O_RDONLY)
  if not src_fd then
    errorf("Failed to open source: %s", src_path)
  end
  local stat = unix.fstat(src_fd)
  if not stat then
    unix.close(src_fd)
    errorf("Failed to stat source")
  end
  local dest_fd = unix.open(dest_path, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0755)
  if not dest_fd then
    unix.close(src_fd)
    errorf("Failed to create destination: %s", dest_path)
  end
  local chunk_size = 65536
  local remaining = stat:size()
  while remaining > 0 do
    local to_read = math.min(remaining, chunk_size)
    local chunk = unix.read(src_fd, to_read)
    if not chunk or #chunk == 0 then break end
    unix.write(dest_fd, chunk)
    remaining = remaining - #chunk
  end
  unix.close(src_fd)
  unix.close(dest_fd)
end

function embed.install(package_name, output_path)
  log("Installing package: " .. package_name)

  log("Finding package info...")
  local info = luarocks.find_package_info(package_name)
  log("Found: " .. info.author .. "/" .. package_name .. " v" .. info.version)

  log("Downloading package...")
  local package_content = luarocks.fetch_rock(info.author, package_name, info.version)
  log("Downloaded " .. #package_content .. " bytes")

  log("Extracting Lua files...")
  local files = extract_lua_files_from_zip(package_content)
  local file_count = 0
  for _ in pairs(files) do file_count = file_count + 1 end
  log("Found " .. file_count .. " Lua files")

  if file_count == 0 then
    errorf("No Lua files found in package")
  end

  log("Normalizing paths...")
  local normalized = normalize_paths(files, package_name)

  log("Will embed:")
  for zippath in pairs(normalized) do
    log("  " .. zippath)
  end

  local exe_path = get_executable_path()

  log("Copying executable to: " .. output_path)
  copy_executable(exe_path, output_path)

  log("Embedding files...")
  local zipappend = require("cosmo.zip.append")
  local ok, err = pcall(zipappend.append, output_path, normalized)
  if not ok then
    unix.unlink(output_path)
    errorf("Failed to append files: %s", err)
  end

  log("Success! Created: " .. output_path)
  return true
end

return embed
