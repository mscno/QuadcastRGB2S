#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "../modules/qc2s_bridge.h"
#include "../modules/qc2s_protocol.h"
#include "mock_hidapi/mock_hidapi_control.h"

static int tests_run = 0;
static int tests_failed = 0;

#define ASSERT_TRUE(cond, msg) do { \
    tests_run++; \
    if (!(cond)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, msg); \
        tests_failed++; \
    } \
} while (0)

#define ASSERT_EQ_INT(a, b, msg) do { \
    tests_run++; \
    if ((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d: %s (got %d want %d)\n", \
                __FILE__, __LINE__, msg, (int)(a), (int)(b)); \
        tests_failed++; \
    } \
} while (0)

static void assert_group_packet_rgb(const uint8_t *packet,
                                    uint8_t group,
                                    uint8_t r, uint8_t g, uint8_t b)
{
    int i;
    ASSERT_EQ_INT(packet[0], QC2S_CMD_COLOR, "group packet cmd");
    ASSERT_EQ_INT(packet[1], QC2S_SUB_DATA, "group packet sub");
    ASSERT_EQ_INT(packet[2], group, "group packet id");
    for (i = QC2S_RGB_OFFSET; i + 2 < QC2S_PACKET_SIZE; i += 3) {
        ASSERT_EQ_INT(packet[i], r, "group packet R fill");
        ASSERT_EQ_INT(packet[i + 1], g, "group packet G fill");
        ASSERT_EQ_INT(packet[i + 2], b, "group packet B fill");
    }
}

static void test_open_close_refcount(void)
{
    qc2s_ctx *ctx1;
    qc2s_ctx *ctx2;

    mock_hid_reset();

    ctx1 = qc2s_open();
    ctx2 = qc2s_open();
    ASSERT_TRUE(ctx1 != NULL, "first open should succeed");
    ASSERT_TRUE(ctx2 != NULL, "second open should succeed");
    ASSERT_EQ_INT(mock_hid_init_calls, 1, "hid_init should run once");

    qc2s_close(ctx1);
    ASSERT_EQ_INT(mock_hid_exit_calls, 0, "hid_exit waits for last context");

    qc2s_close(ctx2);
    ASSERT_EQ_INT(mock_hid_exit_calls, 1, "hid_exit after last close");
}

static void test_set_color_packet_sequence(void)
{
    qc2s_ctx *ctx;
    int g;

    mock_hid_reset();
    ctx = qc2s_open();
    ASSERT_TRUE(ctx != NULL, "open for set_color");
    ASSERT_EQ_INT(qc2s_set_color(ctx, 0x11, 0x22, 0x33), 0, "set_color succeeds");

    ASSERT_EQ_INT(mock_hid_write_calls, 8, "set_color writes init + start + 6 groups");
    ASSERT_EQ_INT(mock_hid_read_calls, 8, "set_color reads ack for each write");
    ASSERT_EQ_INT(mock_hid_packets[0][0], QC2S_CMD_INIT, "packet0 init cmd");
    ASSERT_EQ_INT(mock_hid_packets[0][1], QC2S_SUB_START, "packet0 init sub");
    ASSERT_EQ_INT(mock_hid_packets[1][0], QC2S_CMD_COLOR, "packet1 color cmd");
    ASSERT_EQ_INT(mock_hid_packets[1][1], QC2S_SUB_START, "packet1 start sub");
    ASSERT_EQ_INT(mock_hid_packets[1][2], QC2S_GROUP_COUNT, "packet1 group count");

    for (g = 0; g < QC2S_GROUP_COUNT; g++) {
        assert_group_packet_rgb(mock_hid_packets[2 + g], (uint8_t)g,
                                0x11, 0x22, 0x33);
    }

    qc2s_close(ctx);
}

static void test_set_frame_uses_upper_and_lower_colors(void)
{
    qc2s_ctx *ctx;
    int g;

    mock_hid_reset();
    ctx = qc2s_open();
    ASSERT_TRUE(ctx != NULL, "open for set_frame");
    ASSERT_EQ_INT(qc2s_set_frame(ctx, 0xAA, 0xBB, 0xCC, 0x11, 0x22, 0x33),
                  0, "set_frame succeeds");

    for (g = 0; g < QC2S_GROUP_COUNT; g++) {
        if (g < QC2S_UPPER_GROUPS) {
            assert_group_packet_rgb(mock_hid_packets[2 + g], (uint8_t)g,
                                    0xAA, 0xBB, 0xCC);
        } else {
            assert_group_packet_rgb(mock_hid_packets[2 + g], (uint8_t)g,
                                    0x11, 0x22, 0x33);
        }
    }

    qc2s_close(ctx);
}

static void test_set_color_write_error(void)
{
    qc2s_ctx *ctx;

    mock_hid_reset();
    mock_hid_write_fail_call = 1;
    ctx = qc2s_open();
    ASSERT_TRUE(ctx != NULL, "open for write error");
    ASSERT_EQ_INT(qc2s_set_color(ctx, 1, 2, 3), -1, "set_color should fail on write error");
    qc2s_close(ctx);
}

static void test_connectivity_check(void)
{
    qc2s_ctx *ctx;

    mock_hid_reset();
    ctx = qc2s_open();
    ASSERT_TRUE(ctx != NULL, "open for connectivity");

    mock_hid_read_result = 0;
    ASSERT_EQ_INT(qc2s_is_connected(ctx), 1, "connected when report roundtrip succeeds");

    mock_hid_write_fail_call = mock_hid_write_calls + 1;
    ASSERT_EQ_INT(qc2s_is_connected(ctx), 0, "disconnected on write failure");

    mock_hid_write_fail_call = 0;
    mock_hid_read_result = -1;
    ASSERT_EQ_INT(qc2s_is_connected(ctx), 0, "disconnected on read failure");

    qc2s_close(ctx);
}

int main(void)
{
    test_open_close_refcount();
    test_set_color_packet_sequence();
    test_set_frame_uses_upper_and_lower_colors();
    test_set_color_write_error();
    test_connectivity_check();

    if (tests_failed) {
        fprintf(stderr, "\n%d/%d tests FAILED\n", tests_failed, tests_run);
        return 1;
    }

    printf("All %d bridge tests passed\n", tests_run);
    return 0;
}
