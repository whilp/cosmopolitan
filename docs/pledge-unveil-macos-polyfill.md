# macOS Polyfill for pledge() and unveil()

**Design Document**
**Version:** 1.0
**Date:** 2026-01-01
**Author:** Claude (AI Assistant)
**Status:** DRAFT

---

## Executive Summary

This document proposes a macOS polyfill implementation for OpenBSD's `pledge()` and `unveil()` system calls within Cosmopolitan libc. The polyfill will translate pledge promises and unveil paths into macOS Sandbox Profile Language (SBPL) and apply them via `sandbox_init_with_parameters()`.

**Key Points:**
- **Estimated LOC:** ~1,150 lines (vs 2,400 for Linux)
- **Coverage:** 60-80% functional compatibility with OpenBSD/Linux
- **Dependencies:** Deprecated but stable `sandbox_init_with_parameters()` API
- **Testing:** Reuse existing 58-test conformance suite
- **Timeline:** 2-3 week implementation + 1 week testing

---

## Table of Contents

1. [Background](#background)
2. [Goals and Non-Goals](#goals-and-non-goals)
3. [Technical Approach](#technical-approach)
4. [Architecture](#architecture)
5. [Implementation Details](#implementation-details)
6. [API Compatibility](#api-compatibility)
7. [Security Analysis](#security-analysis)
8. [Testing Strategy](#testing-strategy)
9. [Performance Considerations](#performance-considerations)
10. [Limitations and Tradeoffs](#limitations-and-tradeoffs)
11. [Implementation Roadmap](#implementation-roadmap)
12. [Risk Assessment](#risk-assessment)
13. [References](#references)

---

## Background

### Current State

**Cosmopolitan libc** currently implements pledge/unveil for:
- ✅ **OpenBSD:** Native syscalls
- ✅ **Linux:** Polyfill via seccomp-bpf (pledge) and landlock (unveil)
- ❌ **macOS:** Silent no-op (returns 0, does nothing)

**Problem:** macOS applications using Cosmopolitan libc have no sandboxing despite calling pledge/unveil.

### Related Work

**Linux Polyfill Implementation:**
- File: `libc/calls/pledge-linux.c` (2,400 lines)
- Approach: Generate seccomp-bpf filter from promise bitmask
- Coverage: ~591 BPF instructions for all promises
- Mechanism: SIGSYS handler for violations

**macOS Sandbox:**
- Native API: `sandbox_init_with_parameters()` (deprecated but stable)
- Profile Language: Scheme-based SBPL
- Mechanism: MACF (Mandatory Access Control Framework) with ~300 hooks
- Used by: Chrome, Firefox, Nix, Apple's own tools

---

## Goals and Non-Goals

### Goals

1. **Functional Security:** Provide meaningful sandboxing on macOS
2. **Source Compatibility:** No code changes required for applications
3. **Test Coverage:** Pass ≥60% of existing test suite
4. **Performance:** <5% overhead vs native pledge/unveil
5. **Maintainability:** Clean integration with existing codebase

### Non-Goals

1. **100% Compatibility:** Accept differences in edge cases
2. **App Sandbox Support:** Only CLI tool sandboxing (not .app bundles)
3. **M1/ARM64 Optimization:** Focus on x86_64 first
4. **Hardened Runtime:** Avoid entitlement-based sandboxing

---

## Technical Approach

### Core Strategy

**Map pledge/unveil semantics to SBPL:**

```
pledge("stdio rpath inet", NULL)
    ↓
Parse promises → bitmask
    ↓
Generate SBPL profile
    ↓
sandbox_init_with_parameters()
    ↓
Kernel-enforced via MACF hooks
```

### Key Insight: Deferred Application

Since `sandbox_init()` can only be called **once**, we must:

1. **Track state** in thread-local storage
2. **Defer application** until lock point
3. **Generate combined profile** from pledge + unveil state
4. **Apply atomically** on `unveil(NULL, NULL)` or `pledge()` after unveil lock

---

## Architecture

### File Structure

```
libc/calls/
├── pledge-xnu.c          # macOS pledge implementation (~600 LOC)
├── unveil-xnu.c          # macOS unveil implementation (~200 LOC)
├── pledge.c              # Add IsXnu() branch
├── unveil.c              # Add IsXnu() branch
├── sbpl-generator.c      # SBPL profile generation (~250 LOC)
└── sandbox-xnu.h         # External declarations

test/libc/calls/
├── pledge_test.c         # Add IsXnu() conditionals
├── unveil_test.c         # Add IsXnu() conditionals
└── sbpl_test.c           # New: SBPL generation tests (~300 LOC)
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Application Code                                             │
│ pledge("stdio rpath inet", NULL);                            │
│ unveil("/etc", "r");                                         │
│ unveil("/tmp", "rwc");                                       │
│ unveil(NULL, NULL);  // Lock                                 │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ pledge.c / unveil.c                                          │
│ if (IsXnu()) sys_pledge_xnu() / sys_unveil_xnu()             │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ Thread-Local State (XnuSandboxState)                         │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ unsigned long promises;        // Pledge bitmask        │ │
│ │ struct unveil_path paths[256]; // Unveil rules          │ │
│ │ int npaths;                                             │ │
│ │ bool sandbox_active;           // Already locked?       │ │
│ └─────────────────────────────────────────────────────────┘ │
└────────────────┬────────────────────────────────────────────┘
                 │
                 │ On unveil(NULL, NULL)
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ apply_sandbox_xnu()                                          │
│ 1. Generate SBPL from promises + paths                       │
│ 2. Call sandbox_init_with_parameters()                       │
│ 3. Set sandbox_active = true                                 │
└────────────────┬────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────┐
│ macOS Kernel (MACF)                                          │
│ Enforces sandbox via ~300 policy hooks                       │
└─────────────────────────────────────────────────────────────┘
```

---

## Implementation Details

### 1. Thread-Local State

```c
// libc/calls/pledge-xnu.c

_Thread_local static struct {
  // Pledge state
  unsigned long promises;       // Inverted bitmask of allowed promises
  bool pledge_called;           // Has pledge() been invoked?

  // Unveil state
  struct unveil_path {
    char path[PATH_MAX];
    char perms[5];              // "rwxc\0"
  } paths[256];
  int npaths;
  bool unveil_locked;           // Has unveil(NULL,NULL) been called?

  // Sandbox state
  bool sandbox_active;          // Has sandbox_init() been called?
  char *error_msg;              // Last error from sandbox_init()
} XnuSandboxState = {
  .promises = -1UL,             // Start with all denied
  .npaths = 0,
  .pledge_called = false,
  .unveil_locked = false,
  .sandbox_active = false,
  .error_msg = NULL
};
```

### 2. Promise → SBPL Mapping Table

```c
// libc/calls/sbpl-generator.c

static const char *kPledgeToSBPL[PROMISE_LEN_] = {

  [PROMISE_STDIO] =
    // Basic I/O operations
    "(allow file-read* file-write*\n"
    "  (literal \"/dev/stdin\" \"/dev/stdout\" \"/dev/stderr\"\n"
    "           \"/dev/null\" \"/dev/zero\" \"/dev/urandom\"))\n"
    "(allow sysctl-read)\n"
    "(allow process-fork)\n"
    "(allow mach-lookup (global-name \"com.apple.system.logger\"))\n",

  [PROMISE_RPATH] =
    // Read-only filesystem operations
    "(allow file-read*)\n"
    "(allow file-read-metadata)\n",

  [PROMISE_WPATH] =
    // Write operations (excluding create/delete)
    "(allow file-write*)\n"
    "(allow file-write-data)\n"
    "(allow file-write-flags)\n"
    "(allow file-write-mode)\n"
    "(allow file-write-owner)\n",

  [PROMISE_CPATH] =
    // Create/delete operations
    "(allow file-write-create)\n"
    "(allow file-write-unlink)\n"
    "(allow file-link)\n"
    "(allow file-rename)\n",

  [PROMISE_DPATH] =
    // Device node creation
    "(allow file-write-create\n"
    "  (vnode-type BLOCK-DEVICE CHARACTER-DEVICE))\n",

  [PROMISE_FLOCK] =
    // File locking
    "(allow file-lock)\n",

  [PROMISE_FATTR] =
    // File attribute modification
    "(allow file-write-mode)\n"
    "(allow file-write-owner)\n"
    "(allow file-write-times)\n"
    "(allow file-write-flags)\n",

  [PROMISE_INET] =
    // IPv4/IPv6 networking
    "(allow network-outbound)\n"
    "(allow network-inbound)\n"
    "(allow network-bind)\n"
    "(allow system-socket)\n",

  [PROMISE_ANET] =
    // Accept-only networking (no connect/UDP)
    "(allow network-inbound)\n"
    "(allow network-bind)\n",

  [PROMISE_UNIX] =
    // Unix domain sockets
    "(allow network* (local ip))\n"
    "(allow ipc-posix-shm)\n"
    "(allow ipc-posix-sem)\n"
    "(allow ipc-sysv-shm)\n",

  [PROMISE_DNS] =
    // DNS resolution
    "(allow network-outbound\n"
    "  (remote udp \"*:53\"))\n"
    "(allow file-read*\n"
    "  (literal \"/etc/resolv.conf\" \"/etc/hosts\"\n"
    "           \"/private/var/run/resolv.conf\"))\n"
    "(allow mach-lookup\n"
    "  (global-name \"com.apple.system.DirectoryService.libinfo_v1\"\n"
    "               \"com.apple.system.notification_center\"))\n",

  [PROMISE_TTY] =
    // Terminal I/O
    "(allow ioctl-set-attributes)\n"
    "(allow file-ioctl\n"
    "  (literal \"/dev/tty\" \"/dev/console\"))\n",

  [PROMISE_RECVFD] =
    // Receive file descriptors
    "(allow ipc-posix-shm-read-data)\n",

  [PROMISE_SENDFD] =
    // Send file descriptors
    "(allow ipc-posix-shm-write-data)\n",

  [PROMISE_PROC] =
    // Process management
    "(allow process-fork)\n"
    "(allow process-exec)\n"
    "(allow signal)\n"
    "(allow sysctl-write\n"
    "  (sysctl-name \"kern.proc.*\"))\n",

  [PROMISE_EXEC] =
    // Execute binaries
    "(allow process-exec)\n"
    "(allow file-map-executable)\n",

  [PROMISE_ID] =
    // Identity management
    "(allow process-setid)\n"
    "(allow system-audit)\n",

  [PROMISE_UNVEIL] =
    // Allow unveil operations (always needed for our impl)
    "",

  [PROMISE_SETTIME] =
    // Set system time
    "(allow system-set-time)\n",

  [PROMISE_PROT_EXEC] =
    // Executable memory
    "(allow file-map-executable)\n"
    "(allow mach-per-user-lookup)\n"  // dyld needs this
    "(allow process-codesigning-status*)\n",

  [PROMISE_VMINFO] =
    // Virtual memory info
    "(allow sysctl-read\n"
    "  (sysctl-name \"vm.*\" \"kern.boottime\" \"kern.osversion\"))\n"
    "(allow file-read*\n"
    "  (subpath \"/System/Library\"))\n",  // top(1) needs this

  [PROMISE_TMPPATH] =
    // Temporary path access
    "(allow file-read* file-write*\n"
    "  (subpath \"/tmp\" \"/var/tmp\"\n"
    "           (param \"TMPDIR\")))\n",

  [PROMISE_CHOWN] =
    // Change ownership
    "(allow file-write-owner)\n",
};
```

### 3. SBPL Profile Generation

```c
// libc/calls/sbpl-generator.c

#define SBPL_MAX_SIZE 16384

static int generate_sbpl_profile(char *out, size_t outsize) {
  int pos = 0;

  // Header
  pos += snprintf(out + pos, outsize - pos,
    ";; Auto-generated by pledge/unveil polyfill\n"
    "(version 1)\n"
    "(deny default)\n"
    "\n"
    ";; Allow self-execution\n"
    "(allow process-exec (literal (param \"PROCESS_PATH\")))\n"
    "\n");

  if (pos >= outsize) return -1;

  // Add pledge promises
  if (XnuSandboxState.pledge_called) {
    pos += snprintf(out + pos, outsize - pos,
      ";; Pledge promises\n");

    for (int i = 0; i < PROMISE_LEN_; i++) {
      // Check if this promise is allowed (bit cleared in inverted mask)
      if (~XnuSandboxState.promises & (1UL << i)) {
        if (kPledgeToSBPL[i] && *kPledgeToSBPL[i]) {
          pos += snprintf(out + pos, outsize - pos,
            "%s", kPledgeToSBPL[i]);
          if (pos >= outsize) return -1;
        }
      }
    }
    pos += snprintf(out + pos, outsize - pos, "\n");
  } else {
    // No pledge called - allow everything by default
    pos += snprintf(out + pos, outsize - pos,
      "(allow default)\n\n");
  }

  // Add unveil paths
  if (XnuSandboxState.npaths > 0) {
    pos += snprintf(out + pos, outsize - pos,
      ";; Unveil filesystem restrictions\n");

    for (int i = 0; i < XnuSandboxState.npaths; i++) {
      const char *path = XnuSandboxState.paths[i].path;
      const char *perms = XnuSandboxState.paths[i].perms;

      // Read permission
      if (strchr(perms, 'r')) {
        pos += snprintf(out + pos, outsize - pos,
          "(allow file-read* (subpath \"%s\"))\n", path);
        if (pos >= outsize) return -1;
      }

      // Write permission
      if (strchr(perms, 'w')) {
        pos += snprintf(out + pos, outsize - pos,
          "(allow file-write* (subpath \"%s\"))\n", path);
        if (pos >= outsize) return -1;
      }

      // Execute permission
      if (strchr(perms, 'x')) {
        pos += snprintf(out + pos, outsize - pos,
          "(allow file-map-executable (subpath \"%s\"))\n"
          "(allow process-exec* (subpath \"%s\"))\n",
          path, path);
        if (pos >= outsize) return -1;
      }

      // Create permission
      if (strchr(perms, 'c')) {
        pos += snprintf(out + pos, outsize - pos,
          "(allow file-write-create (subpath \"%s\"))\n"
          "(allow file-write-unlink (subpath \"%s\"))\n"
          "(allow file-link (subpath \"%s\"))\n"
          "(allow file-rename (subpath \"%s\"))\n",
          path, path, path, path);
        if (pos >= outsize) return -1;
      }
    }
  } else if (XnuSandboxState.unveil_locked) {
    // Locked with no paths = deny all filesystem access
    pos += snprintf(out + pos, outsize - pos,
      ";; No filesystem access (unveil locked with no paths)\n"
      "(deny file-read* file-write*)\n");
  }

  return pos;
}
```

### 4. Core Implementation: pledge()

```c
// libc/calls/pledge-xnu.c

/**
 * Stores pledge promises for later application.
 * @return 0 on success, -1 w/ errno on error
 */
int sys_pledge_xnu(unsigned long ipromises, int mode) {
  // Check if sandbox already active
  if (XnuSandboxState.sandbox_active) {
    // Can we tighten further?
    unsigned long new_denied = ipromises;
    unsigned long old_denied = XnuSandboxState.promises;

    // On macOS, once locked we cannot change the policy
    // Linux allows tightening, OpenBSD allows tightening
    // For macOS, we must return EPERM
    return eperm();
  }

  // Store the promise mask
  XnuSandboxState.promises = ipromises;
  XnuSandboxState.pledge_called = true;

  // If unveil has been locked, apply now
  if (XnuSandboxState.unveil_locked) {
    return apply_sandbox_xnu();
  }

  // Otherwise defer until unveil lock or next pledge
  return 0;
}

/**
 * Applies the sandbox by generating SBPL and calling sandbox_init.
 */
static int apply_sandbox_xnu(void) {
  char profile[SBPL_MAX_SIZE];
  char *error = NULL;
  int rc;

  // Already active?
  if (XnuSandboxState.sandbox_active) {
    return 0;
  }

  // Generate SBPL profile
  rc = generate_sbpl_profile(profile, sizeof(profile));
  if (rc < 0) {
    kprintf("pledge/unveil: SBPL profile too large\n");
    return enomem();
  }

  // Debug logging (if enabled)
  if (__strace > 0) {
    kprintf("pledge/unveil: Applying sandbox profile:\n%s\n", profile);
  }

  // Prepare parameters
  const char *params[] = {
    "PROCESS_PATH", __progname,
    "TMPDIR", getenv("TMPDIR") ?: "/tmp",
    NULL
  };

  // Apply sandbox
  rc = sandbox_init_with_parameters(profile, 0, params, &error);

  if (rc != 0) {
    if (error) {
      kprintf("pledge/unveil: sandbox_init failed: %s\n", error);
      XnuSandboxState.error_msg = error;
      // Note: Don't call sandbox_free_error() yet - keep for debugging
    }
    return -1;
  }

  // Mark as active
  XnuSandboxState.sandbox_active = true;

  return 0;
}
```

### 5. Core Implementation: unveil()

```c
// libc/calls/unveil-xnu.c

/**
 * Stores unveil paths or locks and applies sandbox.
 * @return 0 on success, -1 w/ errno on error
 */
int sys_unveil_xnu(const char *path, const char *permissions) {
  // Lock and apply?
  if (!path && !permissions) {
    XnuSandboxState.unveil_locked = true;
    return apply_sandbox_xnu();
  }

  // Check for invalid combinations
  if ((path && !permissions) || (!path && permissions)) {
    return einval();
  }

  // Check if already locked
  if (XnuSandboxState.unveil_locked) {
    return eperm();
  }

  // Check capacity
  if (XnuSandboxState.npaths >= 256) {
    return enomem();
  }

  // Validate permissions
  for (const char *p = permissions; *p; p++) {
    if (*p != 'r' && *p != 'w' && *p != 'x' && *p != 'c') {
      return einval();
    }
  }

  // Store the path and permissions
  struct unveil_path *u = &XnuSandboxState.paths[XnuSandboxState.npaths++];

  // Resolve to absolute path if needed
  if (path[0] != '/') {
    char cwd[PATH_MAX];
    if (!getcwd(cwd, sizeof(cwd))) {
      return -1;
    }
    snprintf(u->path, PATH_MAX, "%s/%s", cwd, path);
  } else {
    strlcpy(u->path, path, PATH_MAX);
  }

  strlcpy(u->perms, permissions, sizeof(u->perms));

  return 0;
}
```

### 6. Integration Points

```c
// libc/calls/pledge.c

int pledge(const char *promises, const char *execpromises) {
  // ... existing code ...

  } else if (!ParsePromises(promises, &ipromises, __promises) &&
             !ParsePromises(execpromises, &iexecpromises, __execpromises)) {
    if (IsLinux()) {
      // ... Linux implementation ...
    } else if (IsXnu()) {
      // macOS implementation
      rc = sys_pledge_xnu(ipromises, __pledge_mode);
      if (rc > -4096u) {
        errno = -rc;
        rc = -1;
      }
    } else {
      // OpenBSD, FreeBSD, etc.
      e = errno;
      rc = sys_pledge(promises, execpromises);
      // ... existing code ...
    }
  }

  // ... rest of function ...
}
```

```c
// libc/calls/unveil.c

int unveil(const char *path, const char *permissions) {
  // ... existing validation ...

  } else if (!IsTiny() && IsGenuineBlink()) {
    rc = 0;  // blink doesn't support
  } else if (IsLinux()) {
    rc = sys_unveil_linux(path, permissions);
  } else if (IsXnu()) {
    // macOS implementation
    rc = sys_unveil_xnu(path, permissions);
  } else {
    rc = sys_unveil(path, permissions);
  }

  // ... rest of function ...
}
```

### 7. External Declarations

```c
// libc/calls/sandbox-xnu.h

#ifndef COSMOPOLITAN_LIBC_CALLS_SANDBOX_XNU_H_
#define COSMOPOLITAN_LIBC_CALLS_SANDBOX_XNU_H_

COSMOPOLITAN_C_START_

// macOS Sandbox API declarations
// These are not in public headers but are stable ABI

extern int sandbox_init_with_parameters(
    const char *profile,
    uint64_t flags,
    const char *const parameters[],
    char **errorbuf
) __attribute__((weak_import));

extern void sandbox_free_error(char *errorbuf)
    __attribute__((weak_import));

// Our polyfill implementations
int sys_pledge_xnu(unsigned long ipromises, int mode);
int sys_unveil_xnu(const char *path, const char *permissions);

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_LIBC_CALLS_SANDBOX_XNU_H_ */
```

---

## API Compatibility

### Behavioral Differences

| Aspect | OpenBSD | Linux | macOS (Proposed) |
|--------|---------|-------|------------------|
| **Incremental pledge()** | ✅ Can tighten | ✅ Can tighten | ❌ First call only* |
| **Incremental unveil()** | ✅ Immediate effect | ⚠️ Deferred to lock | ⚠️ Deferred to lock |
| **Multiple unveil locks** | ❌ Not allowed | ✅ Allowed | ⚠️ Allowed (no-op)** |
| **Error on violation** | SIGABRT (kill) | EPERM or SIGSYS | SIGKILL (macOS default) |
| **Thread scope** | Process-wide | Thread-local | Thread-local*** |
| **exec inheritance** | ✅ execpromises | ✅ Via libc wrapper | ⚠️ Inherit fully**** |

**Notes:**
- \* Could be improved in future by regenerating profile
- \*\* Linux landlock allows multiple locks; macOS we'd make it a no-op
- \*\*\* Unless we explicitly make process-wide (TBD)
- \*\*\*\* execpromises hard to implement without libc interception

### Compatibility Matrix

| Test Case | OpenBSD | Linux | macOS | Notes |
|-----------|---------|-------|-------|-------|
| `pledge, default_allowsExit` | ✅ | ✅ | ✅ | Should work |
| `pledge, stdio_forbidsOpeningPasswd` | ✅ | ✅ | ✅ | Should work |
| `pledge, multipleCalls_canOnlyBecomeMoreRestrictive` | ✅ | ✅ | ⚠️ | First call only |
| `pledge, inet_forbidsOtherSockets` | ✅ | ✅ | ✅ | Should work |
| `pledge, execpromises_ok` | ✅ | ✅ | ⚠️ | Exec issues |
| `unveil, rx_readOnlyPreexistingExecutable` | ✅ | ✅ | ✅ | Should work |
| `unveil, dirfdHacking_doesntWork` | ✅ | ✅ | ❌ | macOS allows O_PATH stat |
| `unveil, overlappingDirectories` | ⚠️ Most restrictive | ⚠️ Union | ⚠️ Union | SBPL limitation |
| `unveil, usedTwice_forbidden` | ❌ | ✅ | ⚠️ | macOS allows |

**Expected test pass rate:** 60-70% without modifications, 80-85% with macOS-specific adjustments.

---

## Security Analysis

### Threat Model

**Assumptions:**
1. Attacker has achieved code execution within the process
2. Goal: Prevent privilege escalation and data exfiltration
3. Trust boundary: macOS kernel sandbox enforcement

**Protections Provided:**

| Attack Vector | OpenBSD | Linux | macOS |
|---------------|---------|-------|-------|
| Read /etc/shadow | ✅ Blocked | ✅ Blocked | ✅ Blocked |
| Write arbitrary files | ✅ Blocked | ✅ Blocked | ✅ Blocked |
| Open network sockets | ✅ Blocked | ✅ Blocked | ✅ Blocked |
| Execute binaries | ✅ Blocked | ✅ Blocked | ✅ Blocked |
| mmap(PROT_EXEC) | ✅ Blocked | ✅ Blocked | ✅ Blocked |
| Capability dropping | ✅ Yes | ✅ Yes | ⚠️ N/A (macOS has no caps) |

### Known Weaknesses

1. **Metadata Leakage:**
   - Linux landlock allows stat() on any path
   - macOS SBPL may have similar issues
   - **Mitigation:** Document as known limitation

2. **setuid/setgid:**
   - macOS sandbox_init() must be called before privilege drop
   - Timing issues possible
   - **Mitigation:** Clear documentation on call order

3. **Symbolic Links:**
   - SBPL uses path-based matching
   - Symlinks outside jail may bypass restrictions
   - **Mitigation:** Resolve symlinks before unveil()

4. **Deprecated API:**
   - `sandbox_init_with_parameters()` is deprecated
   - Apple could remove in future macOS
   - **Mitigation:** Feature detection, graceful fallback

### Comparison to Alternatives

| Approach | Pros | Cons |
|----------|------|------|
| **SBPL (Proposed)** | Kernel-enforced, granular, tested | Deprecated API |
| **App Sandbox** | Apple-blessed | Timing issues, requires entitlements |
| **No-op (Current)** | Simple, compatible | Zero security |
| **User-space interception** | No deprecated APIs | Bypassable, performance |

**Verdict:** SBPL provides the best balance of security and compatibility.

---

## Testing Strategy

### Phase 1: Unit Tests

**New tests in `test/libc/calls/sbpl_test.c`:**

```c
TEST(sbpl, generateBasicProfile)
TEST(sbpl, pledgeStdioOnly)
TEST(sbpl, pledgeRpathWpath)
TEST(sbpl, unveilSinglePath)
TEST(sbpl, unveilMultiplePaths)
TEST(sbpl, combinedPledgeUnveil)
TEST(sbpl, profileSizeLimit)
TEST(sbpl, invalidPermissions)
```

### Phase 2: Integration Tests

**Modify existing tests with `IsXnu()` guards:**

```c
TEST(pledge, stdio_forbidsOpeningPasswd) {
  if (!IsLinux() && !IsXnu())
    return;
  // ... test body ...
  if (IsXnu()) {
    // macOS-specific expectations
    EXPECT_EQ(SIGKILL, WTERMSIG(ws));  // macOS default
  }
}
```

**Expected modifications:**
- ~15 tests in `pledge_test.c`
- ~8 tests in `unveil_test.c`
- Add `xnu/` subdirectory for macOS-specific tests

### Phase 3: Conformance Testing

**Run full test suite on macOS:**

```bash
# Target metrics
make -j8 MODE=rel o/rel/test/libc/calls/pledge_test.runs
make -j8 MODE=rel o/rel/test/libc/calls/unveil_test.runs

# Expected results:
# pledge_test.c:  20/33 passing (60%)
# unveil_test.c:  12/18 passing (66%)
```

**Create test report:**
```
docs/macos-pledge-test-report.md
  - Passing tests
  - Failing tests with explanations
  - Platform-specific behavior notes
```

### Phase 4: Real-World Testing

**Test with actual programs:**

```bash
# Lua interpreter
lua --allow-read=/tmp --allow-write=/tmp script.lua

# curl
pledge -p 'stdio inet dns rpath' curl https://example.com

# Redbean web server
pledge -p 'stdio inet rpath' redbean.com
```

### Phase 5: Security Testing

**Negative tests (should fail):**

```c
// These should be BLOCKED by sandbox
TEST(pledge_security_xnu, cannotReadPasswdAfterStdio)
TEST(pledge_security_xnu, cannotOpenSocketAfterStdio)
TEST(unveil_security_xnu, cannotReadOutsideJail)
TEST(unveil_security_xnu, cannotSymlinkEscape)
```

**Fuzzing:**
- Fuzz SBPL generation with random promise combinations
- Fuzz unveil paths (long paths, special chars, symlinks)

---

## Performance Considerations

### Initialization Cost

**Estimated overhead:**

| Operation | Time | Notes |
|-----------|------|-------|
| `pledge()` first call | ~50μs | Parse + store |
| `unveil()` per path | ~10μs | Path resolution + store |
| `unveil(NULL, NULL)` | ~500μs | SBPL gen + sandbox_init() |
| **Total typical startup** | **~600μs** | 1 pledge + 5 unveils + lock |

**Comparison:**
- Linux pledge: ~200μs (seccomp filter install)
- OpenBSD pledge: ~20μs (native syscall)
- **macOS overhead: ~3x Linux, ~30x OpenBSD**

### Runtime Cost

**Per-operation overhead:**

| Operation | OpenBSD | Linux | macOS |
|-----------|---------|-------|-------|
| `open()` allowed | 0μs | ~1μs (BPF check) | ~0.5μs (MACF hook) |
| `open()` denied | 0μs | ~2μs (BPF + EPERM) | ~1μs (MACF + error) |
| Socket creation | 0μs | ~1.5μs | ~0.5μs |

**Verdict:** Runtime overhead negligible (<1%).

### Memory Usage

**State storage:**
- `XnuSandboxState`: ~64KB per thread (256 paths × 256 bytes)
- SBPL profile buffer: ~16KB per thread
- **Total: ~80KB per thread**

**Comparison:**
- Linux: ~8KB (seccomp filter)
- OpenBSD: 0 bytes (kernel-side)

**Mitigation:** Thread-local storage is acceptable for CLI tools.

---

## Limitations and Tradeoffs

### Known Limitations

#### 1. Single Application Point

**Issue:** `sandbox_init()` can only be called once per process.

**Impact:**
- Cannot tighten policy after initial lock
- Multiple `pledge()` calls only work if unveil not locked

**Workaround:**
- Document as limitation
- Application should call pledge/unveil early, all at once

**Alternative considered:**
- Generate new profile and re-exec self
- **Rejected:** Too complex, breaks semantics

#### 2. No execpromises Support

**Issue:** macOS sandbox doesn't inherit cleanly across exec().

**Impact:**
- `execpromises` parameter ignored
- Child processes inherit full sandbox (may be too restrictive or too loose)

**Workaround:**
- Document as limitation
- Applications using exec() should use wrapper scripts

**Alternative considered:**
- LD_PRELOAD trick to re-apply sandbox
- **Rejected:** Doesn't work with SIP, fragile

#### 3. Path Resolution Differences

**Issue:** SBPL uses prefix matching, landlock uses inode-based.

**Impact:**
- Symlinks may behave differently
- Overlapping paths use union (not most-restrictive)

**Workaround:**
- Resolve symlinks in `sys_unveil_xnu()`
- Document behavior difference

#### 4. Metadata Leakage

**Issue:** macOS sandbox allows stat() on hidden paths (like Linux).

**Impact:**
- Attacker can probe filesystem structure
- Know file sizes, existence

**Workaround:**
- Document as limitation
- Not worse than Linux

#### 5. Deprecated API

**Issue:** `sandbox_init_with_parameters()` is marked deprecated.

**Impact:**
- Apple may remove in future macOS version
- No public replacement announced

**Workaround:**
- Weak symbol import (graceful fallback)
- Feature detection with `pledge(0,0)` returning ENOSYS

**Monitoring:**
- Test on macOS beta releases
- Engage with Apple developer relations

### Tradeoff Summary

| Aspect | Gained | Lost |
|--------|--------|------|
| **Security** | ✅ Kernel-enforced sandboxing | ⚠️ Some edge cases weaker |
| **Compatibility** | ✅ Source-compatible | ❌ Behavior differences |
| **Performance** | ✅ <1% runtime overhead | ⚠️ 600μs startup cost |
| **Maintainability** | ✅ Clean integration | ⚠️ Depends on deprecated API |
| **Testing** | ✅ Reuse existing suite | ⚠️ Some tests need guards |

**Overall verdict:** Benefits outweigh costs for CLI tool sandboxing.

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)

**Days 1-2: Scaffolding**
- [ ] Create `libc/calls/pledge-xnu.c` stub
- [ ] Create `libc/calls/unveil-xnu.c` stub
- [ ] Create `libc/calls/sandbox-xnu.h` declarations
- [ ] Add `IsXnu()` branches to `pledge.c` and `unveil.c`
- [ ] Create `test/libc/calls/sbpl_test.c`

**Days 3-4: SBPL Generation**
- [ ] Implement `sbpl-generator.c`
- [ ] Complete promise → SBPL mapping table
- [ ] Add unit tests for SBPL generation
- [ ] Test on macOS with manual profiles

**Day 5: State Management**
- [ ] Implement `XnuSandboxState` structure
- [ ] Add state tracking in pledge/unveil
- [ ] Test state accumulation

### Phase 2: Core Implementation (Week 2)

**Days 6-8: pledge() Implementation**
- [ ] Implement `sys_pledge_xnu()`
- [ ] Implement `apply_sandbox_xnu()`
- [ ] Add error handling
- [ ] Test basic pledge scenarios

**Days 9-10: unveil() Implementation**
- [ ] Implement `sys_unveil_xnu()`
- [ ] Add path resolution logic
- [ ] Add permission validation
- [ ] Test basic unveil scenarios

### Phase 3: Integration & Testing (Week 3)

**Days 11-12: Integration**
- [ ] Wire up all components
- [ ] Add debug logging
- [ ] Fix compilation errors
- [ ] Run basic smoke tests

**Days 13-14: Conformance Testing**
- [ ] Modify existing tests for macOS
- [ ] Run full test suite
- [ ] Document failures
- [ ] Fix critical bugs

**Day 15: Security Testing**
- [ ] Run negative tests
- [ ] Test with real programs
- [ ] Security review

### Phase 4: Polish & Documentation (Week 4)

**Days 16-17: Bug Fixes**
- [ ] Fix test failures
- [ ] Improve error messages
- [ ] Performance profiling

**Days 18-19: Documentation**
- [ ] Update `pledge.c` documentation
- [ ] Create macOS-specific docs
- [ ] Write migration guide

**Day 20: Release Prep**
- [ ] Final testing on multiple macOS versions
- [ ] Code review
- [ ] Prepare PR

### Milestones

| Milestone | Date | Deliverable |
|-----------|------|-------------|
| **M1: Prototype** | Day 5 | SBPL generation working |
| **M2: Alpha** | Day 10 | pledge() + unveil() functional |
| **M3: Beta** | Day 15 | Passing 50% of tests |
| **M4: RC** | Day 19 | Passing 70% of tests |
| **M5: Release** | Day 20 | Ready for production |

---

## Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **API deprecation** | Medium | High | Weak import, feature detection |
| **SBPL incompleteness** | Medium | Medium | Thorough testing, conservative mapping |
| **Performance issues** | Low | Medium | Profiling, optimization |
| **Security gaps** | Low | High | Security review, fuzzing |
| **macOS version incompatibility** | Low | High | Test on 10.15+, beta testing |

### Process Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|------------|
| **Scope creep** | Medium | Medium | Strict phase gating |
| **Test coverage gaps** | Medium | High | Systematic test planning |
| **Documentation lag** | High | Low | Inline documentation |

### Contingency Plans

**If `sandbox_init()` is removed:**
- Fall back to no-op behavior (current state)
- Investigate App Sandbox entitlements
- Consider user-space interception

**If test pass rate <50%:**
- Re-evaluate promise mappings
- Adjust compatibility expectations
- Add more macOS-specific workarounds

**If performance unacceptable:**
- Lazy SBPL generation
- Cache generated profiles
- Reduce state storage

---

## References

### External Documentation

1. **OpenBSD Manual Pages**
   - pledge(2): https://man.openbsd.org/pledge.2
   - unveil(2): https://man.openbsd.org/unveil.2

2. **macOS Sandbox**
   - Apple Sandbox Guide: https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf
   - SBPL Language: https://www.romab.com/ironsuite/SBPL.html
   - Chromium Mac Sandbox: https://chromium.googlesource.com/chromium/src/+/HEAD/sandbox/mac/seatbelt_sandbox_design.md

3. **Linux Implementation**
   - seccomp-bpf: https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html
   - landlock: https://docs.kernel.org/userspace-api/landlock.html

### Code References

- `libc/calls/pledge-linux.c`: Linux polyfill implementation
- `libc/calls/unveil.c`: Linux unveil + landlock
- `libc/calls/pledge.c`: Main pledge() wrapper
- `test/libc/calls/pledge_test.c`: Comprehensive test suite
- `tool/build/pledge.c`: Standalone pledge wrapper tool

### Research Papers

1. "Pledge: A New Security Technology in OpenBSD" (Theo de Raadt)
2. "A Comparison of Unix Sandboxing Techniques" (FreeBSD Foundation, 2017)
3. "SandBlaster: Reversing the Apple Sandbox" (ar5iv.labs.arxiv.org/html/1608.04303)

---

## Appendix A: Example SBPL Profiles

### Example 1: stdio + rpath

```scheme
(version 1)
(deny default)
(allow process-exec (literal (param "PROCESS_PATH")))

;; Pledge promises
(allow file-read* file-write*
  (literal "/dev/stdin" "/dev/stdout" "/dev/stderr"
           "/dev/null" "/dev/zero" "/dev/urandom"))
(allow sysctl-read)
(allow process-fork)
(allow mach-lookup (global-name "com.apple.system.logger"))

(allow file-read*)
(allow file-read-metadata)
```

### Example 2: Combined pledge + unveil

```scheme
(version 1)
(deny default)
(allow process-exec (literal (param "PROCESS_PATH")))

;; Pledge promises
(allow file-read* file-write*
  (literal "/dev/stdin" "/dev/stdout" "/dev/stderr"))
(allow network-outbound)
(allow network-inbound)

;; Unveil filesystem restrictions
(allow file-read* (subpath "/etc"))
(allow file-write* (subpath "/tmp"))
(allow file-write-create (subpath "/tmp"))
(allow file-write-unlink (subpath "/tmp"))
```

### Example 3: Minimal stdio-only

```scheme
(version 1)
(deny default)
(allow process-exec (literal (param "PROCESS_PATH")))

;; Pledge: stdio only
(allow file-read* file-write*
  (literal "/dev/stdin" "/dev/stdout" "/dev/stderr"
           "/dev/null" "/dev/zero" "/dev/urandom"))
(allow sysctl-read)
(allow process-fork)
```

---

## Appendix B: Compatibility Test Matrix

| Test Name | OpenBSD | Linux | macOS | Notes |
|-----------|---------|-------|-------|-------|
| pledge_default_allowsExit | ✅ | ✅ | ✅ | Basic functionality |
| pledge_execpromises_notok | ✅ | ✅ | ⚠️ | execpromises not supported |
| pledge_tester | ✅ | ✅ | ✅ | Basic test |
| pledge_withThreadMemory | ❌ | ✅ | ✅ | OpenBSD doesn't allow |
| pledge_tgkill | ❌ | ✅ | ⚠️ | Linux-specific |
| pledge_stdio_forbidsOpeningPasswd1 | ❌ | ✅ | ✅ | Should work |
| pledge_stdio_forbidsOpeningPasswd2 | ✅ | ✅ | ✅ | Should work |
| pledge_multipleCalls_canOnlyBecomeMoreRestrictive1 | ❌ | ✅ | ⚠️ | Can't tighten on macOS |
| pledge_multipleCalls_canOnlyBecomeMoreRestrictive2 | ✅ | ❌ | ⚠️ | OpenBSD-specific |
| pledge_multipleCalls_canOnlyBecomeMoreRestrictive3 | ✅ | ❌ | ⚠️ | OpenBSD-specific |
| pledge_stdio_fcntl_allowsSomeFirstArgs | ❌ | ✅ | ✅ | Should work |
| pledge_stdioTty_sendtoRestricted_requiresNullAddr | ❌ | ✅ | ⚠️ | May work |
| pledge_unix_forbidsInetSockets | ❌ | ✅ | ✅ | Should work |
| pledge_wpath_doesNotImplyRpath | ⚠️ | ✅ | ✅ | Should work |
| pledge_inet_forbidsOtherSockets | ❌ | ✅ | ✅ | Should work |
| pledge_anet_forbidsUdpSocketsAndConnect | ❌ | ✅ | ✅ | Should work |
| pledge_mmap | ❌ | ✅ | ✅ | Should work |
| pledge_mmapProtExec | ❌ | ✅ | ✅ | Should work |
| pledge_chmod_ignoresDangerBits | ❌ | ✅ | ⚠️ | May differ |
| pledge_open_rpath | ❌ | ✅ | ✅ | Should work |
| pledge_open_wpath | ❌ | ✅ | ✅ | Should work |
| pledge_open_cpath | ❌ | ✅ | ✅ | Should work |
| pledge_execpromises_ok | ❌ | ✅ | ⚠️ | execpromises issue |
| pledge_execpromises_notok1 | ❌ | ✅ | ⚠️ | execpromises issue |
| pledge_execpromises_reducesAtExecOnLinux | ❌ | ✅ | ⚠️ | execpromises issue |
| unveil_api_differences | ⚠️ | ⚠️ | ⚠️ | Documents differences |
| unveil_rx_readOnlyPreexistingExecutable_worksFine | ⚠️ | ✅ | ✅ | Should work |
| unveil_r_noExecutePreexistingExecutable_raisesEacces | ✅ | ✅ | ✅ | Should work |
| unveil_canBeUsedAgainAfterVfork | ✅ | ✅ | ⚠️ | May work |
| unveil_rwc_createExecutableFile_isAllowedButCantBeRun | ✅ | ✅ | ✅ | Should work |
| unveil_rwcx_createExecutableFile_canAlsoBeRun | ⚠️ | ✅ | ✅ | Should work |
| unveil_dirfdHacking_doesntWork | ✅ | ✅ | ❌ | macOS allows O_PATH stat |
| unveil_mostRestrictivePolicy | ❌ | ✅ | ✅ | Should work |
| unveil_overlappingDirectories_inconsistentBehavior | ⚠️ | ⚠️ | ⚠️ | Documented difference |
| unveil_usedTwice_allowedOnLinux | ❌ | ✅ | ⚠️ | macOS allows |
| unveil_truncate_isForbiddenBySeccomp | ✅ | ⚠️ | ⚠️ | May work |
| unveil_ftruncate_isForbidden | ❌ | ✅ | ⚠️ | May work |
| unveil_procfs_isForbiddenByDefault | ❌ | ✅ | N/A | macOS has no procfs |
| unveil_isInheritedAcrossThreads | ✅ | ✅ | ⚠️ | Thread-local on macOS |
| unveil_isThreadSpecificOnLinux_isProcessWideOnOpenbsd | ⚠️ | ⚠️ | ⚠️ | Thread-local on macOS |
| unveil_usedTwice_forbidden_worksWithPledge | ❌ | ✅ | ⚠️ | May work |
| unveil_lotsOfPaths | ✅ | ✅ | ✅ | Should work (256 limit) |

**Legend:**
- ✅ Expected to pass
- ⚠️ May pass with modifications or acceptable differences
- ❌ Expected to fail (platform limitation)
- N/A Not applicable to platform

**Estimated pass rate:** 24/58 (41%) strict, 38/58 (66%) with acceptable differences

---

## Appendix C: Migration Guide

### For Application Developers

**If your code currently uses pledge/unveil:**

```c
// Before (works on OpenBSD/Linux, no-op on macOS)
pledge("stdio rpath inet", NULL);
unveil("/etc", "r");
unveil("/tmp", "rwc");
unveil(NULL, NULL);

// After polyfill (works on OpenBSD/Linux/macOS)
// NO CHANGES REQUIRED!
pledge("stdio rpath inet", NULL);
unveil("/etc", "r");
unveil("/tmp", "rwc");
unveil(NULL, NULL);
```

**Recommendations:**

1. **Call early:** Apply pledge/unveil during initialization
2. **Call once:** Don't rely on incremental tightening on macOS
3. **Test:** Verify sandbox is actually enforced
4. **Document:** Note macOS-specific behavior

### For Cosmopolitan libc Developers

**Adding new promise:**

1. Add to `libc/intrin/promises.h`:
   ```c
   #define PROMISE_NEWFEATURE 23
   ```

2. Add to `libc/calls/sbpl-generator.c`:
   ```c
   [PROMISE_NEWFEATURE] =
     "(allow some-operation)\n",
   ```

3. Add to `libc/calls/pledge-linux.c` mapping table

4. Add tests in `test/libc/calls/pledge_test.c`

---

## Appendix D: Open Questions

### For Discussion

1. **Process-wide vs Thread-local:**
   - Should we make macOS sandbox process-wide like OpenBSD?
   - Requires coordination across threads, more complex
   - **Recommendation:** Start thread-local, evaluate later

2. **execpromises support:**
   - Could we use `posix_spawn()` attributes to re-apply sandbox?
   - Requires interception of all exec variants
   - **Recommendation:** Document as limitation for v1

3. **Fallback behavior:**
   - If `sandbox_init()` fails, should we:
     - a) Return error (fail closed)
     - b) Silently continue (fail open, current behavior)
   - **Recommendation:** Return error, let app decide

4. **Weak symbol import:**
   - Should we weak-import `sandbox_init_with_parameters()`?
   - Allows running on future macOS without the API
   - **Recommendation:** Yes, with feature detection

5. **Multiple lock support:**
   - Linux allows multiple `unveil(NULL, NULL)` calls
   - Should macOS support this? (Would be complex)
   - **Recommendation:** Make subsequent locks no-ops

---

**End of Design Document**
