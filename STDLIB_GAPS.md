# Lua + Cosmo.* Standard Library Gap Analysis

Comparison of cosmo.* modules vs standard libraries in Python, Go, and Rust.

## Current Cosmo Modules

### Available (✓)

| Module | Functionality | Lines | Performance |
|--------|--------------|-------|-------------|
| **cosmo** (core) | HTTP client, JSON, encoding (base64/hex/url), hashing (MD5, SHA*), compression, UUID, random, CRC32, IP parsing | ~1300 | Excellent |
| **cosmo.unix** | 100+ POSIX syscalls: files, processes, sockets, signals, sandboxing | ~2000 | Native |
| **cosmo.path** | Path manipulation: join, dirname, basename, exists, isfile, isdir | ~200 | Fast |
| **cosmo.re** | POSIX regex: search, compile | ~150 | Native |
| **cosmo.lsqlite3** | SQLite 3.35.5 with full API | ~2855 | 400k queries/sec |
| **cosmo.argon2** | Argon2 password hashing | ~100 | Secure |
| **cosmo.maxmind** | IP geolocation (GeoIP) | ~300 | Fast |
| **cosmo.finger** | Device fingerprinting | ~200 | Fast |
| **cosmo.help** | Interactive help system | ~400 | N/A |
| **cosmo.skill** | Claude Code skill installer | ~300 | N/A |

### Redbean (Partial)

**redbean.c** (7317 lines) provides HTTP server with:
- Request handlers: `OnHttpRequest()`, `OnError()`, etc.
- Response API: `Write()`, `SetStatus()`, `SetHeader()`, `SetCookie()`
- Request API: `GetMethod()`, `GetPath()`, `GetParam()`, `GetBody()`, `GetHeader()`
- Asset management: `ServeAsset()`, `LoadAsset()`, `StoreAsset()`
- Built-in ZIP filesystem

**Issue**: Redbean is a standalone server binary, not a Lua module for programmatic use.

---

## Gap Analysis vs Python/Go/Rust

### 🔴 Critical Gaps (High Priority)

| Feature | Python | Go | Rust | Gap | Solution |
|---------|--------|----|----- |-----|----------|
| **HTTP Server** | ✓ http.server | ✓ net/http | ✓ std::net | ❌ | **Extract from redbean.c** |
| **Template Engine** | ✓ jinja2/mako | ✓ html/template | ✓ askama/tera | ❌ | Mustache/Handlebars in Lua |
| **CSV Parser** | ✓ csv | ✓ encoding/csv | ✓ csv crate | ❌ | Pure Lua or C wrapper |
| **HTML/XML Parser** | ✓ html.parser/lxml | ✓ encoding/xml | ✓ scraper/quick-xml | ❌ | Wrap libxml2 or Lua parser |
| **CLI Argument Parser** | ✓ argparse | ✓ flag | ✓ clap | ❌ | Pure Lua (like Penlight) |
| **Structured Logging** | ✓ logging | ✓ log/slog | ✓ log/tracing | ⚠️ (only syslog) | Pure Lua logger |
| **Archive (tar/zip API)** | ✓ tarfile/zipfile | ✓ archive/* | ✓ tar/zip | ⚠️ (ZIP exists, no API) | Expose redbean ZIP + tar |
| **Testing Framework** | ✓ unittest/pytest | ✓ testing | ✓ builtin tests | ❌ | Pure Lua (luaunit-style) |

### 🟡 Medium Priority Gaps

| Feature | Python | Go | Rust | Gap | Solution |
|---------|--------|----|----- |-----|----------|
| **Email/SMTP Client** | ✓ smtplib | ✓ net/smtp | ✓ lettre | ❌ | Lua SMTP over unix sockets |
| **Advanced Crypto** | ✓ cryptography | ✓ crypto/* | ✓ ring/rustls | ⚠️ (hashing only) | Wrap BoringSSL/OpenSSL |
| **Datetime Parsing** | ✓ datetime | ✓ time | ✓ chrono | ⚠️ (basic only) | Wrap strftime/strptime |
| **URL Routing** | ✓ flask/django | ✓ gorilla/mux | ✓ axum/actix | ⚠️ (basic Route()) | Lua web framework |
| **Form Parsing** | ✓ cgi/werkzeug | ✓ multipart | ✓ multipart | ❌ | Lua multipart parser |
| **WebSockets** | ✓ websockets | ✓ gorilla/websocket | ✓ tokio-tungstenite | ❌ | Extend redbean C code |
| **Session Management** | ✓ sessions | ✓ gorilla/sessions | ✓ tower-sessions | ❌ | Lua + SQLite backend |
| **INI/TOML/YAML** | ✓ configparser/pyyaml | ✓ toml | ✓ toml/serde_yaml | ❌ (JSON only) | Pure Lua parsers |
| **Buffered I/O** | ✓ io.BufferedReader | ✓ bufio | ✓ BufReader | ⚠️ (manual) | Lua wrapper |
| **Markdown Parser** | ✓ markdown | ✓ goldmark | ✓ pulldown-cmark | ❌ | Wrap cmark or Lua |

### 🟢 Low Priority / Async Features

| Feature | Python | Go | Rust | Gap | Solution |
|---------|--------|----|----- |-----|----------|
| **Threading** | ✓ threading | ✓ sync | ✓ std::thread | ⚠️ (fork only) | Wrap pthreads (see greenbean) |
| **Mutexes/Locks** | ✓ threading.Lock | ✓ sync.Mutex | ✓ std::sync::Mutex | ❌ | Wrap pthread mutexes |
| **Channels** | ✓ queue | ✓ chan | ✓ std::sync::mpsc | ❌ | Pure Lua or C impl |
| **Async/Await** | ✓ asyncio | ✓ goroutines | ✓ async/await | ❌ | Lua coroutines + epoll |
| **Connection Pooling** | ✓ pool | ✓ sync.Pool | ✓ deadpool | ❌ | Lua implementation |

### ✓ Already Covered

| Feature | Provided By |
|---------|-------------|
| HTTP Client | `cosmo.Fetch()` |
| JSON | `cosmo.EncodeJson()`, `DecodeJson()` |
| Base64/Hex/URL encoding | `cosmo.Encode*/Decode*()` |
| Regex | `cosmo.re` |
| Path operations | `cosmo.path` |
| File I/O | `cosmo.unix.*` |
| SQLite | `cosmo.lsqlite3` |
| Subprocess | `cosmo.unix.fork()`, `exec()` |
| Hashing | `cosmo.Md5()`, `Sha*()`, `Crc32()` |
| Compression | `cosmo.Compress()`, `Decompress()`, `Deflate()`, `Inflate()` |
| TCP/UDP sockets | `cosmo.unix.socket()`, `bind()`, `listen()`, `accept()`, `connect()` |
| Random | `cosmo.Rand64()`, `GetRandomBytes()`, `UuidV4()`, `UuidV7()` |
| Collections | Native Lua tables |
| Math | Native Lua math library |
| Temp files | `cosmo.unix.mkstemp()`, `mkdtemp()` |

---

## Proposed Solutions

### 1. 🎯 HTTP Server Module (Highest Priority)

**Problem**: Redbean provides HTTP serving, but only as a standalone server binary. No programmatic Lua API.

**Solution**: Extract redbean's HTTP server core into `cosmo.http` module.

**Resources Available**:
- `tool/net/redbean.c` (7317 lines) - Full HTTP/1.1 server with TLS
- `examples/greenbean.c` - Threaded server example with pthread
- Both show proper TCP server patterns

**Proposed API**:
```lua
local http = require("cosmo.http")

-- Create server
local server = http.Server({
    host = "0.0.0.0",
    port = 8080,
    threads = 4,  -- or fork-based workers
    tls = {
        cert = "server.crt",
        key = "server.key"
    }
})

-- Route handlers
server:route("GET", "/hello", function(req, res)
    res:setHeader("Content-Type", "text/plain")
    res:write("Hello, World!")
end)

server:route("POST", "/api/:id", function(req, res)
    local id = req.params.id
    local body = req:json()  -- Parse JSON body
    res:json({status = "ok", id = id})
end)

-- Middleware
server:use(function(req, res, next)
    print("Request:", req.method, req.path)
    next()
end)

-- Start server
server:listen()
```

**Implementation Path**:
1. Create `tool/net/lhttp.c` - C bindings for HTTP server
2. Port redbean's HTTP parsing, routing, and response logic
3. Support both fork-based (redbean) and thread-based (greenbean) concurrency
4. Expose as `cosmo.http` module
5. Add pure Lua web framework on top (routes, middleware, templates)

### 2. Template Engine

**Options**:
- **Pure Lua**: Implement Mustache (logic-less, simple)
- **C Wrapper**: Wrap cmark for Markdown, or Jinja2-like engine

**Proposed API**:
```lua
local template = require("cosmo.template")

local tmpl = template.compile([[
<html>
  <h1>{{title}}</h1>
  <ul>
  {{#items}}
    <li>{{name}}: {{value}}</li>
  {{/items}}
  </ul>
</html>
]])

local html = tmpl({
    title = "My Page",
    items = {
        {name = "foo", value = 1},
        {name = "bar", value = 2}
    }
})
```

**Implementation**: ~500 lines of Lua (Mustache parser + renderer)

### 3. CSV Parser

**Pure Lua implementation** (~200 lines):
```lua
local csv = require("cosmo.csv")

-- Read CSV
for row in csv.rows("data.csv") do
    print(row[1], row[2], row[3])
end

-- Parse string
local data = csv.parse("a,b,c\n1,2,3\n4,5,6")
-- Returns: {{"a","b","c"}, {"1","2","3"}, {"4","5","6"}}

-- Write CSV
csv.write("output.csv", {
    {"name", "age", "city"},
    {"Alice", 30, "NYC"},
    {"Bob", 25, "SF"}
})
```

### 4. HTML/XML Parser

**Options**:
- Wrap **libxml2** (already in cosmopolitan)
- Pure Lua SAX-style parser

**Proposed API**:
```lua
local xml = require("cosmo.xml")

local doc = xml.parse("<root><item id='1'>Hello</item></root>")
print(doc:find("//item[@id='1']"):text())  -- "Hello"

-- HTML parsing
local html = require("cosmo.html")
local doc = html.parse("<div><p>Text</p></div>")
for elem in doc:select("p") do
    print(elem:text())
end
```

### 5. CLI Argument Parser

**Pure Lua** (~300 lines):
```lua
local argparse = require("cosmo.argparse")

local parser = argparse.new("mytool", "Description of my tool")
parser:option("-v --verbose", "Enable verbose mode"):count()
parser:option("-o --output", "Output file"):required()
parser:argument("input", "Input files"):args("+")

local args = parser:parse()
print(args.verbose, args.output, args.input)
```

**Reference**: Lua-Penlight has good implementation to adapt

### 6. Structured Logging

**Pure Lua** (~200 lines):
```lua
local log = require("cosmo.log")

log.setLevel("INFO")
log.setOutput("app.log")  -- or stderr

log.info("Server starting", {port = 8080, workers = 4})
log.error("Database error", {error = err, query = sql})
log.debug("Request processed", {
    method = "GET",
    path = "/api/users",
    duration_ms = 45
})

-- Outputs JSON:
-- {"level":"INFO","msg":"Server starting","port":8080,"workers":4,"time":"2025-12-29T10:30:00Z"}
```

### 7. Archive API (tar/zip)

**ZIP**: Redbean already has ZIP support in `zip.c`. Expose it:
```lua
local zip = require("cosmo.zip")

-- Read
local z = zip.open("archive.zip")
for path, data in z:files() do
    print(path, #data)
end
local content = z:read("file.txt")

-- Write
local z = zip.create("new.zip")
z:add("file.txt", "content")
z:add("data.json", EncodeJson({key = "value"}))
z:close()
```

**TAR**: Implement pure Lua TAR reader/writer (~400 lines):
```lua
local tar = require("cosmo.tar")

for entry in tar.files("archive.tar.gz") do
    print(entry.name, entry.size, entry.mode)
    local data = entry:read()
end
```

### 8. Testing Framework

**Pure Lua** (~400 lines, luaunit-style):
```lua
local test = require("cosmo.test")

function test.test_addition()
    test.assertEquals(1 + 1, 2)
    test.assertTrue(1 < 2)
end

function test.test_http_server()
    local http = require("cosmo.http")
    -- ... test logic
    test.assertNotNil(http.Server)
end

-- Run: lua -l cosmo.test mytest.lua
test.run()
```

### 9. Advanced Crypto

**Wrap existing cosmopolitan crypto**:
```lua
local crypto = require("cosmo.crypto")

-- AES encryption
local key = crypto.randomBytes(32)
local iv = crypto.randomBytes(16)
local encrypted = crypto.aes256.encrypt(plaintext, key, iv)
local decrypted = crypto.aes256.decrypt(encrypted, key, iv)

-- RSA
local pubkey, privkey = crypto.rsa.generate(2048)
local signature = crypto.rsa.sign(data, privkey)
local valid = crypto.rsa.verify(data, signature, pubkey)

-- TLS client
local socket = crypto.tls.connect("example.com", 443)
socket:write("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
local response = socket:read()
```

### 10. Threading/Async

**Threading** (wrap pthreads like greenbean.c):
```lua
local thread = require("cosmo.thread")

local t = thread.create(function(arg)
    print("Worker thread:", arg)
    return arg * 2
end, 42)

local result = t:join()  -- Wait and get return value
```

**Async** (Lua coroutines + epoll/kqueue):
```lua
local async = require("cosmo.async")

async.run(function()
    local resp1 = async.fetch("http://example.com/1")
    local resp2 = async.fetch("http://example.com/2")
    -- Both requests run concurrently
    print(resp1.status, resp2.status)
end)
```

---

## Priority Roadmap

### Phase 1: Web Development Essentials (Highest Value)
1. **HTTP Server Module** (`cosmo.http`) - Extract from redbean
2. **Template Engine** (`cosmo.template`) - Pure Lua Mustache
3. **URL Routing** - Lua web framework on redbean
4. **Form Parsing** - Multipart/form-data support
5. **Session Management** - Cookie-based + SQLite storage

### Phase 2: Data & Parsing
6. **CSV Parser** (`cosmo.csv`) - Pure Lua
7. **HTML/XML Parser** (`cosmo.xml`, `cosmo.html`) - Wrap libxml2
8. **INI/TOML/YAML** - Pure Lua parsers
9. **Archive API** (`cosmo.zip`, `cosmo.tar`) - Expose existing + new

### Phase 3: Developer Experience
10. **CLI Argument Parser** (`cosmo.argparse`) - Pure Lua
11. **Structured Logging** (`cosmo.log`) - Pure Lua JSON logger
12. **Testing Framework** (`cosmo.test`) - Pure Lua
13. **Markdown Parser** (`cosmo.markdown`) - Wrap cmark

### Phase 4: Advanced Features
14. **Advanced Crypto** (`cosmo.crypto`) - Wrap BoringSSL
15. **Email/SMTP** (`cosmo.smtp`) - Pure Lua
16. **WebSockets** - Extend redbean
17. **Threading** (`cosmo.thread`) - Wrap pthreads
18. **Async/Await** (`cosmo.async`) - Coroutines + event loop

---

## Size Estimates

| Module | Implementation | Estimated Lines |
|--------|----------------|-----------------|
| cosmo.http | C + Lua | 2000 C + 500 Lua |
| cosmo.template | Pure Lua | 500 |
| cosmo.csv | Pure Lua | 200 |
| cosmo.xml/html | C wrapper | 800 C + 200 Lua |
| cosmo.argparse | Pure Lua | 300 |
| cosmo.log | Pure Lua | 200 |
| cosmo.zip | C bindings | 400 C |
| cosmo.tar | Pure Lua | 400 |
| cosmo.test | Pure Lua | 400 |
| cosmo.crypto | C wrapper | 1000 C |
| cosmo.smtp | Pure Lua | 600 |
| cosmo.thread | C wrapper | 300 C |
| cosmo.async | Lua + C | 800 Lua + 500 C |

**Total New Code**: ~6000 C + ~3100 Lua = **~9100 lines**

**Impact**: Brings cosmo to parity with Python/Go/Rust standard libraries for web development, CLI tools, and data processing.

---

## Existing Resources to Leverage

### From This Repository

1. **redbean.c** (7317 lines)
   - HTTP/1.1 server with TLS
   - Request parsing, routing, response handling
   - ZIP filesystem, asset serving
   - Worker process management

2. **greenbean.c** (example)
   - pthread-based server
   - Thread pool pattern
   - Atomic operations

3. **tool/net/zip.c**
   - ZIP reading/writing
   - PKZIP format support
   - Already integrated in redbean

4. **cosmopolitan libc crypto**
   - MD5, SHA*, CRC32 (exposed)
   - BoringSSL available (not exposed)
   - Argon2 (exposed)

5. **libxml2** (in third_party)
   - XML/HTML parsing
   - XPath support

6. **Lua 5.4**
   - Coroutines for async
   - Full metatable/OOP support
   - Fast JIT-friendly bytecode

### Pure Lua Libraries to Adapt

- **Penlight** - CLI parsing, templates, utils
- **LuaSocket** - HTTP patterns (already have sockets)
- **lua-cjson** patterns (already have JSON)
- **luaunit** - Testing framework patterns

---

## Conclusion

**Current State**: Cosmo has excellent low-level primitives (syscalls, sockets, SQLite, crypto hashing) but lacks high-level conveniences.

**Main Gap**: **HTTP server module** - This is the #1 priority. Redbean proves it's possible; we need to expose it as a Lua API.

**Quickest Wins** (Pure Lua, no C needed):
- CSV parser
- CLI argument parser
- Structured logging
- Template engine (Mustache)
- Testing framework

**Medium Effort** (C wrappers for existing code):
- HTTP server (extract from redbean)
- ZIP API (wrap existing zip.c)
- XML/HTML parser (wrap libxml2)
- Advanced crypto (wrap BoringSSL)
- Threading (wrap pthreads)

**Total Effort**: ~9000 lines of new code brings cosmo.* to full standard library parity with Python/Go/Rust for web development, CLI tools, and system programming.
