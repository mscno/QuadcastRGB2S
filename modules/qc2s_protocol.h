/*
 * qc2s_protocol.h — shared protocol constants for QuadCast 2S RGB controller.
 */
#ifndef QC2S_PROTOCOL_H
#define QC2S_PROTOCOL_H

/* Packet layout */
#define QC2S_PACKET_SIZE 64
#define QC2S_GROUP_COUNT 6
#define QC2S_UPPER_GROUPS 2
#define QC2S_RGB_OFFSET 4

/* Report commands */
#define QC2S_CMD_INIT 0x10
#define QC2S_CMD_COLOR 0x44
#define QC2S_SUB_START 0x01
#define QC2S_SUB_DATA 0x02

/* HID interrupt endpoints used by QC2S firmware variants */
#define QC2S_INTR_EP_OUT 0x06
#define QC2S_INTR_EP_OUT_ALT1 0x04
#define QC2S_INTR_EP_OUT_ALT2 0x02
#define QC2S_INTR_EP_IN 0x85
#define QC2S_INTR_EP_IN_ALT1 0x83
#define QC2S_INTR_EP_IN_ALT2 0x81

/* Ack timeout (milliseconds) */
#define QC2S_ACK_TIMEOUT 100

#endif /* QC2S_PROTOCOL_H */
