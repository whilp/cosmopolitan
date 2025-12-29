/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Cosmopolitan Contributors                                     │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for        │
│ any purpose with or without fee is hereby granted, provided that the        │
│ above copyright notice and this permission notice appear in all copies.     │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL               │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED               │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE            │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL        │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR       │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER              │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR            │
│ PERFORMANCE OF THIS SOFTWARE.                                               │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "tool/net/lhttp.h"
#include "libc/serialize.h"
#include "net/http/http.h"
#include "third_party/lua/cosmo.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"

/**
 * @fileoverview HTTP parsing and formatting module for Lua
 *
 * This module provides low-level HTTP primitives for building servers
 * and clients in Lua. It wraps Cosmopolitan's battle-tested HTTP parser
 * and provides simple formatting functions.
 *
 * Design goals:
 * - Provide low-level primitives for HTTP parsing and formatting
 * - Keep API simple and composable
 * - Designed to be extended with server framework in the future
 * - No global state - all operations are stateless
 */

// http.parse(raw_request_string)
//     ├─→ {method, uri, version, headers, body}
//     └─→ nil, error_message
//
// Parses an HTTP request into a Lua table. Returns nil on error.
// The input buffer must contain at least the complete headers.
//
// Example:
//   local req = http.parse("GET /path HTTP/1.1\r\nHost: localhost\r\n\r\n")
//   print(req.method)  -- "GET"
//   print(req.uri)     -- "/path"
//   print(req.headers.Host)  -- "localhost"
static int LuaHttpParse(lua_State *L) {
  size_t len;
  const char *buf = luaL_checklstring(L, 1, &len);

  struct HttpMessage msg;
  InitHttpMessage(&msg, kHttpRequest);

  int rc = ParseHttpMessage(&msg, buf, len, len);
  if (rc <= 0) {
    DestroyHttpMessage(&msg);
    lua_pushnil(L);
    lua_pushstring(L, rc == 0 ? "incomplete message" : "parse error");
    return 2;
  }

  // Build result table
  lua_newtable(L);

  // method: "GET", "POST", "PUT", etc.
  char method[9] = {0};
  WRITE64LE(method, msg.method);
  lua_pushstring(L, method);
  lua_setfield(L, -2, "method");

  // uri: "/path?query#fragment"
  lua_pushlstring(L, buf + msg.uri.a, msg.uri.b - msg.uri.a);
  lua_setfield(L, -2, "uri");

  // version: 11 for HTTP/1.1, 10 for HTTP/1.0, 9 for HTTP/0.9
  lua_pushinteger(L, msg.version);
  lua_setfield(L, -2, "version");

  // headers: table of header name -> value
  lua_newtable(L);

  // Standard headers (optimized with integer keys in C)
  for (int i = 0; i < kHttpHeadersMax; i++) {
    if (msg.headers[i].a) {
      const char *name = GetHttpHeaderName(i);
      lua_pushlstring(L, buf + msg.headers[i].a,
                      msg.headers[i].b - msg.headers[i].a);
      lua_setfield(L, -2, name);
    }
  }

  // Extra headers (non-standard headers stored separately)
  for (unsigned i = 0; i < msg.xheaders.n; i++) {
    lua_pushlstring(L, buf + msg.xheaders.p[i].v.a,
                    msg.xheaders.p[i].v.b - msg.xheaders.p[i].v.a);
    lua_pushlstring(L, buf + msg.xheaders.p[i].k.a,
                    msg.xheaders.p[i].k.b - msg.xheaders.p[i].k.a);
    lua_settable(L, -3);
  }
  lua_setfield(L, -2, "headers");

  // body: everything after headers (may be empty)
  // Note: For chunked encoding or large bodies, future server framework
  // can provide streaming APIs. This is the simple case.
  if (rc < (int)len) {
    lua_pushlstring(L, buf + rc, len - rc);
    lua_setfield(L, -2, "body");
  }

  // header_size: size of headers in bytes (useful for streaming)
  lua_pushinteger(L, rc);
  lua_setfield(L, -2, "header_size");

  DestroyHttpMessage(&msg);
  return 1;
}

// http.parse_response(raw_response_string)
//     ├─→ {status, message, version, headers, body}
//     └─→ nil, error_message
//
// Parses an HTTP response into a Lua table.
static int LuaHttpParseResponse(lua_State *L) {
  size_t len;
  const char *buf = luaL_checklstring(L, 1, &len);

  struct HttpMessage msg;
  InitHttpMessage(&msg, kHttpResponse);

  int rc = ParseHttpMessage(&msg, buf, len, len);
  if (rc <= 0) {
    DestroyHttpMessage(&msg);
    lua_pushnil(L);
    lua_pushstring(L, rc == 0 ? "incomplete message" : "parse error");
    return 2;
  }

  lua_newtable(L);

  // status: 200, 404, etc.
  lua_pushinteger(L, msg.status);
  lua_setfield(L, -2, "status");

  // message: "OK", "Not Found", etc.
  lua_pushlstring(L, buf + msg.message.a, msg.message.b - msg.message.a);
  lua_setfield(L, -2, "message");

  // version: 11 for HTTP/1.1, 10 for HTTP/1.0
  lua_pushinteger(L, msg.version);
  lua_setfield(L, -2, "version");

  // headers
  lua_newtable(L);
  for (int i = 0; i < kHttpHeadersMax; i++) {
    if (msg.headers[i].a) {
      const char *name = GetHttpHeaderName(i);
      lua_pushlstring(L, buf + msg.headers[i].a,
                      msg.headers[i].b - msg.headers[i].a);
      lua_setfield(L, -2, name);
    }
  }
  for (unsigned i = 0; i < msg.xheaders.n; i++) {
    lua_pushlstring(L, buf + msg.xheaders.p[i].v.a,
                    msg.xheaders.p[i].v.b - msg.xheaders.p[i].v.a);
    lua_pushlstring(L, buf + msg.xheaders.p[i].k.a,
                    msg.xheaders.p[i].k.b - msg.xheaders.p[i].k.a);
    lua_settable(L, -3);
  }
  lua_setfield(L, -2, "headers");

  // body
  if (rc < (int)len) {
    lua_pushlstring(L, buf + rc, len - rc);
    lua_setfield(L, -2, "body");
  }

  lua_pushinteger(L, rc);
  lua_setfield(L, -2, "header_size");

  DestroyHttpMessage(&msg);
  return 1;
}

// http.format_response(response_table) -> string
//
// Formats a response table into an HTTP response string.
// Table format: {status=200, headers={...}, body="..."}
//
// Example:
//   local resp = http.format_response({
//     status = 200,
//     headers = {["Content-Type"] = "text/html"},
//     body = "<h1>Hello</h1>"
//   })
static int LuaHttpFormatResponse(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);

  // Get status code (default 200)
  lua_getfield(L, 1, "status");
  int status = luaL_optinteger(L, -1, 200);
  lua_pop(L, 1);

  luaL_Buffer b;
  luaL_buffinit(L, &b);

  // Status line: "HTTP/1.1 200 OK\r\n"
  luaL_addstring(&b, "HTTP/1.1 ");
  char status_str[32];
  snprintf(status_str, sizeof(status_str), "%d ", status);
  luaL_addstring(&b, status_str);
  luaL_addstring(&b, GetHttpReason(status));
  luaL_addstring(&b, "\r\n");

  // Headers
  lua_getfield(L, 1, "headers");
  if (lua_istable(L, -1)) {
    lua_pushnil(L);
    while (lua_next(L, -2)) {
      const char *key = lua_tostring(L, -2);
      const char *val = lua_tostring(L, -1);
      if (key && val) {
        luaL_addstring(&b, key);
        luaL_addstring(&b, ": ");
        luaL_addstring(&b, val);
        luaL_addstring(&b, "\r\n");
      }
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);

  // End of headers
  luaL_addstring(&b, "\r\n");

  // Body
  lua_getfield(L, 1, "body");
  if (lua_isstring(L, -1)) {
    size_t body_len;
    const char *body = lua_tolstring(L, -1, &body_len);
    luaL_addlstring(&b, body, body_len);
  }
  lua_pop(L, 1);

  luaL_pushresult(&b);
  return 1;
}

// http.format_request(request_table) -> string
//
// Formats a request table into an HTTP request string.
// Table format: {method="GET", uri="/path", headers={...}, body="..."}
//
// Useful for HTTP clients.
static int LuaHttpFormatRequest(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);

  // Get method (default "GET")
  lua_getfield(L, 1, "method");
  const char *method = luaL_optstring(L, -1, "GET");
  lua_pop(L, 1);

  // Get URI (required)
  lua_getfield(L, 1, "uri");
  const char *uri = luaL_checkstring(L, -1);
  lua_pop(L, 1);

  luaL_Buffer b;
  luaL_buffinit(L, &b);

  // Request line: "GET /path HTTP/1.1\r\n"
  luaL_addstring(&b, method);
  luaL_addstring(&b, " ");
  luaL_addstring(&b, uri);
  luaL_addstring(&b, " HTTP/1.1\r\n");

  // Headers
  lua_getfield(L, 1, "headers");
  if (lua_istable(L, -1)) {
    lua_pushnil(L);
    while (lua_next(L, -2)) {
      const char *key = lua_tostring(L, -2);
      const char *val = lua_tostring(L, -1);
      if (key && val) {
        luaL_addstring(&b, key);
        luaL_addstring(&b, ": ");
        luaL_addstring(&b, val);
        luaL_addstring(&b, "\r\n");
      }
      lua_pop(L, 1);
    }
  }
  lua_pop(L, 1);

  // End of headers
  luaL_addstring(&b, "\r\n");

  // Body
  lua_getfield(L, 1, "body");
  if (lua_isstring(L, -1)) {
    size_t body_len;
    const char *body = lua_tolstring(L, -1, &body_len);
    luaL_addlstring(&b, body, body_len);
  }
  lua_pop(L, 1);

  luaL_pushresult(&b);
  return 1;
}

// http.reason(status_code) -> reason_string
//
// Returns the standard reason phrase for an HTTP status code.
// Example: http.reason(200) -> "OK"
static int LuaHttpReason(lua_State *L) {
  int status = luaL_checkinteger(L, 1);
  lua_pushstring(L, GetHttpReason(status));
  return 1;
}

// http.header_name(header_constant) -> string
//
// Returns the header name for a header constant.
// Useful for working with the kHttp* constants.
static int LuaHttpHeaderName(lua_State *L) {
  int header = luaL_checkinteger(L, 1);
  if (header >= 0 && header < kHttpHeadersMax) {
    lua_pushstring(L, GetHttpHeaderName(header));
    return 1;
  }
  lua_pushnil(L);
  return 1;
}

static const luaL_Reg kLuaHttp[] = {
    {"parse", LuaHttpParse},
    {"parse_response", LuaHttpParseResponse},
    {"format_response", LuaHttpFormatResponse},
    {"format_request", LuaHttpFormatRequest},
    {"reason", LuaHttpReason},
    {"header_name", LuaHttpHeaderName},
    {0},
};

int LuaHttp(lua_State *L) {
  luaL_newlib(L, kLuaHttp);

  // HTTP Method constants (as 64-bit integers for comparison)
  lua_pushinteger(L, kHttpGet);
  lua_setfield(L, -2, "GET");
  lua_pushinteger(L, kHttpPost);
  lua_setfield(L, -2, "POST");
  lua_pushinteger(L, kHttpPut);
  lua_setfield(L, -2, "PUT");
  lua_pushinteger(L, kHttpDelete);
  lua_setfield(L, -2, "DELETE");
  lua_pushinteger(L, kHttpHead);
  lua_setfield(L, -2, "HEAD");
  lua_pushinteger(L, kHttpOptions);
  lua_setfield(L, -2, "OPTIONS");
  lua_pushinteger(L, kHttpConnect);
  lua_setfield(L, -2, "CONNECT");
  lua_pushinteger(L, kHttpTrace);
  lua_setfield(L, -2, "TRACE");

  // Common HTTP status codes
  lua_pushinteger(L, 200);
  lua_setfield(L, -2, "OK");
  lua_pushinteger(L, 201);
  lua_setfield(L, -2, "CREATED");
  lua_pushinteger(L, 204);
  lua_setfield(L, -2, "NO_CONTENT");
  lua_pushinteger(L, 301);
  lua_setfield(L, -2, "MOVED_PERMANENTLY");
  lua_pushinteger(L, 302);
  lua_setfield(L, -2, "FOUND");
  lua_pushinteger(L, 304);
  lua_setfield(L, -2, "NOT_MODIFIED");
  lua_pushinteger(L, 400);
  lua_setfield(L, -2, "BAD_REQUEST");
  lua_pushinteger(L, 401);
  lua_setfield(L, -2, "UNAUTHORIZED");
  lua_pushinteger(L, 403);
  lua_setfield(L, -2, "FORBIDDEN");
  lua_pushinteger(L, 404);
  lua_setfield(L, -2, "NOT_FOUND");
  lua_pushinteger(L, 405);
  lua_setfield(L, -2, "METHOD_NOT_ALLOWED");
  lua_pushinteger(L, 500);
  lua_setfield(L, -2, "INTERNAL_SERVER_ERROR");
  lua_pushinteger(L, 502);
  lua_setfield(L, -2, "BAD_GATEWAY");
  lua_pushinteger(L, 503);
  lua_setfield(L, -2, "SERVICE_UNAVAILABLE");

  // Header name constants (for efficient header access)
  lua_pushinteger(L, kHttpHost);
  lua_setfield(L, -2, "HOST");
  lua_pushinteger(L, kHttpContentType);
  lua_setfield(L, -2, "CONTENT_TYPE");
  lua_pushinteger(L, kHttpContentLength);
  lua_setfield(L, -2, "CONTENT_LENGTH");
  lua_pushinteger(L, kHttpConnection);
  lua_setfield(L, -2, "CONNECTION");
  lua_pushinteger(L, kHttpAccept);
  lua_setfield(L, -2, "ACCEPT");
  lua_pushinteger(L, kHttpUserAgent);
  lua_setfield(L, -2, "USER_AGENT");

  return 1;
}
