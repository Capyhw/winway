#include <unistd.h>

// A native executable with no Apple platform signature or entitlements.
// Keep inherited signal dispositions so tests can exercise SIGKILL fallback.
int main(void) {
    sleep(30);
    return 0;
}
