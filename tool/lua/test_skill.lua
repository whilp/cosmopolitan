-- test skill module

local skill = require("cosmo.skill")
local unix = require("cosmo.unix")

assert(skill, "skill module should load")
assert(type(skill.install) == "function", "skill.install should be a function")

-- Test install to temp directory
local tmpdir = (os.getenv("TMPDIR") or "/tmp") .. "/lua_" .. unix.getpid()
local ok, err = skill.install(tmpdir .. "/")
assert(ok, "skill.install failed: " .. (err or ""))

-- Verify SKILL.md was created
local f = io.open(tmpdir .. "/cosmo-lua/SKILL.md")
assert(f, "SKILL.md should exist")
local content = f:read("*a")
f:close()
assert(content:match("cosmo%-lua"), "SKILL.md should contain skill name")

-- Cleanup
os.remove(tmpdir .. "/cosmo-lua/SKILL.md")
os.remove(tmpdir .. "/cosmo-lua")
os.remove(tmpdir)

print("all skill tests passed")
