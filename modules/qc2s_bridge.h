/*
 * qc2s_bridge.h — Shared C API for QuadCast 2S RGB control
 * Thread-safe per context, depends only on hidapi.
 */
#ifndef QC2S_BRIDGE_H
#define QC2S_BRIDGE_H

#include <stdint.h>
#include "qc2s_protocol.h"

typedef struct qc2s_ctx qc2s_ctx;

/* Open the QC2S HID device (interface 1). Returns NULL on failure. */
qc2s_ctx *qc2s_open(void);

/* Send a frame: groups 0-1 get (ur,ug,ub), groups 2-5 get (lr,lg,lb).
   Returns 0 on success, -1 on error. */
int qc2s_set_frame(qc2s_ctx *ctx,
                   uint8_t ur, uint8_t ug, uint8_t ub,
                   uint8_t lr, uint8_t lg, uint8_t lb);

/* Send a solid color to all 6 LED groups. Returns 0 on success, -1 on error. */
int qc2s_set_color(qc2s_ctx *ctx, uint8_t r, uint8_t g, uint8_t b);

/* Send a raw 64-byte QC2S report. expect_ack=1 reads one ack frame. */
int qc2s_send_report(qc2s_ctx *ctx, const uint8_t *packet, int expect_ack);

/* Check if the device is still responsive. Returns 1 if connected, 0 if not. */
int qc2s_is_connected(qc2s_ctx *ctx);

/* Close the device and free context. Safe to call with NULL. */
void qc2s_close(qc2s_ctx *ctx);

#endif /* QC2S_BRIDGE_H */
