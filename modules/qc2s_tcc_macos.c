#include "qc2s_tcc_macos.h"

#ifdef __APPLE__
#include <IOKit/hidsystem/IOHIDLib.h>
#endif

int qc2s_tcc_listen_access_allowed(void)
{
#ifdef __APPLE__
    IOHIDAccessType access;

    access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent);
    if (access == kIOHIDAccessTypeGranted)
        return 1;

    if (access == kIOHIDAccessTypeUnknown &&
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent))
        return 1;

    return 0;
#else
    return 1;
#endif
}
