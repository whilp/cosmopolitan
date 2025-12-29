-- skill module for cosmo lua
-- Generates and installs a Claude Code skill

local skill = {}

local SKILL_NAME = "cosmo-lua"

local SKILL_CONTENT = [[---
name: cosmo-lua
description: Use cosmopolitan Lua (cosmo-lua) for portable scripts. Includes HTTP, JSON, unix syscalls, path utils, regex, sqlite, argon2.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
---

# Cosmo Lua

Portable Lua 5.4 with batteries included. Single binary runs on Linux, macOS, Windows, FreeBSD, OpenBSD, NetBSD.

## Installation

```bash
curl -L -o lua https://github.com/whilp/cosmopolitan/releases/latest/download/lua
chmod +x lua
./lua --skill  # install this skill
```

## Getting Help

The executable has built-in documentation. Use the help module interactively or in scripts:

```bash
# Interactive REPL
./lua
> local help = require("cosmo.help")
> help()                      -- overview of all modules
> help("Fetch")               -- docs for a function
> help("unix")                -- list functions in a module
> help.search("socket")       -- search by keyword
```

```bash
# One-liner to look up a function
./lua -e 'require("cosmo.help")("Fetch")'
```

## Quick Reference

All functions are accessed via `local cosmo = require("cosmo")`.

### HTTP & Networking (replaces curl, luasocket)

| Function | Purpose |
|----------|---------|
| `cosmo.Fetch(url)` | HTTP GET/POST with redirects, TLS, proxy support |
| `cosmo.ResolveIp(host)` | DNS lookup |
| `cosmo.ParseUrl(url)` | Parse URL into components |
| `cosmo.FormatIp(ip)` | Format IP address |
| `cosmo.IsPublicIp(ip)` | Check if IP is public |

### JSON (replaces dkjson, cjson)

| Function | Purpose |
|----------|---------|
| `cosmo.DecodeJson(str)` | Parse JSON string to Lua table |
| `cosmo.EncodeJson(tbl)` | Encode Lua table to JSON string |

### Encoding & Hashing

| Function | Purpose |
|----------|---------|
| `cosmo.EncodeBase64(s)` | Base64 encode |
| `cosmo.DecodeBase64(s)` | Base64 decode |
| `cosmo.EncodeHex(s)` | Hex encode |
| `cosmo.DecodeHex(s)` | Hex decode |
| `cosmo.Sha256(s)` | SHA-256 hash |
| `cosmo.Sha1(s)` | SHA-1 hash |
| `cosmo.Md5(s)` | MD5 hash |
| `cosmo.GetRandomBytes(n)` | Cryptographic random bytes |

### Compression

| Function | Purpose |
|----------|---------|
| `cosmo.Deflate(s)` | Compress with zlib |
| `cosmo.Inflate(s)` | Decompress zlib |

### Path Utilities (replaces lfs path operations)

| Function | Purpose |
|----------|---------|
| `cosmo.path.join(...)` | Join path components |
| `cosmo.path.basename(p)` | Get filename from path |
| `cosmo.path.dirname(p)` | Get directory from path |
| `cosmo.path.exists(p)` | Check if path exists |
| `cosmo.path.isfile(p)` | Check if path is file |
| `cosmo.path.isdir(p)` | Check if path is directory |

### POSIX/Unix (replaces luaposix)

| Function | Purpose |
|----------|---------|
| `cosmo.unix.open(path, flags)` | Open file descriptor |
| `cosmo.unix.read(fd)` | Read from fd |
| `cosmo.unix.write(fd, data)` | Write to fd |
| `cosmo.unix.close(fd)` | Close fd |
| `cosmo.unix.fork()` | Fork process |
| `cosmo.unix.execve(prog, args)` | Execute program |
| `cosmo.unix.stat(path)` | Get file metadata |
| `cosmo.unix.environ()` | Get environment |
| `cosmo.unix.getpid()` | Get process ID |
| `cosmo.unix.sleep(secs)` | Sleep |
| `cosmo.unix.clock_gettime()` | High-resolution time |

See `help("unix")` for 100+ additional syscall wrappers.

### Regular Expressions (replaces lrexlib, PCRE)

| Function | Purpose |
|----------|---------|
| `cosmo.re.search(pattern, str)` | Search for pattern |
| `cosmo.re.compile(pattern)` | Compile regex for reuse |
| `regex:search(str)` | Search with compiled regex |

### SQLite (replaces lsqlite3)

| Function | Purpose |
|----------|---------|
| `cosmo.sqlite3.open(path)` | Open database |
| `cosmo.sqlite3.open_memory()` | Open in-memory database |
| `db:exec(sql)` | Execute SQL |
| `db:prepare(sql)` | Prepare statement |
| `stmt:step()` | Execute prepared statement |
| `db:close()` | Close database |

### Password Hashing

| Function | Purpose |
|----------|---------|
| `cosmo.argon2.hash_encoded(pw, salt)` | Hash password |
| `cosmo.argon2.verify(encoded, pw)` | Verify password |

## Example

```lua
local cosmo = require("cosmo")

-- Fetch JSON from an API
local status, headers, body = cosmo.Fetch("https://api.example.com/data")
if status == 200 then
  local data = cosmo.DecodeJson(body)
  print(data.message)
end

-- Work with files
local path = cosmo.path.join(os.getenv("HOME"), ".config", "app.json")
if cosmo.path.exists(path) then
  local f = io.open(path)
  local config = cosmo.DecodeJson(f:read("*a"))
  f:close()
end
```

## More Information

Use `help.search(keyword)` to find functions. The help system has complete documentation for all functions including parameters, return values, and examples.
]]

-- Write a file, creating parent directories as needed
local function write_file(path, content)
  local dir = path:match("(.+)/[^/]+$")
  if dir then
    os.execute('mkdir -p "' .. dir .. '"')
  end

  local f = io.open(path, "w")
  if not f then
    return nil, "failed to open file: " .. path
  end
  f:write(content)
  f:close()
  return true
end

-- Get the default skill installation path
local function default_path()
  local home = os.getenv("HOME")
  if not home then
    return nil, "HOME environment variable not set"
  end
  return home .. "/.claude/skills"
end

-- Generate docs (for test compatibility - returns empty modules now)
function skill.generate_docs()
  local help = require("cosmo.help")
  help.load()

  -- Discover module prefixes for test compatibility
  local modules = {}
  for name in pairs(help._docs) do
    local prefix = name:match("^([^%.]+)%.") or ""
    modules[prefix] = true
  end

  -- Return skill content as the only doc
  return {["SKILL.md"] = SKILL_CONTENT}, modules
end

-- Install skill to a directory
function skill.install(path)
  if not path then
    local default, err = default_path()
    if not default then
      return nil, err
    end
    path = default
  elseif path:sub(-1) ~= "/" then
    path = path .. "/.claude/skills"
  end

  local skill_dir = path .. "/" .. SKILL_NAME

  local ok, err = write_file(skill_dir .. "/SKILL.md", SKILL_CONTENT)
  if not ok then
    return nil, "failed to write SKILL.md: " .. err
  end

  io.write("installed skill to: " .. skill_dir .. "\n")
  return true
end

return skill
