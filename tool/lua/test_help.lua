-- Tests for the help module parser and functionality

local cosmo = require("cosmo")
local help = require("cosmo.help")

-- Test 1: help module loaded correctly
assert(type(help) == "table", "help should be a table")
assert(type(help.show) == "function", "help.show should be a function")
assert(type(help.search) == "function", "help.search should be a function")
assert(type(help.register) == "function", "help.register should be a function")

-- Test 2: help is callable
assert(type(getmetatable(help).__call) == "function", "help should be callable")

-- Test 3: Parser tests - parse a sample definitions string
-- We'll access the internal _docs after triggering a load
help("cosmo")  -- This triggers load_definitions
assert(type(help._docs) == "table", "help._docs should be a table after loading")

-- Test 4: Check that some functions are documented
assert(help._docs["cosmo.EncodeBase64"], "cosmo.EncodeBase64 should be documented")
assert(help._docs["cosmo.Fetch"], "cosmo.Fetch should be documented")
assert(help._docs["cosmo.unix.fork"], "cosmo.unix.fork should be documented")
assert(help._docs["cosmo.path.basename"], "cosmo.path.basename should be documented")

-- Test 5: Check documentation structure
local doc = help._docs["cosmo.EncodeBase64"]
assert(doc.signature, "doc should have signature")
assert(doc.desc, "doc should have description")
assert(type(doc.params) == "table", "doc.params should be a table")
assert(type(doc.returns) == "table", "doc.returns should be a table")

-- Test 6: Check parameter parsing
assert(#doc.params >= 1, "EncodeBase64 should have at least 1 parameter")
assert(doc.params[1].name == "data", "first param should be 'data'")
assert(doc.params[1].type == "string", "first param type should be 'string'")

-- Test 7: Check return parsing
assert(#doc.returns >= 1, "EncodeBase64 should have at least 1 return")
assert(doc.returns[1].type == "string", "return type should be 'string'")

-- Test 8: Function registration works
assert(help._funcs[cosmo.EncodeBase64] == "cosmo.EncodeBase64",
       "cosmo.EncodeBase64 should be registered")
assert(help._funcs[cosmo.unix.fork] == "cosmo.unix.fork",
       "cosmo.unix.fork should be registered")

-- Test 9: help(func) works with function reference
local output = {}
local old_print = print
print = function(...) for i,v in ipairs({...}) do table.insert(output, tostring(v)) end end

help(cosmo.EncodeBase64)
print = old_print

assert(#output > 0, "help(func) should produce output")
assert(output[1]:match("EncodeBase64"), "output should mention function name")

-- Test 10: help.search works
output = {}
print = function(...) for i,v in ipairs({...}) do table.insert(output, tostring(v)) end end

help.search("base64")
print = old_print

assert(#output > 0, "help.search should produce output")
local found_base64 = false
for _, line in ipairs(output) do
  if line:lower():match("base64") then found_base64 = true end
end
assert(found_base64, "search results should include base64 functions")

-- Test 11: Check Fetch documentation includes proxy info
local fetch_doc = help._docs["cosmo.Fetch"]
assert(fetch_doc, "cosmo.Fetch should be documented")
assert(fetch_doc.desc:match("proxy") or fetch_doc.desc:match("Proxy"),
       "Fetch docs should mention proxy support")

-- Test 12: Check unix module has many functions documented
local unix_count = 0
for name in pairs(help._docs) do
  if name:match("^cosmo%.unix%.") then unix_count = unix_count + 1 end
end
assert(unix_count >= 20, "should have at least 20 unix functions documented, got " .. unix_count)

print("all help tests passed")
