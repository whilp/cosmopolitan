#ifndef COSMOPOLITAN_LIBC_CALLS_PLEDGE_XNU_INTERNAL_H_
#define COSMOPOLITAN_LIBC_CALLS_PLEDGE_XNU_INTERNAL_H_
COSMOPOLITAN_C_START_

/**
 * @fileoverview macOS pledge() polyfill using Sandbox Profile Language
 *
 * This implements OpenBSD's pledge() on macOS by translating pledge
 * promises into SBPL (Sandbox Profile Language) and applying them
 * via sandbox_init_with_parameters().
 */

#if defined(__APPLE__) && defined(__MACH__)

// macOS Sandbox API declarations
// These functions are in libsystem_sandbox.dylib but not in public headers
// They are stable ABI used by Chrome, Firefox, and Apple's own tools

extern int sandbox_init_with_parameters(
    const char *profile,
    uint64_t flags,
    const char *const parameters[],
    char **errorbuf
) __attribute__((weak_import));

extern void sandbox_free_error(char *errorbuf)
    __attribute__((weak_import));

// Our implementation
int sys_pledge_xnu(unsigned long ipromises, int mode);

#endif /* __APPLE__ && __MACH__ */

COSMOPOLITAN_C_END_
#endif /* COSMOPOLITAN_LIBC_CALLS_PLEDGE_XNU_INTERNAL_H_ */
