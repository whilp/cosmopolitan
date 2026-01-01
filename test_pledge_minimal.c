/*
 * Minimal test for pledge("stdio") on macOS
 *
 * Compile on macOS:
 *   make -j8 o/cosmopolitan.a
 *   gcc -o test_pledge_minimal test_pledge_minimal.c o/cosmopolitan.a
 *
 * Run:
 *   ./test_pledge_minimal
 *
 * Expected behavior on macOS:
 *   - Should successfully call pledge("stdio")
 *   - Should NOT be able to open /etc/passwd
 *   - Should exit with code 0
 */

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

// Forward declaration
int pledge(const char *promises, const char *execpromises);

int main(void) {
  int fd;

  printf("Testing minimal pledge(\"stdio\") implementation...\n");

  // Try to open /etc/passwd BEFORE pledge - should work
  printf("\n1. Opening /etc/passwd BEFORE pledge()...\n");
  fd = open("/etc/passwd", O_RDONLY);
  if (fd >= 0) {
    printf("   SUCCESS: Could open /etc/passwd (fd=%d)\n", fd);
    close(fd);
  } else {
    printf("   FAILED: Could not open /etc/passwd: %s\n", strerror(errno));
  }

  // Apply pledge
  printf("\n2. Calling pledge(\"stdio\", NULL)...\n");
  if (pledge("stdio", NULL) == 0) {
    printf("   SUCCESS: pledge() returned 0\n");
  } else {
    printf("   FAILED: pledge() returned -1: %s\n", strerror(errno));
    return 1;
  }

  // Try to open /etc/passwd AFTER pledge - should FAIL on macOS
  printf("\n3. Opening /etc/passwd AFTER pledge()...\n");
  fd = open("/etc/passwd", O_RDONLY);
  if (fd >= 0) {
    printf("   WARNING: Could still open /etc/passwd (fd=%d)\n", fd);
    printf("   This means the sandbox is NOT working!\n");
    close(fd);
    return 1;
  } else {
    printf("   SUCCESS: Could NOT open /etc/passwd: %s\n", strerror(errno));
    printf("   This means the sandbox IS working!\n");
  }

  // Try stdio operations - should work
  printf("\n4. Testing stdio operations...\n");
  printf("   stdout works!\n");
  fprintf(stderr, "   stderr works!\n");

  printf("\n✓ All tests passed!\n");
  return 0;
}
