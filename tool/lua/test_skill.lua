-- test skill module

local cosmo = require("cosmo")
local skill = require("cosmo.skill")
local unix = require("cosmo.unix")
local path = require("cosmo.path")

assert(skill, "skill module should load")
assert(type(skill.install) == "function", "skill.install should be a function")

-- Test install to temp directory
local suffix = cosmo.EncodeHex(cosmo.GetRandomBytes(3))
local tmpdir = path.join(os.getenv("TMPDIR") or "/tmp", "lua_" .. suffix)
local ok, err = skill.install(tmpdir .. "/")
assert(ok, "skill.install failed: " .. (err or ""))

-- Verify SKILL.md was created
local skill_file = path.join(tmpdir, "cosmo-lua", "SKILL.md")
local f = io.open(skill_file)
assert(f, "SKILL.md should exist")
local content = f:read("*a")
f:close()
assert(content:match("cosmo%-lua"), "SKILL.md should contain skill name")

-- Cleanup
unix.rmrf(tmpdir)

print("all skill tests passed")
