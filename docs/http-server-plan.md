# HTTP Server Module Implementation Plan

This document outlines the plan to expose redbean's HTTP server functionality as a composable Lua module.

## Architecture

```
┌─────────────────────────────────────────────┐
│  cosmo.http.serve()  - High-level API       │  Phase 2
│  Handler-based server like Go net/http      │
├─────────────────────────────────────────────┤
│  cosmo.http  - HTTP parsing/formatting      │  Phase 1
│  parse, format_response, format_request     │
├─────────────────────────────────────────────┤
│  unix.*  - Socket primitives (existing)     │  Already done
│  socket, bind, listen, accept, poll, etc    │
└─────────────────────────────────────────────┘
```

Socket primitives already exist in `unix.*` (from lunix.c):
- `unix.socket()`, `unix.bind()`, `unix.listen()`, `unix.accept()`
- `unix.recv()`, `unix.send()`, `unix.poll()`, `unix.close()`
- All constants: `AF_INET`, `SOCK_STREAM`, `POLLIN`, etc.

## Phase 1: HTTP Parsing/Formatting

Land the code from PR #32. Stateless HTTP primitives:

```lua
local http = require("cosmo.http")

-- Parse request
local req = http.parse("GET /path HTTP/1.1\r\nHost: localhost\r\n\r\n")
-- req = {method="GET", uri="/path", version=11, headers={Host="localhost"}}

-- Format response
local raw = http.format_response({
  status = 200,
  headers = {["Content-Type"] = "text/html"},
  body = "<h1>Hello</h1>"
})
```

**Functions:**
- `http.parse(raw)` → `{method, uri, version, headers, body}` or `nil, err`
- `http.parse_response(raw)` → `{status, message, headers, body}` or `nil, err`
- `http.format_response({status, headers, body})` → string
- `http.format_request({method, uri, headers, body})` → string
- `http.reason(status_code)` → string

**Files:**
- `tool/net/lhttp.c` - Core implementation
- `tool/net/lhttp.h` - Header
- `tool/lua/.lua/cosmo/http.lua` - LuaLS type definitions

## Phase 2: Server API

Inspired by Go's `http.ListenAndServe` and Axum's handler model.

### Simple Handler API

```lua
local http = require("cosmo.http")

-- Like Go's http.ListenAndServe(addr, handler)
http.serve(":8080", function(req)
  return {
    status = 200,
    headers = {["Content-Type"] = "text/plain"},
    body = "Hello, " .. req.uri
  }
end)
```

### With Options

```lua
http.serve({
  addr = "0.0.0.0:8080",  -- or host="0.0.0.0", port=8080
  backlog = 128,
  timeout = 30,
}, function(req)
  return {status = 200, body = "Hello"}
end)
```

### Future: Worker Modes

```lua
-- Fork workers (like redbean -w4)
http.serve({addr = ":8080", workers = 4}, handler)

-- Thread pool (like greenbean)
http.serve({addr = ":8080", threads = 4}, handler)
```

### Low-Level Control

For users who want more control, compose with unix.*:

```lua
local http = require("cosmo.http")
local unix = require("unix")

local fd = unix.socket(unix.AF_INET, unix.SOCK_STREAM)
unix.setsockopt(fd, unix.SOL_SOCKET, unix.SO_REUSEADDR, 1)
unix.bind(fd, 0, 8080)  -- INADDR_ANY, port 8080
unix.listen(fd, 128)

while true do
  local client, ip, port = unix.accept(fd)
  local raw = unix.recv(client, 65536)
  local req = http.parse(raw)

  local response = http.format_response({
    status = 200,
    body = "Hello from " .. req.uri
  })
  unix.send(client, response)
  unix.close(client)
end
```

## Implementation Notes

### Reuse from redbean.c:
- `GoodSocket()` for optimized socket creation (TCP_FASTOPEN, etc.)
- Incremental HTTP message parsing with buffer management
- Poll-based timeout handling

### Design decisions:
1. **Handler returns response table** - Like Axum's IntoResponse
2. **Options first, handler second** - Consistent with Go pattern
3. **Single-process default** - Simple model; workers/threads opt-in
4. **Builds on unix.*** - No duplicate socket primitives

### Future extensions (not in initial scope):
- TLS/SSL support (via mbedtls, like redbean)
- WebSocket upgrade
- HTTP/2
- Streaming responses
- Middleware composition

## Testing Strategy

- Phase 1: `tool/lua/test_http.lua` - Parse/format round-trips
- Phase 2: `tool/lua/test_http_server.lua` - Full server integration

## Phased Landing

1. **PR 1**: "Add cosmo.http module for HTTP parsing and formatting"
   - lhttp.c, lhttp.h, type definitions, tests

2. **PR 2**: "Add http.serve() for handler-based HTTP servers"
   - Server loop implementation, worker modes, tests
