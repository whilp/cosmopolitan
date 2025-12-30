/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
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
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "tool/net/lhttp.h"
#include "libc/serialize.h"
#include "net/http/http.h"
#include "third_party/lua/cosmo.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"

// http.parse(raw_request_string)
//     ├─→ {method, uri, version, headers, body, header_size}
//     └─→ nil, error_message
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

  lua_newtable(L);

  // method
  char method[9] = {0};
  WRITE64LE(method, msg.method);
  lua_pushstring(L, method);
  lua_setfield(L, -2, "method");

  // uri
  lua_pushlstring(L, buf + msg.uri.a, msg.uri.b - msg.uri.a);
  lua_setfield(L, -2, "uri");

  // version
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

  // header_size
  lua_pushinteger(L, rc);
  lua_setfield(L, -2, "header_size");

  DestroyHttpMessage(&msg);
  return 1;
}

// http.parse_response(raw_response_string)
//     ├─→ {status, message, version, headers, body, header_size}
//     └─→ nil, error_message
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

  // status
  lua_pushinteger(L, msg.status);
  lua_setfield(L, -2, "status");

  // message
  lua_pushlstring(L, buf + msg.message.a, msg.message.b - msg.message.a);
  lua_setfield(L, -2, "message");

  // version
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

  // header_size
  lua_pushinteger(L, rc);
  lua_setfield(L, -2, "header_size");

  DestroyHttpMessage(&msg);
  return 1;
}

// http.format_response({status, headers, body}) -> string
static int LuaHttpFormatResponse(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);

  lua_getfield(L, 1, "status");
  int status = luaL_optinteger(L, -1, 200);
  lua_pop(L, 1);

  // Build status line
  char status_line[64];
  snprintf(status_line, sizeof(status_line), "HTTP/1.1 %d %s\r\n",
           status, GetHttpReason(status));
  lua_pushstring(L, status_line);
  int nparts = 1;

  // Headers - collect all header strings
  lua_getfield(L, 1, "headers");
  if (lua_istable(L, -1)) {
    int headers_idx = lua_gettop(L);
    lua_pushnil(L);
    while (lua_next(L, headers_idx)) {
      // Stack: ..., headers_table, key, value
      const char *key = lua_tostring(L, -2);
      const char *val = lua_tostring(L, -1);
      lua_pop(L, 1);  // pop value first, keep key for next iteration
      // Stack: ..., headers_table, key
      if (key && val) {
        // Insert formatted header before headers_table
        lua_pushfstring(L, "%s: %s\r\n", key, val);
        lua_insert(L, headers_idx);
        headers_idx++;  // table moved up
        nparts++;
      }
    }
    // Pop headers_table (now at headers_idx)
    lua_remove(L, headers_idx);
  } else {
    lua_pop(L, 1);  // pop non-table headers
  }

  // End of headers
  lua_pushstring(L, "\r\n");
  nparts++;

  // Body
  lua_getfield(L, 1, "body");
  if (lua_isstring(L, -1)) {
    nparts++;
  } else {
    lua_pop(L, 1);
  }

  lua_concat(L, nparts);
  return 1;
}

// http.format_request({method, uri, headers, body}) -> string
static int LuaHttpFormatRequest(lua_State *L) {
  luaL_checktype(L, 1, LUA_TTABLE);

  lua_getfield(L, 1, "method");
  const char *method = luaL_optstring(L, -1, "GET");
  lua_pop(L, 1);

  lua_getfield(L, 1, "uri");
  const char *uri = luaL_checkstring(L, -1);
  lua_pop(L, 1);

  // Build request line
  lua_pushfstring(L, "%s %s HTTP/1.1\r\n", method, uri);
  int nparts = 1;

  // Headers - collect all header strings
  lua_getfield(L, 1, "headers");
  if (lua_istable(L, -1)) {
    int headers_idx = lua_gettop(L);
    lua_pushnil(L);
    while (lua_next(L, headers_idx)) {
      // Stack: ..., headers_table, key, value
      const char *key = lua_tostring(L, -2);
      const char *val = lua_tostring(L, -1);
      lua_pop(L, 1);  // pop value first, keep key for next iteration
      // Stack: ..., headers_table, key
      if (key && val) {
        // Insert formatted header before headers_table
        lua_pushfstring(L, "%s: %s\r\n", key, val);
        lua_insert(L, headers_idx);
        headers_idx++;  // table moved up
        nparts++;
      }
    }
    // Pop headers_table (now at headers_idx)
    lua_remove(L, headers_idx);
  } else {
    lua_pop(L, 1);  // pop non-table headers
  }

  // End of headers
  lua_pushstring(L, "\r\n");
  nparts++;

  // Body
  lua_getfield(L, 1, "body");
  if (lua_isstring(L, -1)) {
    nparts++;
  } else {
    lua_pop(L, 1);
  }

  lua_concat(L, nparts);
  return 1;
}

// http.reason(status_code) -> string
static int LuaHttpReason(lua_State *L) {
  int status = luaL_checkinteger(L, 1);
  lua_pushstring(L, GetHttpReason(status));
  return 1;
}

// http.header_name(header_constant) -> string or nil
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

  // HTTP method constants
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

  // Common status codes
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

  // Header constants
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
