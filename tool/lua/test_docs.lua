-- Tests for documentation accuracy
-- Verifies that:
--   a) All loadable modules are documented
--   b) All documented modules are loadable

local cosmo = require("cosmo")
local help = require("cosmo.help")
local skill = require("cosmo.skill")

-- Load the help documentation
help.load()

-- Test 1: All documented module prefixes should correspond to loadable modules
-- Get all documented prefixes (module names)
local function get_documented_prefixes()
  local prefixes = {}
  for name in pairs(help._docs) do
    local prefix = name:match("^([^%.]+)%.") or ""
    if prefix ~= "" then
      prefixes[prefix] = true
    end
  end
  return prefixes
end

-- The modules that should be available in cosmo.* (from lcosmo.c)
local EXPECTED_MODULES = {
  unix = true,
  path = true,
  re = true,
  argon2 = true,
  sqlite3 = true,  -- Note: exposed as sqlite3, NOT lsqlite3
}

-- Get documented prefixes
local documented = get_documented_prefixes()
print("Documented prefixes:")
for prefix in pairs(documented) do
  print("  - " .. prefix)
end
print()

-- Test 2: Every documented prefix should be a loadable module or valid class
-- sqlite3.Database, unix.Dir, etc. are classes within their parent module
local KNOWN_CLASSES = {
  -- sqlite3 classes (now properly prefixed)
  ["sqlite3.Database"] = true,
  ["sqlite3.Statement"] = true,
  ["sqlite3.Context"] = true,
  ["sqlite3.Rebaser"] = true,
  ["sqlite3.Session"] = true,
  ["sqlite3.Iterator"] = true,
  ["sqlite3.VM"] = true,
  -- unix classes
  ["unix.Memory"] = true,
  ["unix.Dir"] = true,
  ["unix.Rusage"] = true,
  ["unix.Stat"] = true,
  ["unix.Sigset"] = true,
  ["unix.Errno"] = true,
  -- re classes
  ["re.Errno"] = true,
  ["re.Regex"] = true,
}

print("Test: Documented modules should match loadable modules")
local failed = false

for prefix in pairs(documented) do
  -- Check if this prefix corresponds to a loadable module
  local is_module = EXPECTED_MODULES[prefix]
  local is_class_prefix = false

  -- Check if this prefix is used by a known class (e.g., lsqlite3 in lsqlite3.Database)
  for class_name in pairs(KNOWN_CLASSES) do
    if class_name:match("^" .. prefix .. "%.") then
      is_class_prefix = true
      break
    end
  end

  if not is_module then
    if prefix == "lsqlite3" then
      print("  FAIL: 'lsqlite3' is documented but module is exposed as 'sqlite3'")
      failed = true
    elseif prefix == "maxmind" then
      print("  FAIL: 'maxmind' is documented but not enabled in lua binary")
      failed = true
    elseif prefix == "finger" then
      print("  FAIL: 'finger' is documented but not enabled in lua binary")
      failed = true
    elseif not is_class_prefix then
      print("  FAIL: '" .. prefix .. "' is documented but not a loadable module")
      failed = true
    end
  else
    print("  OK: '" .. prefix .. "' is documented and loadable")
  end
end

-- Test 3: Every expected module should be documented
print()
print("Test: All loadable modules should be documented")
for modname in pairs(EXPECTED_MODULES) do
  if not documented[modname] then
    print("  FAIL: '" .. modname .. "' is loadable but not documented")
    failed = true
  else
    print("  OK: '" .. modname .. "' is loadable and documented")
  end
end

-- Test 4: Verify the modules are actually loadable
print()
print("Test: Modules are actually loadable from cosmo")
for modname in pairs(EXPECTED_MODULES) do
  local mod = cosmo[modname]
  if mod == nil then
    print("  FAIL: cosmo." .. modname .. " is nil")
    failed = true
  elseif type(mod) ~= "table" then
    print("  FAIL: cosmo." .. modname .. " is not a table (got " .. type(mod) .. ")")
    failed = true
  else
    print("  OK: cosmo." .. modname .. " is loaded")
  end
end

-- Test 5: Skill generation should only produce docs for valid modules
print()
print("Test: Skill generates docs only for valid modules")
local docs, modules = skill.generate_docs()

-- Check that no invalid module prefixes are in the generated docs
for prefix in pairs(modules) do
  if prefix ~= "" then  -- empty prefix is top-level functions
    if prefix == "lsqlite3" then
      print("  FAIL: skill generates docs for 'lsqlite3' (should be 'sqlite3')")
      failed = true
    elseif prefix == "maxmind" then
      print("  FAIL: skill generates docs for 'maxmind' (not enabled)")
      failed = true
    elseif prefix == "finger" then
      print("  FAIL: skill generates docs for 'finger' (not enabled)")
      failed = true
    elseif not EXPECTED_MODULES[prefix] then
      print("  FAIL: skill generates docs for unknown module '" .. prefix .. "'")
      failed = true
    else
      print("  OK: skill generates docs for '" .. prefix .. "'")
    end
  end
end

-- Test 6: Check that sqlite3 docs exist (not lsqlite3)
print()
print("Test: sqlite3 documentation naming")
if docs["cosmo-sqlite3.md"] then
  print("  OK: cosmo-sqlite3.md is generated")
else
  print("  FAIL: cosmo-sqlite3.md is not generated")
  failed = true
end

if docs["cosmo-lsqlite3.md"] then
  print("  FAIL: cosmo-lsqlite3.md should not be generated (use sqlite3)")
  failed = true
else
  print("  OK: cosmo-lsqlite3.md is not generated")
end

-- Final result
print()
if failed then
  print("FAILED: Some documentation tests failed")
  os.exit(1)
else
  print("all docs tests passed")
end
