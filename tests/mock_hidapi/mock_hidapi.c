#include "hidapi/hidapi.h"
#include "mock_hidapi_control.h"
#include <stdlib.h>
#include <string.h>

struct hid_device_ {
    int alive;
};

int mock_hid_init_calls = 0;
int mock_hid_exit_calls = 0;
int mock_hid_enumerate_calls = 0;
int mock_hid_open_calls = 0;
int mock_hid_close_calls = 0;
int mock_hid_write_calls = 0;
int mock_hid_read_calls = 0;

int mock_hid_init_result = 0;
int mock_hid_has_device = 1;
int mock_hid_interface_number = 1;
int mock_hid_open_success = 1;
int mock_hid_write_fail_call = 0;
int mock_hid_read_result = 0;

int mock_hid_packet_count = 0;
uint8_t mock_hid_packets[MOCK_HID_PACKET_LOG_CAP][MOCK_HID_PACKET_SIZE];

void mock_hid_reset(void)
{
    mock_hid_init_calls = 0;
    mock_hid_exit_calls = 0;
    mock_hid_enumerate_calls = 0;
    mock_hid_open_calls = 0;
    mock_hid_close_calls = 0;
    mock_hid_write_calls = 0;
    mock_hid_read_calls = 0;

    mock_hid_init_result = 0;
    mock_hid_has_device = 1;
    mock_hid_interface_number = 1;
    mock_hid_open_success = 1;
    mock_hid_write_fail_call = 0;
    mock_hid_read_result = 0;

    mock_hid_packet_count = 0;
    memset(mock_hid_packets, 0, sizeof(mock_hid_packets));
}

int hid_init(void)
{
    mock_hid_init_calls++;
    return mock_hid_init_result;
}

int hid_exit(void)
{
    mock_hid_exit_calls++;
    return 0;
}

struct hid_device_info *hid_enumerate(unsigned short vendor_id,
                                      unsigned short product_id)
{
    struct hid_device_info *dev;

    (void)vendor_id;
    (void)product_id;
    mock_hid_enumerate_calls++;

    if (!mock_hid_has_device)
        return NULL;

    dev = calloc(1, sizeof(*dev));
    if (!dev)
        return NULL;

    dev->path = strdup("mock-device-path");
    dev->interface_number = mock_hid_interface_number;
    return dev;
}

void hid_free_enumeration(struct hid_device_info *devs)
{
    while (devs) {
        struct hid_device_info *next = devs->next;
        free(devs->path);
        free(devs);
        devs = next;
    }
}

hid_device *hid_open_path(const char *path)
{
    hid_device *dev;

    (void)path;
    mock_hid_open_calls++;
    if (!mock_hid_open_success)
        return NULL;

    dev = calloc(1, sizeof(*dev));
    if (!dev)
        return NULL;
    dev->alive = 1;
    return dev;
}

int hid_write(hid_device *dev, const unsigned char *data, size_t length)
{
    (void)dev;
    mock_hid_write_calls++;

    if (mock_hid_packet_count < MOCK_HID_PACKET_LOG_CAP &&
        length >= MOCK_HID_PACKET_SIZE) {
        memcpy(mock_hid_packets[mock_hid_packet_count], data, MOCK_HID_PACKET_SIZE);
        mock_hid_packet_count++;
    }

    if (mock_hid_write_fail_call > 0 &&
        mock_hid_write_calls == mock_hid_write_fail_call) {
        return -1;
    }

    return (int)length;
}

int hid_read_timeout(hid_device *dev, unsigned char *data, size_t length,
                     int milliseconds)
{
    (void)dev;
    (void)milliseconds;
    mock_hid_read_calls++;
    if (data && length > 0)
        data[0] = 0;
    return mock_hid_read_result;
}

const wchar_t *hid_error(hid_device *dev)
{
    (void)dev;
    return L"mock hidapi error";
}

void hid_close(hid_device *dev)
{
    mock_hid_close_calls++;
    free(dev);
}
