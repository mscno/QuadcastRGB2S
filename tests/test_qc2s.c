/* Unit tests for QC2S packet building functions.
 * Build: make test
 * These test pure functions that don't require USB hardware.
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Pull in the types we need */
#include "../modules/rgbmodes.h"
#include "../modules/qc2s_protocol.h"

/* Keep test independent from libusb-heavy headers */
#define PACKET_SIZE QC2S_PACKET_SIZE

static int tests_run = 0;
static int tests_failed = 0;

#define ASSERT_EQ(a, b, msg) do { \
    tests_run++; \
    if((a) != (b)) { \
        fprintf(stderr, "FAIL %s:%d: %s (got %d, want %d)\n", \
                __FILE__, __LINE__, msg, (int)(a), (int)(b)); \
        tests_failed++; \
    } \
} while(0)

#define ASSERT_MEM_EQ(a, b, n, msg) do { \
    tests_run++; \
    if(memcmp((a), (b), (n)) != 0) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, msg); \
        tests_failed++; \
    } \
} while(0)

/* ---- Functions under test (copied to avoid libusb dependency) ---- */

static void write_qc2s_color_packet(byte_t group, const byte_t *rgb,
                                    byte_t *packet)
{
    int i;
    memset(packet, 0, PACKET_SIZE);
    packet[0] = QC2S_CMD_COLOR;
    packet[1] = QC2S_SUB_DATA;
    packet[2] = group;
    for(i = QC2S_RGB_OFFSET; i+2 < PACKET_SIZE; i += 3) {
        packet[i] = rgb[0];
        packet[i+1] = rgb[1];
        packet[i+2] = rgb[2];
    }
}

static void get_group_colors(const byte_t *colcommand, byte_t *upper,
                             byte_t *lower)
{
    if(*colcommand == RGB_CODE) {
        memcpy(upper, colcommand+1, 3);
    } else {
        memset(upper, 0, 3);
    }

    if(*(colcommand+BYTE_STEP) == RGB_CODE) {
        memcpy(lower, colcommand+BYTE_STEP+1, 3);
    } else {
        memset(lower, 0, 3);
    }
}

/* ---- Tests ---- */

static void test_write_color_packet_header(void)
{
    byte_t packet[PACKET_SIZE];
    byte_t rgb[3] = {0xFF, 0x55, 0x00};

    write_qc2s_color_packet(3, rgb, packet);

    ASSERT_EQ(packet[0], QC2S_CMD_COLOR, "byte 0 should be CMD_COLOR");
    ASSERT_EQ(packet[1], QC2S_SUB_DATA, "byte 1 should be SUB_DATA");
    ASSERT_EQ(packet[2], 3, "byte 2 should be group index");
    ASSERT_EQ(packet[3], 0, "byte 3 should be zero padding");
}

static void test_write_color_packet_rgb_fill(void)
{
    byte_t packet[PACKET_SIZE];
    byte_t rgb[3] = {0xFF, 0x55, 0x00};
    int i;

    write_qc2s_color_packet(0, rgb, packet);

    /* Verify all RGB triplets from offset 4 onward */
    for(i = QC2S_RGB_OFFSET; i+2 < PACKET_SIZE; i += 3) {
        ASSERT_EQ(packet[i],   0xFF, "R byte in triplet");
        ASSERT_EQ(packet[i+1], 0x55, "G byte in triplet");
        ASSERT_EQ(packet[i+2], 0x00, "B byte in triplet");
    }
}

static void test_write_color_packet_black(void)
{
    byte_t packet[PACKET_SIZE];
    byte_t rgb[3] = {0, 0, 0};
    int i;

    write_qc2s_color_packet(5, rgb, packet);

    ASSERT_EQ(packet[0], QC2S_CMD_COLOR, "header present for black");
    /* All data bytes should be zero */
    for(i = QC2S_RGB_OFFSET; i < PACKET_SIZE; i++)
        ASSERT_EQ(packet[i], 0, "black pixel should be 0");
}

static void test_write_color_packet_all_groups(void)
{
    byte_t packet[PACKET_SIZE];
    byte_t rgb[3] = {0xAA, 0xBB, 0xCC};
    int g;

    for(g = 0; g < QC2S_GROUP_COUNT; g++) {
        write_qc2s_color_packet((byte_t)g, rgb, packet);
        ASSERT_EQ(packet[2], g, "group index matches");
    }
}

static void test_get_group_colors_both_set(void)
{
    /* Simulate datpack layout: [RGB_CODE R G B] [RGB_CODE R G B] ... */
    byte_t colcommand[8] = {0};
    byte_t upper[3], lower[3];

    colcommand[0] = RGB_CODE;
    colcommand[1] = 0xFF; colcommand[2] = 0x00; colcommand[3] = 0xAA;
    colcommand[BYTE_STEP] = RGB_CODE;
    colcommand[BYTE_STEP+1] = 0x11; colcommand[BYTE_STEP+2] = 0x22;
    colcommand[BYTE_STEP+3] = 0x33;

    get_group_colors(colcommand, upper, lower);

    ASSERT_EQ(upper[0], 0xFF, "upper R");
    ASSERT_EQ(upper[1], 0x00, "upper G");
    ASSERT_EQ(upper[2], 0xAA, "upper B");
    ASSERT_EQ(lower[0], 0x11, "lower R");
    ASSERT_EQ(lower[1], 0x22, "lower G");
    ASSERT_EQ(lower[2], 0x33, "lower B");
}

static void test_get_group_colors_upper_only(void)
{
    byte_t colcommand[8] = {0};
    byte_t upper[3], lower[3];

    colcommand[0] = RGB_CODE;
    colcommand[1] = 0xDD; colcommand[2] = 0xEE; colcommand[3] = 0xFF;
    /* lower has no RGB_CODE marker */

    get_group_colors(colcommand, upper, lower);

    ASSERT_EQ(upper[0], 0xDD, "upper R set");
    ASSERT_EQ(lower[0], 0, "lower R zeroed");
    ASSERT_EQ(lower[1], 0, "lower G zeroed");
    ASSERT_EQ(lower[2], 0, "lower B zeroed");
}

static void test_get_group_colors_neither_set(void)
{
    byte_t colcommand[8] = {0};
    byte_t upper[3] = {0xFF, 0xFF, 0xFF};
    byte_t lower[3] = {0xFF, 0xFF, 0xFF};

    get_group_colors(colcommand, upper, lower);

    ASSERT_EQ(upper[0], 0, "upper zeroed when no RGB_CODE");
    ASSERT_EQ(lower[0], 0, "lower zeroed when no RGB_CODE");
}

static void test_triplet_count(void)
{
    /* 64 bytes total, offset 4 = 60 data bytes, 60/3 = 20 triplets */
    int count = (PACKET_SIZE - QC2S_RGB_OFFSET) / 3;
    ASSERT_EQ(count, 20, "should fit 20 RGB triplets per packet");
}

int main(void)
{
    test_write_color_packet_header();
    test_write_color_packet_rgb_fill();
    test_write_color_packet_black();
    test_write_color_packet_all_groups();
    test_get_group_colors_both_set();
    test_get_group_colors_upper_only();
    test_get_group_colors_neither_set();
    test_triplet_count();

    if(tests_failed) {
        fprintf(stderr, "\n%d/%d tests FAILED\n", tests_failed, tests_run);
        return 1;
    }
    printf("All %d tests passed\n", tests_run);
    return 0;
}
