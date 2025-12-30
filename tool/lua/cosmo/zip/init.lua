-- cosmo.zip wrapper
-- Provides unified open(path, mode) API with append ("a") support

local cosmo = require("cosmo")
local unix = require("cosmo.unix")

-- Get the underlying C module
local czip = package.loaded["cosmo.zip.c"] or require("cosmo.zip.c")

local M = {}

-- Copy all functions from C module
for k, v in pairs(czip) do
  M[k] = v
end

-- Helper functions for writing ZIP structures
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

-- Appender metatable
local Appender = {}
Appender.__index = Appender
Appender.__name = "zip.Appender"

function Appender:__tostring()
  if self._closed then
    return "zip.Appender (closed)"
  else
    return string.format("zip.Appender (%d pending)", #self._entries)
  end
end

function Appender:add(name, content)
  if self._closed then
    return nil, "appender is closed"
  end
  table.insert(self._entries, {
    name = name,
    content = content,
    crc = cosmo.Crc32(0, content),
  })
  return true
end

local function write_local_file_header(fd, name, content, crc)
  local name_bytes = #name
  local data_bytes = #content
  local header =
    "\x50\x4B\x03\x04" ..
    pack_u16(20) ..       -- version needed
    pack_u16(0) ..        -- flags
    pack_u16(0) ..        -- compression method (store)
    pack_u16(0) ..        -- mod time
    pack_u16(0) ..        -- mod date
    pack_u32(crc) ..
    pack_u32(data_bytes) ..
    pack_u32(data_bytes) ..
    pack_u16(name_bytes) ..
    pack_u16(0)           -- extra field length
  unix.write(fd, header)
  unix.write(fd, name)
  unix.write(fd, content)
  return 30 + name_bytes + data_bytes
end

local function write_central_dir_entry(fd, name, content_size, crc, offset)
  local name_bytes = #name
  local header =
    "\x50\x4B\x01\x02" ..
    pack_u16((3 << 8) | 20) ..  -- version made by (Unix, 2.0)
    pack_u16(20) ..             -- version needed
    pack_u16(0) ..              -- flags
    pack_u16(0) ..              -- compression method
    pack_u16(0) ..              -- mod time
    pack_u16(0) ..              -- mod date
    pack_u32(crc) ..
    pack_u32(content_size) ..   -- compressed size
    pack_u32(content_size) ..   -- uncompressed size
    pack_u16(name_bytes) ..
    pack_u16(0) ..              -- extra field length
    pack_u16(0) ..              -- comment length
    pack_u16(0) ..              -- disk number
    pack_u16(0) ..              -- internal attrs
    pack_u32(0x81A40000) ..     -- external attrs (regular file, 0644)
    pack_u32(offset)
  unix.write(fd, header)
  unix.write(fd, name)
  return 46 + name_bytes
end

local function write_eocd(fd, num_entries, cdir_size, cdir_offset)
  local eocd =
    "\x50\x4B\x05\x06" ..
    pack_u16(0) ..            -- disk number
    pack_u16(0) ..            -- disk with cdir
    pack_u16(num_entries) ..  -- entries on this disk
    pack_u16(num_entries) ..  -- total entries
    pack_u32(cdir_size) ..
    pack_u32(cdir_offset) ..
    pack_u16(0)               -- comment length
  unix.write(fd, eocd)
end

function Appender:close()
  if self._closed then
    return true
  end
  self._closed = true

  if #self._entries == 0 then
    return true
  end

  local fd = unix.open(self._path, unix.O_WRONLY | unix.O_APPEND)
  if not fd then
    return nil, "failed to open file: " .. self._path
  end

  local stat = unix.fstat(fd)
  if not stat then
    unix.close(fd)
    return nil, "failed to stat file"
  end

  local offset = stat:size()
  local written_entries = {}

  for _, entry in ipairs(self._entries) do
    local size = write_local_file_header(fd, entry.name, entry.content, entry.crc)
    table.insert(written_entries, {
      name = entry.name,
      content_size = #entry.content,
      crc = entry.crc,
      offset = offset,
    })
    offset = offset + size
  end

  local cdir_offset = offset
  local cdir_size = 0
  for _, entry in ipairs(written_entries) do
    local size = write_central_dir_entry(
      fd,
      entry.name,
      entry.content_size,
      entry.crc,
      entry.offset
    )
    cdir_size = cdir_size + size
  end

  write_eocd(fd, #written_entries, cdir_size, cdir_offset)
  unix.close(fd)
  return true
end

Appender.__close = Appender.close
Appender.__gc = Appender.close

-- Unified open API
function M.open(path, mode, opts)
  mode = mode or "r"

  if mode == "r" then
    return czip.open(path, opts)
  elseif mode == "w" then
    return czip.create(path, opts)
  elseif mode == "a" then
    return setmetatable({
      _path = path,
      _entries = {},
      _closed = false,
    }, Appender)
  else
    return nil, "invalid mode: " .. mode .. " (use 'r', 'w', or 'a')"
  end
end

return M
