-- Tests for documentation accuracy
local cosmo = require("cosmo")
local help = require("cosmo.help")
local skill = require("cosmo.skill")

help.load()

local EXPECTED_MODULES = {
  unix = true, path = true, re = true, argon2 = true, sqlite3 = true,
}

local UNAVAILABLE_MODULES = {"maxmind", "finger"}

local KNOWN_UNDOCUMENTED = {
  Compress = true, Curve25519 = true, DecodeBase32 = true, EncodeBase32 = true,
  EscapeIp = true, HasControlCodes = true, HighwayHash64 = true,
  IsAcceptableHost = true, IsAcceptablePort = true, IsHeaderRepeatable = true,
  IsValidHttpToken = true, ParseHost = true, ParseParams = true, Uncompress = true,
  ["argon2.hash_len"] = true, ["argon2.m_cost"] = true, ["argon2.parallelism"] = true,
  ["argon2.t_cost"] = true, ["argon2.variant"] = true, ["sqlite3.config"] = true,
  ["unix.S_ISBLK"] = true, ["unix.S_ISCHR"] = true, ["unix.S_ISDIR"] = true,
  ["unix.S_ISFIFO"] = true, ["unix.S_ISLNK"] = true, ["unix.S_ISREG"] = true,
  ["unix.S_ISSOCK"] = true, ["unix.fstatfs"] = true, ["unix.major"] = true,
  ["unix.minor"] = true, ["unix.setfsgid"] = true, ["unix.sigpending"] = true,
  ["unix.statfs"] = true, ["unix.verynice"] = true,
}

local errors = {}

-- Get documented module prefixes
local documented = {}
for name in pairs(help._docs) do
  local prefix = name:match("^([^%.]+)%.") or ""
  if prefix ~= "" then documented[prefix] = true end
end

-- Check module correspondence
for prefix in pairs(documented) do
  if not EXPECTED_MODULES[prefix] then
    table.insert(errors, "'" .. prefix .. "' documented but not expected")
  end
end
for modname in pairs(EXPECTED_MODULES) do
  if not documented[modname] then
    table.insert(errors, "'" .. modname .. "' expected but not documented")
  end
  if type(cosmo[modname]) ~= "table" then
    table.insert(errors, "cosmo." .. modname .. " missing or not a table")
  end
end

-- Check unavailable modules are filtered
for _, modname in ipairs(UNAVAILABLE_MODULES) do
  if cosmo[modname] == nil then
    for name in pairs(help._docs) do
      if name:match("^" .. modname .. "%.") then
        table.insert(errors, "'" .. modname .. "' unavailable but in help._docs")
        break
      end
    end
  end
end

-- Check for new undocumented functions
local undocumented = {}
for name, val in pairs(cosmo) do
  if type(val) == "function" and not help._docs[name] and not KNOWN_UNDOCUMENTED[name] then
    table.insert(undocumented, name)
  end
end
for modname in pairs(EXPECTED_MODULES) do
  local mod = cosmo[modname]
  if mod and type(mod) == "table" then
    for name, val in pairs(mod) do
      if type(val) == "function" and not name:match("^__") then
        local fullname = modname .. "." .. name
        if not help._docs[fullname] and not KNOWN_UNDOCUMENTED[fullname] then
          table.insert(undocumented, fullname)
        end
      end
    end
  end
end
if #undocumented > 0 then
  table.sort(undocumented)
  table.insert(errors, "new undocumented: " .. table.concat(undocumented, ", "))
end

-- Check sqlite3 naming
local docs = skill.generate_docs()
if not docs["cosmo-sqlite3.md"] then
  table.insert(errors, "cosmo-sqlite3.md not generated")
end
if docs["cosmo-lsqlite3.md"] then
  table.insert(errors, "cosmo-lsqlite3.md should not exist")
end

-- Result
if #errors > 0 then
  for _, e in ipairs(errors) do print("FAIL: " .. e) end
  os.exit(1)
end
print("all docs tests passed")
