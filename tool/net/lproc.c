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
#include "tool/net/lproc.h"
#include "libc/calls/calls.h"
#include "libc/calls/struct/rusage.h"
#include "libc/calls/weirdtypes.h"
#include "libc/errno.h"
#include "libc/mem/mem.h"
#include "libc/proc/posix_spawn.h"
#include "libc/runtime/runtime.h"
#include "libc/str/str.h"
#include "libc/sysv/consts/prio.h"
#include "libc/sysv/consts/w.h"
#include "third_party/lua/lauxlib.h"
#include "third_party/lua/lualib.h"
#include "third_party/lua/lunix.h"

static void FreeStringList(char **p) {
  int i;
  if (p) {
    for (i = 0; p[i]; ++i) {
      free(p[i]);
    }
    free(p);
  }
}

static char **ConvertLuaArrayToStringList(lua_State *L, int i) {
  int j, n;
  char **p, *s;
  luaL_checktype(L, i, LUA_TTABLE);
  lua_len(L, i);
  n = lua_tointeger(L, -1);
  lua_pop(L, 1);
  if ((p = calloc(n + 1, sizeof(*p)))) {
    for (j = 1; j <= n; ++j) {
      lua_geti(L, i, j);
      s = strdup(lua_tostring(L, -1));
      lua_pop(L, 1);
      if (s) {
        p[j - 1] = s;
      } else {
        FreeStringList(p);
        p = 0;
        break;
      }
    }
    if (p)
      p[j - 1] = 0;
  }
  return p;
}

// proc.daemon([nochdir:bool[, noclose:bool]])
//     ├─→ true
//     └─→ nil, unix.Errno
static int LuaProcDaemon(lua_State *L) {
  int olderr = errno;
  int nochdir = lua_toboolean(L, 1);
  int noclose = lua_toboolean(L, 2);
  int rc = daemon(nochdir, noclose);
  if (rc != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "daemon", olderr);
  }
}

// proc.waitpid(pid:int[, options:int])
//     ├─→ pid:int, wstatus:int
//     └─→ nil, unix.Errno
static int LuaProcWaitpid(lua_State *L) {
  int olderr = errno;
  int pid = luaL_checkinteger(L, 1);
  int options = luaL_optinteger(L, 2, 0);
  int wstatus;
  int rc = waitpid(pid, &wstatus, options);
  if (rc != -1) {
    lua_pushinteger(L, rc);
    lua_pushinteger(L, wstatus);
    return 2;
  } else {
    return LuaUnixSysretErrno(L, "waitpid", olderr);
  }
}

// proc.nice(inc:int)
//     ├─→ priority:int
//     └─→ nil, unix.Errno
static int LuaProcNice(lua_State *L) {
  int olderr = errno;
  int inc = luaL_checkinteger(L, 1);
  int rc = nice(inc);
  if (rc != -1) {
    lua_pushinteger(L, rc);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "nice", olderr);
  }
}

// proc.getpriority(which:int, who:int)
//     ├─→ priority:int
//     └─→ nil, unix.Errno
//
// which can be:
//   - proc.PRIO_PROCESS (0) - who is process id (0 = calling process)
//   - proc.PRIO_PGRP (1) - who is process group id (0 = calling process group)
//   - proc.PRIO_USER (2) - who is user id (0 = calling user)
static int LuaProcGetpriority(lua_State *L) {
  int olderr = errno;
  int which = luaL_checkinteger(L, 1);
  int who = luaL_checkinteger(L, 2);
  errno = 0;
  int rc = getpriority(which, who);
  if (rc == -1 && errno != 0) {
    return LuaUnixSysretErrno(L, "getpriority", olderr);
  }
  errno = olderr;
  lua_pushinteger(L, rc);
  return 1;
}

// proc.setpriority(which:int, who:int, prio:int)
//     ├─→ true
//     └─→ nil, unix.Errno
//
// which can be:
//   - proc.PRIO_PROCESS (0) - who is process id (0 = calling process)
//   - proc.PRIO_PGRP (1) - who is process group id (0 = calling process group)
//   - proc.PRIO_USER (2) - who is user id (0 = calling user)
static int LuaProcSetpriority(lua_State *L) {
  int olderr = errno;
  int which = luaL_checkinteger(L, 1);
  int who = luaL_checkinteger(L, 2);
  int prio = luaL_checkinteger(L, 3);
  int rc = setpriority(which, who, prio);
  if (rc != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "setpriority", olderr);
  }
}

// proc.killpg(pgrp:int, sig:int)
//     ├─→ true
//     └─→ nil, unix.Errno
static int LuaProcKillpg(lua_State *L) {
  int olderr = errno;
  int pgrp = luaL_checkinteger(L, 1);
  int sig = luaL_checkinteger(L, 2);
  int rc = killpg(pgrp, sig);
  if (rc != -1) {
    lua_pushboolean(L, 1);
    return 1;
  } else {
    return LuaUnixSysretErrno(L, "killpg", olderr);
  }
}

// proc.execvp(prog:str[, argv:table])
//     ├─→ ⊥
//     └─→ nil, unix.Errno
static int LuaProcExecvp(lua_State *L) {
  int olderr;
  const char *prog;
  char **argv, **freeme, *ezargs[2];
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if (!lua_isnoneornil(L, 2)) {
    if ((argv = ConvertLuaArrayToStringList(L, 2))) {
      freeme = argv;
    } else {
      return LuaUnixSysretErrno(L, "execvp", olderr);
    }
  } else {
    ezargs[0] = (char *)prog;
    ezargs[1] = 0;
    argv = ezargs;
    freeme = 0;
  }
  execvp(prog, argv);
  FreeStringList(freeme);
  return LuaUnixSysretErrno(L, "execvp", olderr);
}

// proc.fexecve(fd:int, argv:table[, envp:table])
//     ├─→ ⊥
//     └─→ nil, unix.Errno
static int LuaProcFexecve(lua_State *L) {
  int olderr, fd;
  char **argv, **envp, **freeme1, **freeme2;
  olderr = errno;
  fd = luaL_checkinteger(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "fexecve", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "fexecve", olderr);
  }
  fexecve(fd, argv, envp);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  return LuaUnixSysretErrno(L, "fexecve", olderr);
}

// proc.spawnp(prog:str, argv:table[, envp:table])
//     ├─→ pid:int
//     └─→ nil, unix.Errno
static int LuaProcSpawnp(lua_State *L) {
  int olderr, rc;
  pid_t pid;
  const char *prog;
  char **argv, **envp, **freeme1, **freeme2;
  olderr = errno;
  prog = luaL_checkstring(L, 1);
  if ((argv = ConvertLuaArrayToStringList(L, 2))) {
    freeme1 = argv;
    if (!lua_isnoneornil(L, 3)) {
      if ((envp = ConvertLuaArrayToStringList(L, 3))) {
        freeme2 = envp;
      } else {
        FreeStringList(argv);
        return LuaUnixSysretErrno(L, "spawnp", olderr);
      }
    } else {
      envp = environ;
      freeme2 = 0;
    }
  } else {
    return LuaUnixSysretErrno(L, "spawnp", olderr);
  }
  rc = posix_spawnp(&pid, prog, NULL, NULL, argv, envp);
  FreeStringList(freeme1);
  FreeStringList(freeme2);
  if (rc == 0) {
    lua_pushinteger(L, pid);
    return 1;
  } else {
    errno = rc;
    return LuaUnixSysretErrno(L, "spawnp", olderr);
  }
}

static void LuaProcAddConstants(lua_State *L) {
  // Priority constants (for getpriority/setpriority)
  lua_pushinteger(L, PRIO_PROCESS);
  lua_setfield(L, -2, "PRIO_PROCESS");
  lua_pushinteger(L, PRIO_PGRP);
  lua_setfield(L, -2, "PRIO_PGRP");
  lua_pushinteger(L, PRIO_USER);
  lua_setfield(L, -2, "PRIO_USER");

  // Wait options (for waitpid)
  lua_pushinteger(L, WNOHANG);
  lua_setfield(L, -2, "WNOHANG");
  lua_pushinteger(L, WUNTRACED);
  lua_setfield(L, -2, "WUNTRACED");
#ifdef WCONTINUED
  lua_pushinteger(L, WCONTINUED);
  lua_setfield(L, -2, "WCONTINUED");
#endif
}

// clang-format off
static const luaL_Reg kLuaProcFuncs[] = {
    {"daemon",       LuaProcDaemon},
    {"waitpid",      LuaProcWaitpid},
    {"nice",         LuaProcNice},
    {"getpriority",  LuaProcGetpriority},
    {"setpriority",  LuaProcSetpriority},
    {"killpg",       LuaProcKillpg},
    {"execvp",       LuaProcExecvp},
    {"fexecve",      LuaProcFexecve},
    {"spawnp",       LuaProcSpawnp},
    {NULL,           NULL},
};
// clang-format on

int LuaProc(lua_State *L) {
  luaL_newlib(L, kLuaProcFuncs);
  LuaProcAddConstants(L);
  return 1;
}
