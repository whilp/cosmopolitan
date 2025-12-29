-- test skill module

local skill = require("cosmo.skill")

-- Test that module loads
assert(skill, "skill module should load")
assert(type(skill.install) == "function", "skill.install should be a function")
assert(type(skill.generate_docs) == "function", "skill.generate_docs should be a function")

-- Test doc generation
local docs, modules = skill.generate_docs()
assert(type(docs) == "table", "generate_docs should return docs table")
assert(type(modules) == "table", "generate_docs should return modules table")

-- Check that modules were discovered (for filtering)
assert(modules[""], "should discover top-level functions (empty prefix)")
assert(modules["unix"], "should discover unix module")
assert(modules["sqlite3"], "should discover sqlite3 module")

-- Check that SKILL.md was generated
assert(docs["SKILL.md"], "should generate SKILL.md")

-- Check SKILL.md has expected content
local content = docs["SKILL.md"]
assert(content:match("^%-%-%-"), "SKILL.md should start with frontmatter")
assert(content:match("name: cosmo%-lua"), "SKILL.md should have correct name")
assert(content:match("whilp/cosmopolitan"), "SKILL.md should reference whilp/cosmopolitan")
assert(content:match("cosmo%.Fetch"), "SKILL.md should document Fetch")
assert(content:match("cosmo%.DecodeJson"), "SKILL.md should document DecodeJson")
assert(content:match("cosmo%.unix"), "SKILL.md should document unix module")
assert(content:match("cosmo%.sqlite3"), "SKILL.md should document sqlite3 module")
assert(content:match("help%("), "SKILL.md should explain help system")

print("all skill tests passed")
