-- help module for cosmo lua
-- Parses LuaLS-style definitions.lua and provides interactive help()

local help = {
  _docs = {},           -- name -> {desc, params, returns, signature}
  _funcs = {},          -- function reference -> name
  _loaded = false,
  _module_order = {},   -- track module discovery order
}

-- Parse a definitions.lua file and extract documentation
local function parse_definitions(content)
  local docs = {}
  local current_desc = {}
  local current_params = {}
  local current_returns = {}
  local current_overloads = {}
  local in_multiline_comment = false
  local multiline_buffer = {}

  for line in content:gmatch("[^\n]+") do
    -- Skip the meta marker and error line
    if line:match("^%-%-%-@meta") or line:match("^error%(") then
      goto continue
    end

    -- Handle multiline comment blocks --[[ ... ]]
    if line:match("^%-%-%[%[") then
      in_multiline_comment = true
      goto continue
    end
    if line:match("^%]%]") then
      in_multiline_comment = false
      goto continue
    end
    if in_multiline_comment then
      goto continue
    end

    -- Description line (--- comment without @)
    local desc_text = line:match("^%-%-%-(.*)$")
    if desc_text and not desc_text:match("^@") then
      table.insert(current_desc, desc_text)
      goto continue
    end

    -- @param annotation
    local param_name, param_type, param_desc = line:match("^%-%-%-@param%s+([%w_]+%??)%s+([^%s]+)%s*(.*)")
    if param_name then
      table.insert(current_params, {
        name = param_name,
        type = param_type,
        desc = param_desc or ""
      })
      goto continue
    end

    -- @return annotation
    local ret_type, ret_desc = line:match("^%-%-%-@return%s+([^%s]+)%s*(.*)")
    if ret_type then
      table.insert(current_returns, {
        type = ret_type,
        desc = ret_desc or ""
      })
      goto continue
    end

    -- @overload annotation (store for reference)
    local overload = line:match("^%-%-%-@overload%s+(.+)")
    if overload then
      table.insert(current_overloads, overload)
      goto continue
    end

    -- Skip other annotations (@nodiscard, @class, etc)
    if line:match("^%-%-%-@") then
      goto continue
    end

    -- Function declaration
    local func_name = line:match("^function%s+([%w_%.]+)%s*%(")
    if func_name then
      -- Extract parameter list from the line
      local params_str = line:match("^function%s+[%w_%.]+%s*%(([^)]*)%)")

      -- Build the documentation entry
      docs[func_name] = {
        desc = table.concat(current_desc, "\n"),
        params = current_params,
        returns = current_returns,
        overloads = current_overloads,
        signature = func_name .. "(" .. (params_str or "") .. ")"
      }

      -- Reset for next function
      current_desc = {}
      current_params = {}
      current_returns = {}
      current_overloads = {}
    end

    -- Variable/constant declaration (for things like unix.O_RDONLY)
    local var_name = line:match("^([%w_%.]+)%s*=")
    if var_name and #current_desc > 0 then
      docs[var_name] = {
        desc = table.concat(current_desc, "\n"),
        params = {},
        returns = {},
        overloads = {},
        signature = var_name
      }
      current_desc = {}
      current_params = {}
      current_returns = {}
      current_overloads = {}
    end

    ::continue::
  end

  return docs
end

-- Format a documentation entry for display
local function format_doc(name, doc)
  local lines = {}

  -- Signature
  table.insert(lines, doc.signature)
  table.insert(lines, "")

  -- Description
  if doc.desc and doc.desc ~= "" then
    -- Clean up description - remove leading spaces from each line
    for desc_line in doc.desc:gmatch("[^\n]+") do
      table.insert(lines, desc_line:match("^%s*(.*)$"))
    end
    table.insert(lines, "")
  end

  -- Parameters
  if #doc.params > 0 then
    table.insert(lines, "Parameters:")
    for _, param in ipairs(doc.params) do
      local optional = param.name:match("%?$") and " (optional)" or ""
      local clean_name = param.name:gsub("%?$", "")
      if param.desc ~= "" then
        table.insert(lines, string.format("  %s (%s)%s: %s", clean_name, param.type, optional, param.desc))
      else
        table.insert(lines, string.format("  %s (%s)%s", clean_name, param.type, optional))
      end
    end
    table.insert(lines, "")
  end

  -- Returns
  if #doc.returns > 0 then
    table.insert(lines, "Returns:")
    for _, ret in ipairs(doc.returns) do
      if ret.desc ~= "" then
        table.insert(lines, string.format("  %s: %s", ret.type, ret.desc))
      else
        table.insert(lines, string.format("  %s", ret.type))
      end
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

-- Load definitions from file
local function load_definitions()
  if help._loaded then return end

  -- Find the definitions file relative to this module
  local info = debug.getinfo(1, "S")
  local this_file = info.source:match("^@(.+)$") or info.source
  local help_dir = this_file:match("(.+)/[^/]+$") or "."
  local def_path = help_dir .. "/definitions.lua"

  local f = io.open(def_path, "r")
  if not f then
    -- Try alternate locations
    local alternates = {
      "tool/lua/help/definitions.lua",
      "./help/definitions.lua",
    }
    for _, path in ipairs(alternates) do
      f = io.open(path, "r")
      if f then break end
    end
  end

  if f then
    local content = f:read("*a")
    f:close()
    help._docs = parse_definitions(content)
  end

  help._loaded = true
end

-- Register function->name mappings for help(func) support
function help.register(tbl, prefix)
  if type(tbl) ~= "table" then return end

  for name, val in pairs(tbl) do
    if type(val) == "function" then
      local fullname = prefix .. "." .. name
      help._funcs[val] = fullname
    elseif type(val) == "table" and name ~= "_G" and not name:match("^_") then
      help.register(val, prefix .. "." .. name)
    end
  end
end

-- List all documented items in a module
local function list_module(prefix)
  load_definitions()

  local items = {}
  local submodules = {}

  for name, doc in pairs(help._docs) do
    if name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)$") then
      local short = name:match("([^%.]+)$")
      table.insert(items, {name = short, signature = doc.signature})
    elseif name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)%.") then
      local submod = name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)")
      submodules[submod] = true
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)

  local lines = {prefix, ""}

  -- Show submodules first
  local submods = {}
  for submod in pairs(submodules) do
    table.insert(submods, submod)
  end
  if #submods > 0 then
    table.sort(submods)
    table.insert(lines, "Submodules:")
    for _, submod in ipairs(submods) do
      table.insert(lines, "  " .. prefix .. "." .. submod)
    end
    table.insert(lines, "")
  end

  -- Show functions
  if #items > 0 then
    table.insert(lines, "Functions:")
    for _, item in ipairs(items) do
      table.insert(lines, "  " .. item.signature)
    end
  end

  return table.concat(lines, "\n")
end

-- Main help function
function help.show(what)
  load_definitions()

  -- No argument: show overview
  if what == nil then
    local overview = [[
Cosmo Lua Help System

Modules:
  cosmo         - Encoding, hashing, compression, networking
  cosmo.unix    - POSIX system calls
  cosmo.path    - Path manipulation
  cosmo.re      - Regular expressions
  cosmo.sqlite3 - SQLite database
  cosmo.argon2  - Password hashing

Usage:
  help("cosmo")              - List module contents
  help("cosmo.Fetch")        - Show function documentation
  help(cosmo.Fetch)          - Same, using function reference
  help.search("base64")      - Search for matching functions
]]
    print(overview)
    return
  end

  local name

  -- Function reference
  if type(what) == "function" then
    name = help._funcs[what]
    if not name then
      print("No documentation found (function not registered)")
      return
    end
  -- String name
  elseif type(what) == "string" then
    name = what
  -- Table (module)
  elseif type(what) == "table" then
    -- Try to identify the module by checking a known function
    for func, fname in pairs(help._funcs) do
      local mod_name, func_name = fname:match("^(.+)%.([^%.]+)$")
      if mod_name and what[func_name] == func then
        print(list_module(mod_name))
        return
      end
    end
    print("No documentation found for this table")
    return
  else
    print("Usage: help(name) or help('module.function')")
    return
  end

  -- Look up exact match
  local doc = help._docs[name]
  if doc then
    print(format_doc(name, doc))
    return
  end

  -- Check if it's a module prefix
  local is_module = false
  for dname in pairs(help._docs) do
    if dname:match("^" .. name:gsub("%.", "%%.") .. "%.") then
      is_module = true
      break
    end
  end

  if is_module then
    print(list_module(name))
    return
  end

  print("No documentation found for: " .. tostring(name))
end

-- Search for functions matching a pattern
function help.search(pattern)
  load_definitions()

  pattern = pattern:lower()
  local matches = {}

  for name, doc in pairs(help._docs) do
    if name:lower():match(pattern) or doc.desc:lower():match(pattern) then
      table.insert(matches, name)
    end
  end

  table.sort(matches)

  if #matches == 0 then
    print("No matches for: " .. pattern)
  else
    print("Matches for '" .. pattern .. "':")
    for _, name in ipairs(matches) do
      print("  " .. name)
    end
  end
end

-- Make help callable directly
setmetatable(help, {
  __call = function(_, what)
    return help.show(what)
  end
})

return help
