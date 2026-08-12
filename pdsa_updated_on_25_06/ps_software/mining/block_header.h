#ifndef BLOCK_HEADER_H
#define BLOCK_HEADER_H

#include <stdint.h>
#include <stddef.h>

#define HASH_HEX_LEN   65
#define JOB_ID_LEN     32

typedef struct {
    char     job_id[JOB_ID_LEN];
    uint8_t  header[80];
    uint32_t midstate[8];
    uint32_t merkle_tail;
    uint32_t timestamp;
    uint32_t nbits;
    uint8_t  target[32];
} mining_job_t;

#endif
