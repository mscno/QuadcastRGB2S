#ifndef MOCK_HIDAPI_CONTROL_H
#define MOCK_HIDAPI_CONTROL_H

#include <stdint.h>

#define MOCK_HID_PACKET_LOG_CAP 32
#define MOCK_HID_PACKET_SIZE 64

extern int mock_hid_init_calls;
extern int mock_hid_exit_calls;
extern int mock_hid_enumerate_calls;
extern int mock_hid_open_calls;
extern int mock_hid_close_calls;
extern int mock_hid_write_calls;
extern int mock_hid_read_calls;

extern int mock_hid_init_result;
extern int mock_hid_has_device;
extern int mock_hid_interface_number;
extern int mock_hid_open_success;
extern int mock_hid_write_fail_call;
extern int mock_hid_read_result;

extern int mock_hid_packet_count;
extern uint8_t mock_hid_packets[MOCK_HID_PACKET_LOG_CAP][MOCK_HID_PACKET_SIZE];

void mock_hid_reset(void);

#endif /* MOCK_HIDAPI_CONTROL_H */
