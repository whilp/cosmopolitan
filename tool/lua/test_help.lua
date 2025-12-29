-- Tests for the help module

local help = require("cosmo.help")

-- Test 1: help module loaded correctly
assert(type(help) == "table", "help should be a table")
assert(type(help.show) == "function", "help.show should be a function")
assert(type(help.search) == "function", "help.search should be a function")
assert(type(getmetatable(help).__call) == "function", "help should be callable")

-- Test 2: Definitions loaded
help.load()
assert(type(help._docs) == "table", "help._docs should be a table")
assert(help._docs["EncodeBase64"], "EncodeBase64 should be documented")
assert(help._docs["unix.fork"], "unix.fork should be documented")

-- Test 3: Documentation structure
local doc = help._docs["EncodeBase64"]
assert(doc.signature, "doc should have signature")
assert(doc.desc, "doc should have description")
assert(type(doc.params) == "table", "doc.params should be a table")
assert(type(doc.returns) == "table", "doc.returns should be a table")

-- Test 4: help.search works
local output = {}
local old_print = print
print = function(...) for _,v in ipairs({...}) do table.insert(output, tostring(v)) end end
help.search("base64")
print = old_print

assert(#output > 0, "help.search should produce output")
local found = false
for _, line in ipairs(output) do
  if line:lower():match("base64") then found = true end
end
assert(found, "search results should include base64 functions")

-- Test 5: Fetch includes proxy info
local fetch_doc = help._docs["Fetch"]
assert(fetch_doc, "Fetch should be documented")
assert(fetch_doc.desc:match("proxy"), "Fetch docs should mention proxy support")

-- Test 6: Unix module has many functions
local unix_count = 0
for name in pairs(help._docs) do
  if name:match("^unix%.") then unix_count = unix_count + 1 end
end
assert(unix_count >= 20, "should have at least 20 unix functions, got " .. unix_count)

print("all help tests passed")
