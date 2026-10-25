#ifndef CSMC_H
#define CSMC_H
#include <stdint.h>
#include <stdbool.h>

typedef struct {
    uint32_t size;
    char type[5];
    uint8_t bytes[32];
} SMCValue;

// Returns 0 on success, otherwise an IOKit/SMC error code.
int smc_open(void);
void smc_close(void);
int smc_read(const char *key, SMCValue *out);
int smc_write(const char *key, const uint8_t *bytes, uint32_t size);
#endif
