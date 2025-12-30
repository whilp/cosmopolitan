local unix = require("cosmo.unix")
local zip = require("cosmo.zip")
local cosmo = require("cosmo")

local tmpdir = unix.mkdtemp("/tmp/test_embed_XXXXXX")
assert(tmpdir, "failed to create temp dir")

local function cleanup()
  unix.rmrf(tmpdir)
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
assert(type(zipappend.pack_u16) == "function")
assert(type(zipappend.pack_u32) == "function")

local packed = zipappend.pack_u16(0x1234)
assert(#packed == 2, "pack_u16 should produce 2 bytes")
assert(packed:byte(1) == 0x34, "pack_u16 byte 1")
assert(packed:byte(2) == 0x12, "pack_u16 byte 2")

packed = zipappend.pack_u32(0x12345678)
assert(#packed == 4, "pack_u32 should produce 4 bytes")
assert(packed:byte(1) == 0x78, "pack_u32 byte 1")
assert(packed:byte(2) == 0x56, "pack_u32 byte 2")
assert(packed:byte(3) == 0x34, "pack_u32 byte 3")
assert(packed:byte(4) == 0x12, "pack_u32 byte 4")

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
