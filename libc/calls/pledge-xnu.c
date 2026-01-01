/*-*- mode:c;indent-tabs-mode:nil;c-basic-offset:2;tab-width:8;coding:utf-8 -*-│
│ vi: set et ft=c ts=2 sts=2 sw=2 fenc=utf-8                               :vi │
╞══════════════════════════════════════════════════════════════════════════════╡
│ Copyright 2025 Justine Alexandra Roberts Tunney                              │
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
#include "libc/calls/pledge-xnu.internal.h"
#include "libc/calls/pledge.internal.h"
#include "libc/dce.h"
#include "libc/errno.h"
#include "libc/intrin/kprintf.h"
#include "libc/intrin/promises.h"
#include "libc/intrin/strace.h"
#include "libc/runtime/runtime.h"
#include "libc/str/str.h"
#include "libc/sysv/errfuns.h"

#if defined(__APPLE__) && defined(__MACH__)

/**
 * @fileoverview Minimal macOS pledge() polyfill
 *
 * This is a minimal implementation supporting only pledge("stdio")
 * to validate the approach. Full implementation in design doc.
 */

#define SBPL_MAX_SIZE 4096

// Thread-local state for macOS sandbox
_Thread_local static struct {
  unsigned long promises;     // Inverted pledge promise bitmask
  bool pledge_called;         // Has pledge() been invoked?
  bool sandbox_active;        // Has sandbox_init() been called?
} XnuSandboxState = {
  .promises = -1UL,           // Start with all denied
  .pledge_called = false,
  .sandbox_active = false,
};

/**
 * Generates SBPL profile for stdio promise only.
 */
static int generate_sbpl_stdio(char *out, size_t outsize) {
  int pos = 0;

  // Header
  pos += snprintf(out + pos, outsize - pos,
    ";; Minimal pledge(\"stdio\") implementation for macOS\n"
    "(version 1)\n"
    "(deny default)\n"
    "\n"
    ";; Allow self-execution\n"
    "(allow process-exec (literal (param \"PROCESS_PATH\")))\n"
    "\n"
    ";; PROMISE_STDIO: Basic I/O operations\n"
    "(allow file-read* file-write*\n"
    "  (literal \"/dev/stdin\" \"/dev/stdout\" \"/dev/stderr\"\n"
    "           \"/dev/null\" \"/dev/zero\" \"/dev/urandom\"\n"
    "           \"/dev/random\" \"/dev/dtracehelper\"))\n"
    "\n"
    ";; System calls needed for basic operation\n"
    "(allow sysctl-read)\n"
    "(allow process-fork)\n"
    "(allow mach-lookup\n"
    "  (global-name \"com.apple.system.logger\"\n"
    "               \"com.apple.system.notification_center\"))\n"
    "\n"
    ";; Memory operations\n"
    "(allow mach-priv-host-port)\n"
    "\n");

  if (pos >= outsize) {
    return -1;
  }

  return pos;
}

/**
 * Applies the sandbox by generating SBPL and calling sandbox_init.
 */
static int apply_sandbox_xnu(void) {
  char profile[SBPL_MAX_SIZE];
  char *error = NULL;
  int rc;

  // Check if sandbox_init is available
  if (!sandbox_init_with_parameters) {
    STRACE("pledge/xnu: sandbox_init_with_parameters not available");
    // Silently succeed like current behavior
    return 0;
  }

  // Already active?
  if (XnuSandboxState.sandbox_active) {
    return 0;
  }

  // For now, we only support stdio
  // In full implementation, this would handle all promises
  if (~XnuSandboxState.promises & (1UL << PROMISE_STDIO)) {
    // stdio is allowed - generate profile
    rc = generate_sbpl_stdio(profile, sizeof(profile));
  } else {
    // Only stdio supported in minimal impl
    STRACE("pledge/xnu: only stdio promise supported in minimal implementation");
    return enosys();
  }

  if (rc < 0) {
    kprintf("pledge/xnu: SBPL profile generation failed\n");
    return enomem();
  }

  // Debug logging
  if (__strace > 0) {
    kprintf("pledge/xnu: Applying sandbox profile (%d bytes):\n%s\n",
            rc, profile);
  }

  // Prepare parameters
  const char *params[] = {
    "PROCESS_PATH", program_invocation_name,
    NULL
  };

  // Apply sandbox
  rc = sandbox_init_with_parameters(profile, 0, params, &error);

  if (rc != 0) {
    if (error) {
      kprintf("pledge/xnu: sandbox_init failed: %s\n", error);
      sandbox_free_error(error);
    }
    return -1;
  }

  // Mark as active
  XnuSandboxState.sandbox_active = true;
  STRACE("pledge/xnu: sandbox successfully applied");

  return 0;
}

/**
 * Stores pledge promises and applies sandbox on macOS.
 *
 * Minimal implementation supporting only pledge("stdio", NULL).
 *
 * @param ipromises inverted bitmask of allowed promises
 * @param mode pledge mode flags (ignored in minimal impl)
 * @return 0 on success, -1 w/ errno on error
 */
int sys_pledge_xnu(unsigned long ipromises, int mode) {
  (void)mode;  // Unused in minimal implementation

  // Check if sandbox already active
  if (XnuSandboxState.sandbox_active) {
    // On macOS, we cannot tighten policy after sandbox is active
    // This is a known limitation vs OpenBSD/Linux
    return eperm();
  }

  // Store the promise mask
  XnuSandboxState.promises = ipromises;
  XnuSandboxState.pledge_called = true;

  // Apply immediately (no unveil support in minimal impl)
  return apply_sandbox_xnu();
}

#else /* !__APPLE__ */

// Stub for non-macOS platforms
int sys_pledge_xnu(unsigned long ipromises, int mode) {
  (void)ipromises;
  (void)mode;
  return enosys();
}

#endif /* __APPLE__ && __MACH__ */
