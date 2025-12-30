local unix = require("cosmo.unix")
local zip = require("cosmo.zip")
local cosmo = require("cosmo")

local tmpdir = unix.mkdtemp("/tmp/test_embed_XXXXXX")
assert(tmpdir, "failed to create temp dir")

local function cleanup()
  os.execute("rm -rf " .. tmpdir)
end

local embed = require("cosmo.embed")
assert(embed, "embed module should exist")
assert(type(embed) == "table", "embed module should be a table")
assert(type(embed.install) == "function", "embed.install should be a function")

local luarocks = require("cosmo.embed.luarocks")
assert(luarocks, "luarocks module should exist")
assert(type(luarocks.find_package_info) == "function")
assert(type(luarocks.fetch_rockspec) == "function")
assert(type(luarocks.get_rock_url) == "function")
assert(type(luarocks.fetch_rock) == "function")

local zipappend = require("cosmo.zip.append")
assert(zipappend, "zip.append module should exist")
assert(type(zipappend.append) == "function")

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

local packed = pack_u16(0x1234)
assert(#packed == 2, "pack_u16 should produce 2 bytes")
assert(packed:byte(1) == 0x34, "pack_u16 byte 1")
assert(packed:byte(2) == 0x12, "pack_u16 byte 2")

packed = pack_u32(0x12345678)
assert(#packed == 4, "pack_u32 should produce 4 bytes")
assert(packed:byte(1) == 0x78, "pack_u32 byte 1")
assert(packed:byte(2) == 0x56, "pack_u32 byte 2")
assert(packed:byte(3) == 0x34, "pack_u32 byte 3")
assert(packed:byte(4) == 0x12, "pack_u32 byte 4")

local crc = cosmo.Crc32(0, "hello")
assert(type(crc) == "number", "CRC32 should return a number")
assert(crc > 0, "CRC32 should be positive")

local function normalize_path(path, package_name)
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
  return zippath
end

assert(normalize_path("testpkg/init.lua", "testpkg") == ".lua/testpkg/init.lua")
assert(normalize_path("testpkg-1.0/lua/testpkg/init.lua", "testpkg") == ".lua/testpkg/init.lua")
assert(normalize_path("lua/testpkg/utils.lua", "testpkg") == ".lua/testpkg/utils.lua")
assert(normalize_path("init.lua", "testpkg") == ".lua/testpkg/init.lua")

local function get_executable_path()
  return arg[-1] or arg[0]
end

local path = get_executable_path()
assert(path, "should detect executable path")
assert(type(path) == "string", "path should be a string")
assert(#path > 0, "path should not be empty")

local rockspec_content = [[
package = "testpkg"
version = "1.0-1"
source = {
  url = "https://example.com/testpkg-1.0.zip"
}
description = {
  summary = "Test package",
  license = "MIT"
}
dependencies = {
  "lua >= 5.1"
}
build = {
  type = "builtin",
  modules = {
    testpkg = "testpkg.lua"
  }
}
]]

local env = {
  package = {},
  version = nil,
  source = {},
  build = {},
  dependencies = {},
  description = {},
}

local chunk, err = load(rockspec_content, "rockspec", "t", env)
assert(chunk, "rockspec should parse: " .. tostring(err))

local ok, result = pcall(chunk)
assert(ok, "rockspec should execute: " .. tostring(result))
assert(env.package == "testpkg", "package name should be parsed")
assert(env.version == "1.0-1", "version should be parsed")
assert(env.source.url == "https://example.com/testpkg-1.0.zip", "source URL should be parsed")

cleanup()
print("PASS")
