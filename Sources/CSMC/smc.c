#include "csmc.h"
#include <IOKit/IOKitLib.h>
#include <string.h>

#define KERNEL_INDEX_SMC 2
#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_BYTES 5
#define SMC_CMD_WRITE_BYTES 6

typedef struct { char major, minor, build, reserved; uint16_t release; } Vers;
typedef struct { uint16_t version, length; uint32_t cpuP, gpuP, memP; } PLimit;
typedef struct { uint32_t dataSize, dataType; uint8_t dataAttributes; } KeyInfo;
typedef struct {
    uint32_t key;
    Vers vers;
    PLimit pLimit;
    KeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParam;

static io_connect_t conn = 0;

static uint32_t str4(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) |
           ((uint32_t)(uint8_t)s[2] << 8) | (uint32_t)(uint8_t)s[3];
}

int smc_open(void) {
    if (conn) return 0;
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!svc) return -1;
    kern_return_t kr = IOServiceOpen(svc, mach_task_self(), 0, &conn);
    IOObjectRelease(svc);
    if (kr != KERN_SUCCESS) { conn = 0; return kr; }
    return 0;
}

void smc_close(void) {
    if (conn) IOServiceClose(conn);
    conn = 0;
}

static int call(SMCParam *in, SMCParam *out) {
    size_t outSize = sizeof(SMCParam);
    kern_return_t kr = IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, in, sizeof(SMCParam), out, &outSize);
    if (kr != KERN_SUCCESS) return kr;
    // SMC-level error (e.g. 0x84 = key not found, 0x86 = not privileged)
    return out->result == 0 ? 0 : 0x10000 | out->result;
}

static int key_info(const char *key, KeyInfo *info) {
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = str4(key);
    in.data8 = SMC_CMD_READ_KEYINFO;
    int r = call(&in, &out);
    if (r == 0) *info = out.keyInfo;
    return r;
}

int smc_read(const char *key, SMCValue *v) {
    if (smc_open() != 0) return -1;
    KeyInfo info;
    int r = key_info(key, &info);
    if (r) return r;
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = str4(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_READ_BYTES;
    r = call(&in, &out);
    if (r) return r;
    memset(v, 0, sizeof *v);
    v->size = info.dataSize > 32 ? 32 : info.dataSize;
    v->type[0] = (info.dataType >> 24) & 0xff; v->type[1] = (info.dataType >> 16) & 0xff;
    v->type[2] = (info.dataType >> 8) & 0xff;  v->type[3] = info.dataType & 0xff;
    memcpy(v->bytes, out.bytes, v->size);
    return 0;
}

int smc_write(const char *key, const uint8_t *bytes, uint32_t size) {
    if (smc_open() != 0) return -1;
    KeyInfo info;
    int r = key_info(key, &info);
    if (r) return r;
    SMCParam in, out;
    memset(&in, 0, sizeof in); memset(&out, 0, sizeof out);
    in.key = str4(key);
    in.keyInfo.dataSize = info.dataSize;
    in.data8 = SMC_CMD_WRITE_BYTES;
    memcpy(in.bytes, bytes, size > 32 ? 32 : size);
    return call(&in, &out);
}
