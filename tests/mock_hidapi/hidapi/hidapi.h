#ifndef MOCK_HIDAPI_H
#define MOCK_HIDAPI_H

#include <stddef.h>
#include <wchar.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct hid_device_ hid_device;

struct hid_device_info {
    char *path;
    unsigned short vendor_id;
    unsigned short product_id;
    wchar_t *serial_number;
    unsigned short release_number;
    wchar_t *manufacturer_string;
    wchar_t *product_string;
    unsigned short usage_page;
    unsigned short usage;
    int interface_number;
    struct hid_device_info *next;
};

int hid_init(void);
int hid_exit(void);
struct hid_device_info *hid_enumerate(unsigned short vendor_id,
                                      unsigned short product_id);
void hid_free_enumeration(struct hid_device_info *devs);
hid_device *hid_open_path(const char *path);
int hid_write(hid_device *dev, const unsigned char *data, size_t length);
int hid_read_timeout(hid_device *dev, unsigned char *data, size_t length,
                     int milliseconds);
const wchar_t *hid_error(hid_device *dev);
void hid_close(hid_device *dev);

#ifdef __cplusplus
}
#endif

#endif /* MOCK_HIDAPI_H */
