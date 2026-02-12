#include "qc2s_tcc_macos.h"

#ifdef __APPLE__
#include <IOKit/hidsystem/IOHIDLib.h>
#endif

int qc2s_tcc_listen_access_allowed(void)
{
#ifdef __APPLE__
    static int cached = -1;
    IOHIDAccessType access;

    if (cached == 1)
        return 1;
    if (cached == 0)
        return 0;

    access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    if (access == kIOHIDAccessTypeGranted) {
        cached = 1;
        return 1;
    }

    if (access == kIOHIDAccessTypeUnknown &&
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)) {
        cached = 1;
        return 1;
    }

    cached = 0;
    return 0;
#else
    return 1;
#endif
}
