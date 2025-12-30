local unix = require("cosmo.unix")
local cosmo = require("cosmo")
local zip = require("cosmo.zip")

local tmpdir = unix.mkdtemp("/tmp/test_embed_int_XXXXXX")
assert(tmpdir, "failed to create temp dir")

local function cleanup()
  os.execute("rm -rf " .. tmpdir)
end

local test_module_content = [[
local M = {}
M.name = "test-module"
M.version = "1.0.0"
function M.greet(name)
  return "Hello, " .. (name or "World") .. "!"
end
function M.add(a, b)
  return a + b
end
return M
]]

local module_path = tmpdir .. "/test-module.lua"
local zip_path = tmpdir .. "/test-package.zip"
local output_path = tmpdir .. "/test-embedded-lua"

local fd = unix.open(module_path, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
assert(fd, "failed to create test module")
unix.write(fd, test_module_content)
unix.close(fd)

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

fd = unix.open(module_path, unix.O_RDONLY)
local stat = unix.fstat(fd)
local content = unix.read(fd, stat:size())
unix.close(fd)

local filename = "lua/testmodule/init.lua"
local crc = cosmo.Crc32(0, content)

local lfh =
  "\x50\x4B\x03\x04" ..
  pack_u16(20) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u32(crc) ..
  pack_u32(#content) ..
  pack_u32(#content) ..
  pack_u16(#filename) ..
  pack_u16(0)

local cfh =
  "\x50\x4B\x01\x02" ..
  pack_u16((3 << 8) | 20) ..
  pack_u16(20) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u32(crc) ..
  pack_u32(#content) ..
  pack_u32(#content) ..
  pack_u16(#filename) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u32(0x81A40000) ..
  pack_u32(0)

local cdir_offset = #lfh + #filename + #content
local cdir_size = #cfh + #filename

local eocd =
  "\x50\x4B\x05\x06" ..
  pack_u16(0) ..
  pack_u16(0) ..
  pack_u16(1) ..
  pack_u16(1) ..
  pack_u32(cdir_size) ..
  pack_u32(cdir_offset) ..
  pack_u16(0)

local zip_content = lfh .. filename .. content .. cfh .. filename .. eocd

fd = unix.open(zip_path, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0644)
assert(fd, "failed to create ZIP package")
unix.write(fd, zip_content)
unix.close(fd)

local embed = require("cosmo.embed")
assert(embed, "embed module should exist")
assert(type(embed.install) == "function")

local function get_executable_path()
  local path = unix.readlink("/proc/self/exe")
  if path then
    return path
  end
  return arg[0] or arg[-1]
end

local exe_path = get_executable_path()
assert(exe_path, "failed to get executable path")

local src_fd = unix.open(exe_path, unix.O_RDONLY)
assert(src_fd, "failed to open source executable")
stat = unix.fstat(src_fd)
assert(stat, "failed to stat source")

local dst_fd = unix.open(output_path, unix.O_WRONLY | unix.O_CREAT | unix.O_TRUNC, 0755)
assert(dst_fd, "failed to create destination")

local chunk_size = 65536
local source_size = stat:size()
local remaining = source_size

while remaining > 0 do
  local to_read = math.min(remaining, chunk_size)
  local chunk = unix.read(src_fd, to_read)
  if not chunk or #chunk == 0 then break end
  unix.write(dst_fd, chunk)
  remaining = remaining - #chunk
end

unix.close(src_fd)
unix.close(dst_fd)

local zip_reader = zip.open(zip_path)
assert(zip_reader, "failed to open test package as ZIP")

local entries = zip_reader:list()
assert(#entries == 1, "ZIP should have 1 entry")

local lua_content = zip_reader:read(entries[1])
assert(lua_content, "failed to read entry from ZIP")
zip_reader:close()

local zipappend = require("cosmo.zip.append")
local ok, err = zipappend.append(output_path, {
  [".lua/testmodule/init.lua"] = lua_content
})
assert(ok, "failed to append: " .. tostring(err))

fd = unix.open(output_path, unix.O_RDONLY)
assert(fd, "failed to open embedded executable")
stat = unix.fstat(fd)
unix.close(fd)

assert(stat:size() > source_size, "embedded executable should be larger")
assert((stat:mode() & 0x40) ~= 0, "file should be executable")

local zip_reader_embedded = zip.open(output_path)
if zip_reader_embedded then
  local embedded_entries = zip_reader_embedded:list()
  local found = false
  for _, entry in ipairs(embedded_entries) do
    if entry == ".lua/testmodule/init.lua" then
      found = true
      local embedded_content = zip_reader_embedded:read(entry)
      assert(embedded_content, "failed to read embedded content")
      assert(#embedded_content == #lua_content, "content size mismatch")
      break
    end
  end
  assert(found, "embedded module not found in ZIP")
  zip_reader_embedded:close()
end

cleanup()
print("PASS")
