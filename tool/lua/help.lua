-- help module for cosmo lua
-- Parses LuaLS-style definitions.lua and provides interactive help()

local help = {
  _docs = {},           -- name -> {desc, params, returns, signature}
  _loaded = false,
}

-- Check if a documented item is available at runtime
local function is_available(name)
  local ok, cosmo = pcall(require, "cosmo")
  if not ok or not cosmo then return false end

  local parts = {}
  for part in name:gmatch("[^%.]+") do
    table.insert(parts, part)
  end

  if #parts == 0 then return false end

  -- Top-level function (e.g., "EncodeBase64")
  if #parts == 1 then
    return cosmo[parts[1]] ~= nil
  end

  -- Module function (e.g., "unix.fork")
  local sok, submod = pcall(require, "cosmo." .. parts[1])
  if not sok or not submod then return false end

  if #parts == 2 then
    return submod[parts[2]] ~= nil
  end

  -- For module.Class.method, trust module availability
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
    if line:match("^%-%-%-@meta") or line:match("^error%(") then
      goto continue
    end

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

    local desc_text = line:match("^%-%-%-(.*)$")
    if desc_text and not desc_text:match("^@") then
      table.insert(current_desc, desc_text)
      goto continue
    end

    local param_name, param_type, param_desc = line:match("^%-%-%-@param%s+([%w_]+%??)%s+([^%s]+)%s*(.*)")
    if param_name then
      table.insert(current_params, {
        name = param_name,
        type = param_type,
        desc = param_desc or ""
      })
      goto continue
    end

    local ret_type, ret_desc = line:match("^%-%-%-@return%s+([^%s]+)%s*(.*)")
    if ret_type then
      table.insert(current_returns, {
        type = ret_type,
        desc = ret_desc or ""
      })
      goto continue
    end

    if line:match("^%-%-%-@") then
      goto continue
    end

    local func_name = line:match("^function%s+([%w_%.]+)%s*%(")
    if not func_name then
      local class_name, meth_name = line:match("^function%s+([%w_%.]+):([%w_]+)%s*%(")
      if class_name and meth_name then
        func_name = class_name .. "." .. meth_name
      end
    end
    if func_name then
      local params_str = line:match("^function%s+[%w_%.]+[%.:][%w_]*%s*%(([^)]*)%)")
      if not params_str then
        params_str = line:match("^function%s+[%w_%.]+%s*%(([^)]*)%)")
      end

      docs[func_name] = {
        desc = table.concat(current_desc, "\n"),
        params = current_params,
        returns = current_returns,
        signature = func_name .. "(" .. (params_str or "") .. ")"
      }

      current_desc = {}
      current_params = {}
      current_returns = {}
    end

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

  table.insert(lines, doc.signature)
  table.insert(lines, "")

  if doc.desc and doc.desc ~= "" then
    for desc_line in doc.desc:gmatch("[^\n]+") do
      table.insert(lines, desc_line:match("^%s*(.*)$"))
    end
    table.insert(lines, "")
  end

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

-- Load and parse definitions file
local function load_defs(modname)
  local path = package.searchpath(modname, package.path)
  if not path then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  return parse_definitions(content)
end

-- Translate documentation names (e.g., Database.close -> lsqlite3.Database.close)
local function translate_name(name)
  if name:match("^Database%.") or name:match("^Context%.") or name:match("^VM%.") then
    return "lsqlite3." .. name
  end
  return name
end

-- Load definitions and filter out unavailable items
local function load_definitions()
  if help._loaded then return end
  local all_docs = load_defs("definitions") or {}

  help._docs = {}
  for name, doc in pairs(all_docs) do
    local translated = translate_name(name)
    if translated ~= name then
      doc.signature = doc.signature:gsub("^" .. name:gsub("%.", "%%."), translated)
    end
    if is_available(translated) then
      help._docs[translated] = doc
    end
  end

  help._loaded = true
end

-- Public function to ensure definitions are loaded
function help.load()
  load_definitions()
end

-- List all documented items in a module (or top-level for "cosmo")
local function list_module(prefix)
  load_definitions()

  local items = {}
  local submodules = {}
  local is_toplevel = (prefix == "cosmo")

  for name, doc in pairs(help._docs) do
    if is_toplevel then
      if not name:match("%.") then
        table.insert(items, {name = name, signature = doc.signature})
      else
        local submod = name:match("^([^%.]+)")
        if submod then submodules[submod] = true end
      end
    else
      if name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)$") then
        local short = name:match("([^%.]+)$")
        table.insert(items, {name = short, signature = doc.signature})
      elseif name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)%.") then
        local submod = name:match("^" .. prefix:gsub("%.", "%%.") .. "%.([^%.]+)")
        submodules[submod] = true
      end
    end
  end

  table.sort(items, function(a, b) return a.name < b.name end)

  local lines = {prefix, ""}

  local submods = {}
  for submod in pairs(submodules) do table.insert(submods, submod) end
  if #submods > 0 then
    table.sort(submods)
    table.insert(lines, "Submodules:")
    for _, submod in ipairs(submods) do
      table.insert(lines, "  " .. (is_toplevel and submod or (prefix .. "." .. submod)))
    end
    table.insert(lines, "")
  end

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
    print([[
Cosmo Lua Help System

Modules:
  cosmo           - Encoding, hashing, compression, networking
  cosmo.unix      - POSIX system calls
  cosmo.path      - Path manipulation
  cosmo.re        - Regular expressions
  cosmo.lsqlite3  - SQLite database
  cosmo.argon2    - Password hashing

Usage:
  help("cosmo")         - List module contents
  help("Fetch")         - Show function documentation
  help.search("base64") - Search for matching functions
]])
    return
  end

  if type(what) ~= "string" then
    print("Usage: help(name) or help('module.function')")
    return
  end

  -- Try direct lookup, then with cosmo. prefix stripped
  local doc = help._docs[what]
  local name = what
  if not doc then
    local stripped = what:match("^cosmo%.(.+)$")
    if stripped and help._docs[stripped] then
      doc = help._docs[stripped]
      name = stripped
    end
  end

  if doc then
    print(format_doc(name, doc))
    return
  end

  -- Check if it's a module prefix
  local function is_module_prefix(prefix)
    local pattern = "^" .. prefix:gsub("%.", "%%.") .. "%."
    for dname in pairs(help._docs) do
      if dname:match(pattern) then return true end
    end
    return false
  end

  if what == "cosmo" or is_module_prefix(what) then
    print(list_module(what))
    return
  end

  local stripped = what:match("^cosmo%.(.+)$")
  if stripped and is_module_prefix(stripped) then
    print(list_module(stripped))
    return
  end

  print("No documentation found for: " .. what)
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
