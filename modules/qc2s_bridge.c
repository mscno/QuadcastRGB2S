/*
 * qc2s_bridge.c — hidapi implementation of the QC2S bridge
 * Thread-safe per context, no exit().
 */
#include "qc2s_bridge.h"
#include "qc2s_tcc_macos.h"
#include <hidapi/hidapi.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

/* USB identifiers for the QC2S RGB controller */
#define QC2S_VID       0x03f0
#define QC2S_PID       0x02b5
#define QC2S_INTERFACE 1
#define QC2S_USAGE_PAGE_PRIMARY         0xff13
#define QC2S_USAGE_PRIMARY              0xff00
#define QC2S_USAGE_PAGE_GENERIC_DESKTOP 0x0001
#define QC2S_USAGE_POINTER              0x0001
#define QC2S_USAGE_MOUSE                0x0002
#define QC2S_PATH_LIST_CAP              16

#define INTER_GROUP_MS 45

#ifdef QC2S_BRIDGE_DEBUG
#include <stdio.h>
#define QC2S_LOG(...) fprintf(stderr, __VA_ARGS__)
#else
#define QC2S_LOG(...) do { } while(0)
#endif

#ifndef QC2S_BRIDGE_DISABLE_SLEEP
#define QC2S_SLEEP_MS(MS) usleep((MS) * 1000)
#else
#define QC2S_SLEEP_MS(MS) do { (void)(MS); } while(0)
#endif

struct qc2s_ctx {
    hid_device *dev;
    int init_sent;
    pthread_mutex_t io_lock;
};

/* Process-wide hidapi lifecycle */
static pthread_mutex_t g_hid_state_lock = PTHREAD_MUTEX_INITIALIZER;
static unsigned int g_hid_refcount = 0;

/* ---- internal helpers ---- */
static int hid_system_acquire(void)
{
    int rc = 0;

    pthread_mutex_lock(&g_hid_state_lock);
    if (g_hid_refcount == 0 && hid_init() != 0)
        rc = -1;
    if (rc == 0)
        g_hid_refcount++;
    pthread_mutex_unlock(&g_hid_state_lock);

    return rc;
}

static void hid_system_release(void)
{
    pthread_mutex_lock(&g_hid_state_lock);
    if (g_hid_refcount > 0) {
        g_hid_refcount--;
        if (g_hid_refcount == 0)
            hid_exit();
    }
    pthread_mutex_unlock(&g_hid_state_lock);
}

static int send_report_locked(qc2s_ctx *ctx, const uint8_t *packet, int expect_ack)
{
    uint8_t ack[QC2S_PACKET_SIZE];
    int res;

    res = hid_write(ctx->dev, packet, QC2S_PACKET_SIZE);
    if (res < 0) {
        QC2S_LOG("[qc2s] hid_write failed\n");
        return -1;
    }

    if (expect_ack) {
        res = hid_read_timeout(ctx->dev, ack, QC2S_PACKET_SIZE, QC2S_ACK_TIMEOUT);
        if (res < 0) {
            QC2S_LOG("[qc2s] hid_read_timeout failed\n");
            return -1;
        }
    }

    return 0;
}

static int hid_listen_access_allowed(void)
{
#ifdef __APPLE__
    return qc2s_tcc_listen_access_allowed();
#else
    return 1;
#endif
}

static int send_init_locked(qc2s_ctx *ctx)
{
    uint8_t pkt[QC2S_PACKET_SIZE];

    memset(pkt, 0, sizeof(pkt));
    pkt[0] = QC2S_CMD_INIT;
    pkt[1] = QC2S_SUB_START;
    if (send_report_locked(ctx, pkt, 1) < 0)
        return -1;

    ctx->init_sent = 1;
    return 0;
}

static void build_color_packet(uint8_t group, uint8_t r, uint8_t g, uint8_t b,
                               uint8_t *packet)
{
    int i;

    memset(packet, 0, QC2S_PACKET_SIZE);
    packet[0] = QC2S_CMD_COLOR;
    packet[1] = QC2S_SUB_DATA;
    packet[2] = group;
    for (i = QC2S_RGB_OFFSET; i + 2 < QC2S_PACKET_SIZE; i += 3) {
        packet[i] = r;
        packet[i + 1] = g;
        packet[i + 2] = b;
    }
}

static int path_in_list(const char *path, const char **paths, size_t count)
{
    size_t i;

    if (!path)
        return 0;

    for (i = 0; i < count; i++) {
        if (strcmp(path, paths[i]) == 0)
            return 1;
    }
    return 0;
}

static void add_path_if_missing(const char *path, const char **paths,
                                size_t *count)
{
    if (!path || !count || *count >= QC2S_PATH_LIST_CAP)
        return;
    if (path_in_list(path, paths, *count))
        return;
    paths[*count] = path;
    (*count)++;
}

static int is_tcc_guarded_usage(const struct hid_device_info *dev)
{
    return dev &&
           dev->usage_page == QC2S_USAGE_PAGE_GENERIC_DESKTOP &&
           (dev->usage == QC2S_USAGE_POINTER || dev->usage == QC2S_USAGE_MOUSE);
}

static int is_vendor_usage(const struct hid_device_info *dev)
{
    return dev && dev->usage_page >= 0xff00;
}

static int matches_pass(int pass, const struct hid_device_info *dev)
{
    if (!dev)
        return 0;

    switch (pass) {
    case 0:
        return dev->interface_number == QC2S_INTERFACE &&
               dev->usage_page == QC2S_USAGE_PAGE_PRIMARY &&
               dev->usage == QC2S_USAGE_PRIMARY;
    case 1:
        return dev->interface_number == QC2S_INTERFACE &&
               dev->usage_page == QC2S_USAGE_PAGE_PRIMARY;
    case 2:
        return dev->interface_number == QC2S_INTERFACE &&
               is_vendor_usage(dev);
    case 3:
        return is_vendor_usage(dev);
    case 4:
        return dev->interface_number == QC2S_INTERFACE &&
               !is_tcc_guarded_usage(dev);
    case 5:
        return !is_tcc_guarded_usage(dev);
    default:
        return dev->usage_page == QC2S_USAGE_PAGE_PRIMARY &&
               dev->usage == QC2S_USAGE_PRIMARY;
    }
}

/* ---- public API ---- */
qc2s_ctx *qc2s_open(void)
{
    struct hid_device_info *devs, *cur;
    const char *attempted_paths[QC2S_PATH_LIST_CAP] = {0};
    size_t attempted_count = 0;
    hid_device *dev = NULL;
    qc2s_ctx *ctx;
    int pass;

    if (!hid_listen_access_allowed()) {
        QC2S_LOG("[qc2s] Input Monitoring (ListenEvent) not granted\n");
        return NULL;
    }

    if (hid_system_acquire() != 0) {
        QC2S_LOG("[qc2s] hid_init failed\n");
        return NULL;
    }

    devs = hid_enumerate(QC2S_VID, QC2S_PID);
    if (!devs) {
        hid_system_release();
        return NULL;
    }

    for (pass = 0; pass < 6 && !dev; pass++) {
        for (cur = devs; cur; cur = cur->next) {
            if (!cur->path)
                continue;
            if (!matches_pass(pass, cur))
                continue;
            if (path_in_list(cur->path, attempted_paths, attempted_count))
                continue;

            add_path_if_missing(cur->path, attempted_paths, &attempted_count);
            dev = hid_open_path(cur->path);
            if (dev) {
                QC2S_LOG("[qc2s] opened HID path %s (iface=%d usage=0x%04hx:0x%04hx)\n",
                         cur->path, cur->interface_number, cur->usage_page,
                         cur->usage);
                break;
            }
        }
    }
    hid_free_enumeration(devs);

    if (!dev) {
        hid_system_release();
        return NULL;
    }

    ctx = calloc(1, sizeof(*ctx));
    if (!ctx) {
        hid_close(dev);
        hid_system_release();
        return NULL;
    }

    ctx->dev = dev;
    ctx->init_sent = 0;
    if (pthread_mutex_init(&ctx->io_lock, NULL) != 0) {
        hid_close(dev);
        free(ctx);
        hid_system_release();
        return NULL;
    }

    return ctx;
}

int qc2s_send_report(qc2s_ctx *ctx, const uint8_t *packet, int expect_ack)
{
    int rc;

    if (!ctx || !ctx->dev || !packet)
        return -1;

    pthread_mutex_lock(&ctx->io_lock);
    rc = send_report_locked(ctx, packet, expect_ack ? 1 : 0);
    pthread_mutex_unlock(&ctx->io_lock);

    return rc;
}

int qc2s_set_frame(qc2s_ctx *ctx,
                   uint8_t ur, uint8_t ug, uint8_t ub,
                   uint8_t lr, uint8_t lg, uint8_t lb)
{
    uint8_t pkt[QC2S_PACKET_SIZE];
    int group;
    int rc = -1;

    if (!ctx || !ctx->dev)
        return -1;

    pthread_mutex_lock(&ctx->io_lock);

    if (!ctx->init_sent) {
        if (send_init_locked(ctx) < 0)
            goto done;
    }

    memset(pkt, 0, sizeof(pkt));
    pkt[0] = QC2S_CMD_COLOR;
    pkt[1] = QC2S_SUB_START;
    pkt[2] = QC2S_GROUP_COUNT;
    if (send_report_locked(ctx, pkt, 1) < 0)
        goto done;

    for (group = 0; group < QC2S_GROUP_COUNT; group++) {
        if (group < QC2S_UPPER_GROUPS)
            build_color_packet((uint8_t)group, ur, ug, ub, pkt);
        else
            build_color_packet((uint8_t)group, lr, lg, lb, pkt);

        if (send_report_locked(ctx, pkt, 1) < 0)
            goto done;
        QC2S_SLEEP_MS(INTER_GROUP_MS);
    }

    rc = 0;
done:
    pthread_mutex_unlock(&ctx->io_lock);
    return rc;
}

int qc2s_set_color(qc2s_ctx *ctx, uint8_t r, uint8_t g, uint8_t b)
{
    return qc2s_set_frame(ctx, r, g, b, r, g, b);
}

int qc2s_is_connected(qc2s_ctx *ctx)
{
    uint8_t pkt[QC2S_PACKET_SIZE];
    int rc;

    if (!ctx || !ctx->dev)
        return 0;

    pthread_mutex_lock(&ctx->io_lock);
    memset(pkt, 0, sizeof(pkt));
    pkt[0] = QC2S_CMD_INIT;
    pkt[1] = QC2S_SUB_START;
    rc = (send_report_locked(ctx, pkt, 1) == 0);
    if (rc)
        ctx->init_sent = 1;
    pthread_mutex_unlock(&ctx->io_lock);

    return rc;
}

void qc2s_close(qc2s_ctx *ctx)
{
    hid_device *dev;

    if (!ctx)
        return;

    pthread_mutex_lock(&ctx->io_lock);
    dev = ctx->dev;
    ctx->dev = NULL;
    pthread_mutex_unlock(&ctx->io_lock);

    if (dev)
        hid_close(dev);

    pthread_mutex_destroy(&ctx->io_lock);
    free(ctx);
    hid_system_release();
}
