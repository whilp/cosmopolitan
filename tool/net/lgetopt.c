/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2024 Justine Alexandra Roberts Tunney                              │
│                                                                              │
│ Permission to use, copy, modify, and/or distribute this software for         │
│ any purpose with or without fee is hereby granted, provided that the         │
│ above copyright notice and this permission notice appear in all copies.      │
│                                                                              │
│ THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL                │
│ WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED                │
│ WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE             │
│ AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL         │
│ DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR        │
│ PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER               │
│ TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR             │
│ PERFORMANCE OF THIS SOFTWARE.                                                │
╚─────────────────────────────────────────────────────────────────────────────*/
#include "tool/net/lgetopt.h"
#include "libc/mem/mem.h"
#include "libc/str/str.h"
#include "third_party/getopt/long1.h"
#include "third_party/getopt/long2.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lua.h"

static int ParseHasArg(lua_State *L, const char *s) {
  if (!strcmp(s, "none"))
    return no_argument;
  if (!strcmp(s, "required"))
    return required_argument;
  if (!strcmp(s, "optional"))
    return optional_argument;
  return luaL_error(L, "has_arg must be 'none', 'required', or 'optional'");
}

// getopt.parse(args, optstring, longopts) -> opts, remaining
static int LuaGetoptParse(lua_State *L) {
  int argc, nlong, opt, longidx;
  const char *optstring;
  char **argv;
  struct option *longopts;
  const char *longname;
  char shortopt[2];

  luaL_checktype(L, 1, LUA_TTABLE);
  optstring = luaL_checkstring(L, 2);
  if (!lua_isnoneornil(L, 3))
    luaL_checktype(L, 3, LUA_TTABLE);

  // Count and allocate argv
  argc = luaL_len(L, 1);
  argv = calloc(argc + 2, sizeof(char *));
  if (!argv)
    return luaL_error(L, "out of memory");
  argv[0] = "lua";
  for (int i = 1; i <= argc; i++) {
    lua_rawgeti(L, 1, i);
    argv[i] = (char *)luaL_checkstring(L, -1);
    lua_pop(L, 1);
  }
  argv[argc + 1] = NULL;
  argc++;

  // Count and allocate longopts
  nlong = lua_isnoneornil(L, 3) ? 0 : luaL_len(L, 3);
  longopts = calloc(nlong + 1, sizeof(struct option));
  if (!longopts) {
    free(argv);
    return luaL_error(L, "out of memory");
  }
  for (int i = 0; i < nlong; i++) {
    lua_rawgeti(L, 3, i + 1);
    if (!lua_istable(L, -1)) {
      free(argv);
      free(longopts);
      return luaL_error(L, "longopt[%d] must be a table", i + 1);
    }
    lua_rawgeti(L, -1, 1);
    longopts[i].name = luaL_checkstring(L, -1);
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 2);
    longopts[i].has_arg = ParseHasArg(L, luaL_checkstring(L, -1));
    lua_pop(L, 1);
    lua_rawgeti(L, -1, 3);
    if (lua_isstring(L, -1)) {
      const char *s = lua_tostring(L, -1);
      longopts[i].val = s[0];
    } else {
      longopts[i].val = 0;
    }
    lua_pop(L, 1);
    longopts[i].flag = NULL;
    lua_pop(L, 1);
  }

  // Reset getopt state
  optind = 1;
  opterr = 0;

  // Create result tables
  lua_newtable(L);  // opts
  int opts_idx = lua_gettop(L);

  // Parse options
  shortopt[1] = '\0';
  while ((opt = getopt_long(argc, argv, optstring, longopts, &longidx)) != -1) {
    if (opt == '?') {
      continue;  // Unknown option, skip
    }
    if (opt == 0) {
      // Long option with flag set
      longname = longopts[longidx].name;
      if (optarg) {
        lua_pushstring(L, optarg);
      } else {
        lua_pushboolean(L, 1);
      }
      lua_setfield(L, opts_idx, longname);
    } else {
      // Short option (or long option returning val)
      shortopt[0] = opt;
      if (optarg) {
        lua_pushstring(L, optarg);
      } else {
        lua_pushboolean(L, 1);
      }
      lua_setfield(L, opts_idx, shortopt);

      // Also set long name if this came from a long option
      for (int i = 0; i < nlong; i++) {
        if (longopts[i].val == opt) {
          if (optarg) {
            lua_pushstring(L, optarg);
          } else {
            lua_pushboolean(L, 1);
          }
          lua_setfield(L, opts_idx, longopts[i].name);
          break;
        }
      }
    }
  }

  // Create remaining args table
  lua_newtable(L);
  int remaining_idx = lua_gettop(L);
  int j = 1;
  for (int i = optind; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, remaining_idx, j++);
  }

  free(argv);
  free(longopts);

  return 2;  // opts, remaining
}

static const luaL_Reg kLuaGetopt[] = {
    {"parse", LuaGetoptParse},
    {0},
};

int LuaGetopt(lua_State *L) {
  luaL_newlib(L, kLuaGetopt);
  return 1;
}
