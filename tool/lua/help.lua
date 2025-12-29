-- help module for cosmo lua
-- Parses LuaLS-style definitions.lua and provides interactive help()

local help = {
  _docs = {},           -- name -> {desc, params, returns, signature}
  _funcs = {},          -- function reference -> name
  _loaded = false,
}

-- Check if a documented item is available at runtime
-- This filters out documented but not enabled items (modules, functions, etc.)
local function is_available(name)
  local ok, cosmo = pcall(require, "cosmo")
  if not ok or not cosmo then return false end

  -- Split the name into parts (e.g., "unix.fork" -> {"unix", "fork"})
  local parts = {}
  for part in name:gmatch("[^%.]+") do
    table.insert(parts, part)
  end

  if #parts == 0 then return false end

  -- Top-level function (e.g., "EncodeBase64")
  if #parts == 1 then
    return cosmo[parts[1]] ~= nil
  end

  -- Module function (e.g., "unix.fork") or class method (e.g., "sqlite3.Database.close")
  local current = cosmo[parts[1]]
  if current == nil then return false end

  -- For simple module.function, check if it exists
  if #parts == 2 then
    -- Could be a function or a class table
    return current[parts[2]] ~= nil
  end

  -- For module.Class.method (e.g., sqlite3.Database.close), we trust that
  -- if the module exists, its class methods are available. We can't easily
  -- check methods on userdata metatables without creating instances.
  -- Just verify the module is available.
  return true
end

-- Parse a definitions.lua file and extract documentation
local function parse_definitions(content)
  local docs = {}
  local current_desc = {}
  local current_params = {}
  local current_returns = {}
  local in_multiline_comment = false

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

    -- Skip other annotations (@nodiscard, @class, @overload, etc)
    if line:match("^%-%-%-@") then
      goto continue
    end

    -- Function declaration (supports both function Name.method() and function Name:method())
    local func_name = line:match("^function%s+([%w_%.]+)%s*%(")
    local method_name = nil
    if not func_name then
      -- Try method syntax: function Class:method()
      local class_name, meth_name = line:match("^function%s+([%w_%.]+):([%w_]+)%s*%(")
      if class_name and meth_name then
        func_name = class_name .. "." .. meth_name
        method_name = meth_name
      end
    end
    if func_name then
      -- Extract parameter list from the line
      local params_str = line:match("^function%s+[%w_%.]+[%.:][%w_]*%s*%(([^)]*)%)")
      if not params_str then
        params_str = line:match("^function%s+[%w_%.]+%s*%(([^)]*)%)")
      end

      -- Build the documentation entry
      docs[func_name] = {
        desc = table.concat(current_desc, "\n"),
        params = current_params,
        returns = current_returns,
        signature = func_name .. "(" .. (params_str or "") .. ")"
      }

      -- Reset for next function
      current_desc = {}
      current_params = {}
      current_returns = {}
    end

    -- Variable/constant declaration (for things like unix.O_RDONLY)
    local var_name = line:match("^([%w_%.]+)%s*=")
    if var_name and #current_desc > 0 then
      docs[var_name] = {
        desc = table.concat(current_desc, "\n"),
        params = {},
        returns = {},
        signature = var_name
      }
      current_desc = {}
      current_params = {}
      current_returns = {}
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

-- Load and parse a definitions file by module name
local function load_defs(modname)
  local path = package.searchpath(modname, package.path)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return parse_definitions(content)
end

-- Translate documentation names from upstream conventions to cosmo conventions
-- e.g., Database.close -> lsqlite3.Database.close
local function translate_name(name)
  -- Standalone class names belong to lsqlite3
  if name:match("^Database%.") or name:match("^Context%.") or name:match("^VM%.") then
    return "lsqlite3." .. name
  end
  return name
end

-- Load definitions and filter out unavailable items
local function load_definitions()
  if help._loaded then return end
  local all_docs = load_defs("definitions") or {}

  -- Translate names and filter out docs for items that aren't available at runtime
  help._docs = {}
  for name, doc in pairs(all_docs) do
    local translated = translate_name(name)
    -- Update signature to use translated name
    if translated ~= name then
      doc.signature = doc.signature:gsub("^" .. name:gsub("%.", "%%."), translated)
    end
    if is_available(translated) then
      help._docs[translated] = doc
    end
  end

  help._loaded = true
end

-- Public function to ensure definitions are loaded (for programmatic access)
function help.load()
  load_definitions()
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
  cosmo           - Encoding, hashing, compression, networking
  cosmo.unix      - POSIX system calls
  cosmo.path      - Path manipulation
  cosmo.re        - Regular expressions
  cosmo.lsqlite3  - SQLite database
  cosmo.argon2    - Password hashing

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

  -- Look up with fallback: cosmo.X -> X, cosmo.unix.X -> unix.X
  local function find_doc(n)
    if help._docs[n] then return help._docs[n], n end
    -- Try stripping cosmo. prefix
    local stripped = n:match("^cosmo%.(.+)$")
    if stripped and help._docs[stripped] then
      return help._docs[stripped], stripped
    end
    return nil
  end

  local doc, found_name = find_doc(name)
  if doc then
    print(format_doc(found_name, doc))
    return
  end

  -- Check if it's a module prefix (try both with and without cosmo.)
  local function is_module_prefix(prefix)
    local pattern = "^" .. prefix:gsub("%.", "%%.") .. "%."
    for dname in pairs(help._docs) do
      if dname:match(pattern) then return true end
    end
    return false
  end

  -- Special case: "cosmo" lists top-level functions (no dot in name)
  if name == "cosmo" then
    local items = {}
    local submodules = {}
    for dname, doc in pairs(help._docs) do
      if not dname:match("%.") then
        table.insert(items, {name = dname, signature = doc.signature})
      else
        local submod = dname:match("^([^%.]+)")
        if submod then submodules[submod] = true end
      end
    end
    table.sort(items, function(a, b) return a.name < b.name end)
    local lines = {"cosmo", ""}
    local submods = {}
    for submod in pairs(submodules) do table.insert(submods, submod) end
    if #submods > 0 then
      table.sort(submods)
      table.insert(lines, "Submodules:")
      for _, submod in ipairs(submods) do
        table.insert(lines, "  " .. submod)
      end
      table.insert(lines, "")
    end
    if #items > 0 then
      table.insert(lines, "Functions:")
      for _, item in ipairs(items) do
        table.insert(lines, "  " .. item.signature)
      end
    end
    print(table.concat(lines, "\n"))
    return
  end

  if is_module_prefix(name) then
    print(list_module(name))
    return
  end
  -- Try without cosmo. prefix
  local stripped = name:match("^cosmo%.(.+)$")
  if stripped and is_module_prefix(stripped) then
    print(list_module(name))  -- Keep original name for display
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

-- Lazy registration of cosmo module (called when help is first used)
local function ensure_registered()
  if not help._registered then
    local ok, cosmo = pcall(require, "cosmo")
    if ok and cosmo then
      help.register(cosmo, "cosmo")
      help._registered = true
    end
  end
end

-- Wrap show and search to ensure registration
local original_show = help.show
function help.show(what)
  ensure_registered()
  return original_show(what)
end

local original_search = help.search
function help.search(pattern)
  ensure_registered()
  return original_search(pattern)
end

return help
