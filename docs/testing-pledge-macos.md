# Testing pledge() macOS Polyfill

## Overview

This guide explains how to test the minimal `pledge("stdio")` implementation on macOS.

## Current Status

**Implementation:** Minimal viable product
- ✅ Supports `pledge("stdio", NULL)` only
- ✅ Uses macOS Sandbox Profile Language (SBPL)
- ✅ Applies via `sandbox_init_with_parameters()`
- ❌ No other promises supported yet
- ❌ No unveil() support yet
- ❌ No execpromises support

**Files:**
- `libc/calls/pledge-xnu.internal.h` - Header declarations
- `libc/calls/pledge-xnu.c` - Implementation (~170 LOC)
- `libc/calls/pledge.c` - Integration (IsXnu() branch)
- `test_pledge_minimal.c` - Standalone test program

## Prerequisites

**Required:**
- macOS 10.15+ (Catalina or later)
- Xcode Command Line Tools
- Cosmopolitan libc source tree

**Check prerequisites:**
```bash
# Check macOS version
sw_vers

# Check if sandbox_init is available
nm /usr/lib/libSystem.dylib | grep sandbox_init
```

## Building on macOS

### Option 1: Standalone Test (Easiest)

```bash
# Build cosmopolitan.a
make -j8 MODE=rel o/rel/cosmopolitan.a

# Compile test program
gcc -o test_pledge_minimal \
    test_pledge_minimal.c \
    o/rel/cosmopolitan.a \
    -I. -Ilibc

# Run test
./test_pledge_minimal
```

**Expected output on macOS:**
```
Testing minimal pledge("stdio") implementation...

1. Opening /etc/passwd BEFORE pledge()...
   SUCCESS: Could open /etc/passwd (fd=3)

2. Calling pledge("stdio", NULL)...
   SUCCESS: pledge() returned 0

3. Opening /etc/passwd AFTER pledge()...
   SUCCESS: Could NOT open /etc/passwd: Operation not permitted
   This means the sandbox IS working!

4. Testing stdio operations...
   stdout works!
   stderr works!

✓ All tests passed!
```

### Option 2: Full Test Suite

```bash
# Build the full test suite
make -j8 MODE=rel o/rel/test/libc/calls/pledge_test

# Run pledge tests
o/rel/test/libc/calls/pledge_test
```

## What to Expect

### On macOS

**If working correctly:**
1. `pledge("stdio")` returns 0
2. Subsequent `open("/etc/passwd")` returns -1 with EPERM
3. stdio operations (printf, fprintf) still work
4. Process continues to run normally

**If NOT working:**
- Returns 0 but doesn't enforce (sandbox_init failed silently)
- Returns ENOSYS (sandbox_init_with_parameters not available)
- Crashes (SBPL syntax error)

### On Linux

**Expected behavior:**
- Continues to use Linux polyfill (seccomp-bpf)
- No change in behavior
- macOS code path not executed

### On Other Platforms

**Expected behavior:**
- Falls through to existing behavior (OpenBSD, FreeBSD)
- No change

## Debugging

### Enable Trace Logging

Set `__strace` to see detailed execution:

```bash
# In your test program
extern int __strace;
__strace = 1;
```

Or run with strace:
```bash
# macOS equivalent (dtrace/dtruss)
sudo dtruss -f ./test_pledge_minimal
```

### Check SBPL Profile

The generated SBPL profile is logged to stderr when `__strace > 0`.

**Expected profile for `pledge("stdio")`:**
```scheme
;; Minimal pledge("stdio") implementation for macOS
(version 1)
(deny default)

;; Allow self-execution
(allow process-exec (literal (param "PROCESS_PATH")))

;; PROMISE_STDIO: Basic I/O operations
(allow file-read* file-write*
  (literal "/dev/stdin" "/dev/stdout" "/dev/stderr"
           "/dev/null" "/dev/zero" "/dev/urandom"
           "/dev/random" "/dev/dtracehelper"))

;; System calls needed for basic operation
(allow sysctl-read)
(allow process-fork)
(allow mach-lookup
  (global-name "com.apple.system.logger"
               "com.apple.system.notification_center"))

;; Memory operations
(allow mach-priv-host-port)
```

### Common Issues

**1. `sandbox_init_with_parameters` not found**
```
Solution: Check macOS version (need 10.7+)
```

**2. Operation still allowed after pledge**
```
Possible causes:
- SBPL syntax error (check __strace output)
- Wrong promise (stdio doesn't block files)
- Sandbox not actually applied (check return code)
```

**3. Crashes immediately**
```
Possible causes:
- SBPL syntax error
- Invalid parameter
- SIP (System Integrity Protection) interference
```

**4. Returns ENOSYS**
```
Explanation: sandbox_init_with_parameters weak import failed
Solution: Check if function exists in libSystem.dylib
```

## Testing Against Real Test Suite

### Test: pledge_stdio_forbidsOpeningPasswd

```bash
# Run single test
o/rel/test/libc/calls/pledge_test pledge_stdio_forbidsOpeningPasswd
```

**Expected on macOS:**
- Test creates child process
- Child calls `pledge("stdio")`
- Child attempts `open("/etc/passwd", O_RDWR)`
- Should return -1 with EPERM
- Process exits cleanly

### Test: pledge_default_allowsExit

```bash
# Run single test
o/rel/test/libc/calls/pledge_test pledge_default_allowsExit
```

**Expected on macOS:**
- Test creates child with `pledge("")`
- Child should only be able to exit
- Should complete successfully

## Verification Checklist

When testing on macOS, verify:

- [ ] `pledge("stdio")` returns 0 (success)
- [ ] File operations are blocked (open returns EPERM)
- [ ] stdio operations still work (printf/fprintf)
- [ ] Process doesn't crash
- [ ] Can call pledge once (subsequent calls return EPERM)
- [ ] Child processes inherit sandbox
- [ ] __strace output shows SBPL profile being applied

## Next Steps

Once basic stdio pledge is working:

1. Add support for more promises (rpath, wpath, inet, etc.)
2. Add unveil() support
3. Improve error handling
4. Add more tests
5. Performance profiling

## Known Limitations

**Current minimal implementation:**
- ❌ Only stdio promise supported
- ❌ Cannot call pledge() multiple times
- ❌ No execpromises support
- ❌ No unveil() support
- ❌ Thread-local (not process-wide like OpenBSD)

See `docs/pledge-unveil-macos-polyfill.md` for full design.

## Reporting Issues

If testing reveals problems:

1. Capture `__strace` output
2. Note macOS version (`sw_vers`)
3. Include SBPL profile from logs
4. Describe expected vs actual behavior
5. Include minimal reproduction case

## References

- Design doc: `docs/pledge-unveil-macos-polyfill.md`
- OpenBSD pledge(2): https://man.openbsd.org/pledge.2
- macOS Sandbox: https://reverse.put.as/wp-content/uploads/2011/09/Apple-Sandbox-Guide-v1.0.pdf
