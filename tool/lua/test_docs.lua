-- Tests for documentation accuracy
-- Verifies that:
--   a) All loadable modules are documented
--   b) All documented modules are loadable (via runtime filtering)
--   c) Unavailable modules are filtered out at runtime

local cosmo = require("cosmo")
local help = require("cosmo.help")
local skill = require("cosmo.skill")

-- Load the help documentation
help.load()

-- Test 1: Get all documented module prefixes after runtime filtering
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
  sqlite3 = true,
}

-- Get documented prefixes (after runtime filtering)
local documented = get_documented_prefixes()
print("Documented prefixes (after runtime filtering):")
for prefix in pairs(documented) do
  print("  - " .. prefix)
end
print()

local failed = false

-- Test 2: Every documented prefix should be a loadable module
print("Test: Documented modules should match loadable modules")
for prefix in pairs(documented) do
  if not EXPECTED_MODULES[prefix] then
    print("  FAIL: '" .. prefix .. "' is documented but not a loadable module")
    failed = true
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

-- Test 4: Verify the modules are actually loadable from cosmo
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

-- Test 5: Verify runtime filtering works (unavailable modules are filtered out)
print()
print("Test: Unavailable modules are filtered out at runtime")

-- These modules are documented in definitions.lua but not enabled in the lua binary
local UNAVAILABLE_MODULES = {"maxmind", "finger"}

for _, modname in ipairs(UNAVAILABLE_MODULES) do
  -- Check it's not in cosmo
  if cosmo[modname] ~= nil then
    print("  SKIP: '" .. modname .. "' is now available (test needs update)")
  else
    -- Check it's filtered out of help._docs
    local found = false
    for name in pairs(help._docs) do
      if name:match("^" .. modname .. "%.") then
        found = true
        break
      end
    end
    if found then
      print("  FAIL: '" .. modname .. "' is not available but still in help._docs")
      failed = true
    else
      print("  OK: '" .. modname .. "' is correctly filtered out")
    end
  end
end

-- Test 6: Skill generation should only produce docs for valid modules
print()
print("Test: Skill generates docs only for valid modules")
local docs, modules = skill.generate_docs()

for prefix in pairs(modules) do
  if prefix ~= "" then  -- empty prefix is top-level functions
    if not EXPECTED_MODULES[prefix] then
      print("  FAIL: skill generates docs for unknown module '" .. prefix .. "'")
      failed = true
    else
      print("  OK: skill generates docs for '" .. prefix .. "'")
    end
  end
end

-- Test 7: Check for undocumented functions (warnings, not failures)
print()
print("Test: Check for undocumented functions")
local undocumented = {}

-- Check top-level functions
for name, val in pairs(cosmo) do
  if type(val) == "function" then
    if not help._docs[name] then
      table.insert(undocumented, "cosmo." .. name)
    end
  end
end

-- Check module functions (not class methods - those are on metatables)
-- Skip internal functions like __newindex
for modname in pairs(EXPECTED_MODULES) do
  local mod = cosmo[modname]
  if mod and type(mod) == "table" then
    for name, val in pairs(mod) do
      if type(val) == "function" and not name:match("^__") then
        local fullname = modname .. "." .. name
        if not help._docs[fullname] then
          table.insert(undocumented, "cosmo." .. fullname)
        end
      end
    end
  end
end

if #undocumented > 0 then
  table.sort(undocumented)
  print("  WARNING: " .. #undocumented .. " undocumented functions found:")
  for _, name in ipairs(undocumented) do
    print("    - " .. name)
  end
else
  print("  OK: all available functions are documented")
end

-- Test 8: Check that sqlite3 docs exist (not lsqlite3)
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
