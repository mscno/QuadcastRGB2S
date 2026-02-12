/* quadcastrgb - set RGB lights of HyperX Quadcast S and DuoCast
 * File devio.c
 *
 * <----- License notice ----->
 * Copyright (C) 2022, 2023, 2024 Ors1mer
 *
 * You may contact the author by email:
 * ors1mer [[at]] ors1mer dot xyz
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, version 2 of the License ONLY.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see
 * <https://www.gnu.org/licenses/gpl-2.0.en.html>. For any questions
 * concerning the license, you can write to <licensing@fsf.org>.
 * Also, you may visit the Free Software Foundation at
 * 51 Franklin Street, Fifth Floor Boston, MA 02110 USA. 
 */
#include "devio.h"

/* For open_micro */
#define FREE_AND_EXIT() \
    libusb_free_device_list(devs, 1); \
    free(data_arr); \
    libusb_exit(NULL); \
    exit(libusberr)

#define HANDLE_ERR(CONDITION, MSG) \
    if(CONDITION) { \
        fprintf(stderr, MSG); \
        FREE_AND_EXIT(); \
    }
/* Microphone opening */
static int claim_dev_interface(libusb_device_handle *handle);
static libusb_device *dev_search(libusb_device **devs, ssize_t cnt);
static int is_micro(libusb_device *dev);
/* Packet transfer */
static short send_display_command(byte_t *packet,
                                  libusb_device_handle *handle);
static short send_qc2s_report(const byte_t *packet,
                              libusb_device_handle *handle);
static void qc2s_read_ack(libusb_device_handle *handle);
static void display_data_arr(libusb_device_handle *handle,
                             const byte_t *colcommand, const byte_t *end);
static void display_qc2s_data_arr(libusb_device_handle *handle,
                                  const byte_t *colcommand,
                                  const byte_t *end);
static void get_group_colors(const byte_t *colcommand, byte_t *upper,
                             byte_t *lower);
static void write_qc2s_color_packet(byte_t group, const byte_t *rgb,
                                    byte_t *packet);
#if !defined(DEBUG) && !defined(OS_MAC)
static void daemonize(int verbose);
#endif
#ifdef DEBUG
static void print_packet(const byte_t *pck, const char *str);
#endif

/* Signal handling */
volatile static sig_atomic_t nonstop = 0; /* BE CAREFUL: GLOBAL VARIABLE */
static int qc2s_controller = 0;
static byte_t qc2s_ep_out = QC2S_INTR_EP_OUT;
static byte_t qc2s_ep_in = QC2S_INTR_EP_IN;
static int qc2s_init_sent = 0;
#ifdef USE_HIDAPI
static hid_device *qc2s_hid = NULL;
#endif
static void nonstop_reset_handler(int s)
{
    /* No need in saving errno or setting the handler again
     * because the program just frees memory and exits */
    (void)s;
    nonstop = 0;
}

/* Functions */
libusb_device_handle *open_micro(datpack *data_arr)
{
    libusb_device **devs;
    libusb_device *micro_dev = NULL;
    libusb_device_handle *handle;
    struct libusb_device_descriptor descr;
    ssize_t dev_count;
    short errcode;
    errcode = libusb_init(NULL);
    if(errcode) {
        perror("libusb_init");
        free(data_arr); exit(libusberr);
    }
    dev_count = libusb_get_device_list(NULL, &devs);
    HANDLE_ERR(dev_count < 0, DEVLIST_ERR_MSG);
    micro_dev = dev_search(devs, dev_count);
    HANDLE_ERR(!micro_dev, NODEV_ERR_MSG);
    libusb_get_device_descriptor(micro_dev, &descr);
    qc2s_controller = (descr.idVendor == DEV_VID_EU &&
                       descr.idProduct == DEV_PID_NA3);
    qc2s_init_sent = 0;
#ifdef DEBUG
    fprintf(stderr, "Selected USB device: %04x:%04x\n",
            descr.idVendor, descr.idProduct);
#endif

#ifdef USE_HIDAPI
    if(qc2s_controller) {
        struct hid_device_info *hid_devs, *cur;
        qc2s_hid = NULL;
        hid_init();
        hid_devs = hid_enumerate(DEV_VID_EU, DEV_PID_NA3);
        for(cur = hid_devs; cur; cur = cur->next) {
            if(cur->interface_number == 1) {
#ifdef DEBUG
                fprintf(stderr, "hidapi: opening interface 1 path=%s\n",
                        cur->path);
#endif
                qc2s_hid = hid_open_path(cur->path);
                break;
            }
        }
        hid_free_enumeration(hid_devs);
        if(!qc2s_hid) {
            fprintf(stderr, "hidapi: couldn't open QC2S interface 1\n");
            FREE_AND_EXIT();
        }
        libusb_free_device_list(devs, 1);
        return NULL; /* no libusb handle needed for QC2S on macOS */
    }
#endif

    errcode = libusb_open(micro_dev, &handle);
    if(errcode) {
        fprintf(stderr, "%s\n%s", libusb_strerror(errcode), OPEN_ERR_MSG);
        FREE_AND_EXIT();
    }
    errcode = claim_dev_interface(handle);
    if(errcode) {
        libusb_close(handle); FREE_AND_EXIT();
    }
    libusb_free_device_list(devs, 1);
    return handle;
}

static int claim_dev_interface(libusb_device_handle *handle)
{
    int i, errs[3];
    libusb_set_auto_detach_kernel_driver(handle, 1); /* might be unsupported */
    for(i = 0; i < 3; i++)
        errs[i] = libusb_claim_interface(handle, i);
#ifdef DEBUG
    fprintf(stderr, "claim if0=%d if1=%d if2=%d\n",
            errs[0], errs[1], errs[2]);
#endif
    for(i = 0; i < 3; i++) {
        if(errs[i] == LIBUSB_ERROR_ACCESS) {
#ifdef DEBUG
            fprintf(stderr, "claim: ACCESS denied (kernel HID driver), "
                    "continuing anyway\n");
#endif
            return 0; /* macOS kernel owns HID — use hidapi instead */
        }
        if(errs[i] == LIBUSB_ERROR_BUSY) {
            fprintf(stderr, BUSY_ERR_MSG);
            return 1;
        }
        if(errs[i] == LIBUSB_ERROR_NO_DEVICE) {
            fprintf(stderr, OPEN_ERR_MSG);
            return 1;
        }
    }
    return 0;
}

static libusb_device *dev_search(libusb_device **devs, ssize_t cnt)
{
    libusb_device *fallback = NULL;
    libusb_device **dev;
    struct libusb_device_descriptor descr;
    for(dev = devs; dev < devs+cnt; dev++) {
        libusb_get_device_descriptor(*dev, &descr);
        /* QuadCast 2 S has a dedicated HID controller device. Prefer it. */
        if(descr.idVendor == DEV_VID_EU && descr.idProduct == DEV_PID_NA3)
            return *dev;
        if(!fallback && is_micro(*dev))
            fallback = *dev;
    }
    return fallback;
}

static int is_micro(libusb_device *dev)
{
    struct libusb_device_descriptor descr; /* no freeing needed */
    libusb_get_device_descriptor(dev, &descr);
    if(descr.idVendor == DEV_VID_NA) {
        if (descr.idProduct == DEV_PID_NA1 ||
            descr.idProduct == DEV_PID_NA2 ||
            descr.idProduct == DEV_PID_NA3) {
              return 1;
        }
    } else if(descr.idVendor == DEV_VID_EU) {
        if(descr.idProduct == DEV_PID_EU1 ||
           descr.idProduct == DEV_PID_EU2 ||
           descr.idProduct == DEV_PID_EU3 ||
           descr.idProduct == DEV_PID_EU4 ||
           descr.idProduct == DEV_PID_NA3 ||
           descr.idProduct == DEV_PID_DUOCAST) {
            return 1;
        }
    }
    return 0;
}

void close_micro(libusb_device_handle *handle)
{
#ifdef USE_HIDAPI
    if(qc2s_hid) {
        hid_close(qc2s_hid);
        qc2s_hid = NULL;
        hid_exit();
    }
#endif
    if(handle) {
        libusb_release_interface(handle, 0);
        libusb_release_interface(handle, 1);
        libusb_close(handle);
    }
    libusb_exit(NULL);
}

void send_packets(libusb_device_handle *handle, const datpack *data_arr,
                  int pck_cnt, int verbose)
{
    short command_cnt;
    #ifdef DEBUG
    puts("Entering display mode...");
    #endif
    #if !defined(DEBUG) && !defined(OS_MAC)
    daemonize(verbose);
    #endif
    command_cnt = count_color_commands(data_arr, pck_cnt, 0);
    signal(SIGINT, nonstop_reset_handler);
    signal(SIGTERM, nonstop_reset_handler);
    /* The loop works until a signal handler resets the variable */
    nonstop = 1; /* set to 1 only here */
    while(nonstop) {
        if(qc2s_controller) {
            display_qc2s_data_arr(handle, *data_arr,
                                  *data_arr+2*BYTE_STEP*command_cnt);
        } else {
            display_data_arr(handle, *data_arr,
                             *data_arr+2*BYTE_STEP*command_cnt);
        }
    }
}

#if !defined(DEBUG) && !defined(OS_MAC)
static void daemonize(int verbose)
{
    int pid;

    chdir("/");
    pid = fork();
    if(pid > 0)
        exit(0);
    setsid();
    pid = fork();
    if(pid > 0)
        exit(0);

    if(verbose)
        printf(PID_MSG, getpid()); /* notify the user */
    fflush(stdout); /* force clear of the buffer */
    close(0);
    close(1);
    close(2);
    open("/dev/null", O_RDONLY);
    open("/dev/null", O_WRONLY);
    open("/dev/null", O_WRONLY);
}
#endif

static void display_data_arr(libusb_device_handle *handle,
                             const byte_t *colcommand, const byte_t *end)
{
    short sent;
    byte_t *packet;
    byte_t header_packet[PACKET_SIZE] = {
        HEADER_CODE, DISPLAY_CODE, 0, 0, 0, 0, 0, 0, PACKET_CNT, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    packet = calloc(PACKET_SIZE, 1);
    while(colcommand < end && nonstop) {
        sent = send_display_command(header_packet, handle);
        if(sent != PACKET_SIZE) {
            nonstop = 0; break; /* finish program in case of any errors */
        }
        memcpy(packet, colcommand, 2*BYTE_STEP);
        sent = libusb_control_transfer(handle, BMREQUEST_TYPE_OUT,
                   BREQUEST_OUT, WVALUE, WINDEX, packet, PACKET_SIZE, TIMEOUT);
        if(sent != PACKET_SIZE) {
            nonstop = 0; break;
        }
        #ifdef DEBUG
        print_packet(packet, "Data:");
        #endif
        colcommand += 2*BYTE_STEP;
        usleep(1000*55);
    }
    free(packet);
}

static void display_qc2s_data_arr(libusb_device_handle *handle,
                                  const byte_t *colcommand,
                                  const byte_t *end)
{
    byte_t packet[PACKET_SIZE] = {0};
    byte_t upper[3], lower[3];
    short sent;
    int group;

    if(!qc2s_init_sent) {
        packet[0] = QC2S_CMD_INIT;
        packet[1] = QC2S_SUB_START;
        sent = send_qc2s_report(packet, handle);
        if(sent != PACKET_SIZE) {
            nonstop = 0;
            return;
        }
        qc2s_init_sent = 1;
    }

    while(colcommand < end && nonstop) {
        get_group_colors(colcommand, upper, lower);

        memset(packet, 0, sizeof(packet));
        packet[0] = QC2S_CMD_COLOR;
        packet[1] = QC2S_SUB_START;
        packet[2] = QC2S_GROUP_COUNT;
        sent = send_qc2s_report(packet, handle);
        if(sent != PACKET_SIZE) {
            nonstop = 0; break;
        }

        for(group = 0; group < QC2S_GROUP_COUNT && nonstop; group++) {
            const byte_t *rgb = (group < QC2S_UPPER_GROUPS) ? upper : lower;
            write_qc2s_color_packet((byte_t)group, rgb, packet);
            sent = send_qc2s_report(packet, handle);
            if(sent != PACKET_SIZE) {
                nonstop = 0; break;
            }
            usleep(1000*45);
        }
        colcommand += 2*BYTE_STEP;
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

static short send_display_command(byte_t *packet, libusb_device_handle *handle)
{
    short sent;
    sent = libusb_control_transfer(handle, BMREQUEST_TYPE_OUT, BREQUEST_OUT,
                                 WVALUE, WINDEX, packet, PACKET_SIZE,
                                 TIMEOUT);
    #ifdef DEBUG
    print_packet(packet, "Header display:");
    if(sent != PACKET_SIZE)
        fprintf(stderr, HEADER_ERR_MSG, libusb_strerror(sent));
    #endif
    return sent;
}

static short send_qc2s_report(const byte_t *packet, libusb_device_handle *handle)
{
    static const byte_t ep_out[] = {
        QC2S_INTR_EP_OUT, QC2S_INTR_EP_OUT_ALT1, QC2S_INTR_EP_OUT_ALT2
    };
    static const byte_t ep_in[] = {
        QC2S_INTR_EP_IN, QC2S_INTR_EP_IN_ALT1, QC2S_INTR_EP_IN_ALT2
    };
    int transferred = 0;
    int i;

#ifdef USE_HIDAPI
    if(qc2s_hid) {
        int res;
        (void)handle;
        res = hid_write(qc2s_hid, packet, PACKET_SIZE);
#ifdef DEBUG
        print_packet(packet, "QC2S report (hidapi):");
        if(res < 0)
            fprintf(stderr, "hidapi write error: %ls\n", hid_error(qc2s_hid));
#endif
        if(res < 0)
            return -1;
        qc2s_read_ack(handle);
        return PACKET_SIZE;
    }
#endif

    /* Try each interrupt endpoint; cache the one that works */
    for(i = 0; i < (int)(sizeof(ep_out)/sizeof(ep_out[0])); i++) {
        byte_t ep = (i == 0) ? qc2s_ep_out : ep_out[i];
        if(i > 0 && ep == qc2s_ep_out)
            continue;
        transferred = 0;
        if(!libusb_interrupt_transfer(handle, ep, (unsigned char *)packet,
                                      PACKET_SIZE, &transferred, TIMEOUT)
           && transferred == PACKET_SIZE) {
            qc2s_ep_out = ep;
            qc2s_ep_in = ep_in[i];
#ifdef DEBUG
            print_packet(packet, "QC2S report (intr):");
#endif
            qc2s_read_ack(handle);
            return PACKET_SIZE;
        }
#ifdef DEBUG
        fprintf(stderr, "intr ep 0x%02x failed\n", ep);
#endif
    }

    /* Last resort: HID SET_REPORT over control endpoint */
    transferred = libusb_control_transfer(handle, BMREQUEST_TYPE_OUT,
                      BREQUEST_OUT, (0x0200 | packet[0]), 1,
                      (unsigned char *)(packet+1), PACKET_SIZE-1, TIMEOUT);
#ifdef DEBUG
    print_packet(packet, "QC2S report (ctrl):");
    if(transferred < 0)
        fprintf(stderr, DATAPCK_ERR_MSG, libusb_strerror(transferred));
#endif
    return (transferred == PACKET_SIZE-1) ? PACKET_SIZE : (short)transferred;
}

static void qc2s_read_ack(libusb_device_handle *handle)
{
    byte_t ack[PACKET_SIZE] = {0};

#ifdef USE_HIDAPI
    if(qc2s_hid) {
        int res;
        (void)handle;
        res = hid_read_timeout(qc2s_hid, ack, PACKET_SIZE, QC2S_ACK_TIMEOUT);
#ifdef DEBUG
        if(res > 0)
            print_packet(ack, "QC2S ack (hidapi):");
        else if(res < 0)
            fprintf(stderr, "hidapi read error: %ls\n", hid_error(qc2s_hid));
#endif
        return;
    }
#endif

    {
        int errcode, transferred = 0;
        errcode = libusb_interrupt_transfer(handle, qc2s_ep_in, ack,
                                            PACKET_SIZE, &transferred,
                                            QC2S_ACK_TIMEOUT);
#ifdef DEBUG
        if(!errcode && transferred > 0)
            print_packet(ack, "QC2S ack:");
        else if(errcode && errcode != LIBUSB_ERROR_TIMEOUT)
            fprintf(stderr, "ack ep 0x%02x err=%d (%s)\n", qc2s_ep_in,
                    errcode, libusb_strerror(errcode));
#endif
    }
}

#ifdef DEBUG
static void print_packet(const byte_t *pck, const char *str)
{
    const byte_t *p;
    puts(str);
    for(p = pck; p < pck+PACKET_SIZE; p++) {
        printf("%02X ", (int)(*p));
        if((p-pck+1) % 16 == 0)
            puts("");
    }
    puts("");
}
#endif
