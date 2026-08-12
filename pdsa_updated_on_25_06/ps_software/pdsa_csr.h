#ifndef PDSA_CSR_H
#define PDSA_CSR_H

#include <stdint.h>
#include <stdbool.h>

#define PDSA_CSR_BASE      0xA0000000
#define PDSA_CSR_RANGE     0x10000    /* 64 KB */

/* Offsets (32-bit word addressing, addr[11:2] in RTL) */
#define CSR_CTRL           0x00
#define CSR_STATUS         0x04
#define CSR_ALGO_SEL       0x08
#define CSR_START_NONCE    0x0C
#define CSR_TARGET_0       0x10
#define CSR_TARGET_1       0x14
#define CSR_TARGET_2       0x18
#define CSR_TARGET_3       0x1C
#define CSR_TARGET_4       0x20
#define CSR_TARGET_5       0x24
#define CSR_TARGET_6       0x28
#define CSR_TARGET_7       0x2C
#define CSR_MIDSTATE_0     0x30
#define CSR_MIDSTATE_1     0x34
#define CSR_MIDSTATE_2     0x38
#define CSR_MIDSTATE_3     0x3C
#define CSR_MIDSTATE_4     0x40
#define CSR_MIDSTATE_5     0x44
#define CSR_MIDSTATE_6     0x48
#define CSR_MIDSTATE_7     0x4C
#define CSR_JOB_DATA_0     0x50
#define CSR_JOB_DATA_1     0x54
#define CSR_JOB_DATA_2     0x58
#define CSR_JOB_DATA_3     0x5C
#define CSR_JOB_DATA_4     0x60
#define CSR_JOB_DATA_5     0x64
#define CSR_JOB_DATA_6     0x68
#define CSR_JOB_DATA_7     0x6C
#define CSR_JOB_DATA_8     0x70
#define CSR_JOB_DATA_9     0x74
#define CSR_JOB_DATA_10    0x78
#define CSR_JOB_DATA_11    0x7C
#define CSR_JOB_DATA_12    0x80
#define CSR_JOB_DATA_13    0x84
#define CSR_JOB_DATA_14    0x88
#define CSR_JOB_DATA_15    0x8C
#define CSR_JOB_DATA_16    0x90
#define CSR_JOB_DATA_17    0x94
#define CSR_JOB_DATA_18    0x98
#define CSR_JOB_DATA_19    0x9C
#define CSR_PT_THRESHOLD   0xA0
#define CSR_PT_CURRENT     0xA4
#define CSR_BCV_STATUS     0xA8
/* read-only status registers */
#define CSR_HASH_COUNT_LO  0xB0
#define CSR_HASH_COUNT_HI  0xB4
#define CSR_GOLDEN_NONCE   0xB8
#define CSR_DPR_LATENCY    0xBC
#define CSR_HASHRATE       0xC0
#define CSR_PDSA_DECISION  0xC4
#define CSR_RESULT_HASH_0  0xC8
#define CSR_RESULT_HASH_1  0xCC
#define CSR_RESULT_HASH_2  0xD0
#define CSR_RESULT_HASH_3  0xD4
#define CSR_RESULT_HASH_4  0xD8
#define CSR_RESULT_HASH_5  0xDC
#define CSR_RESULT_HASH_6  0xE0
#define CSR_RESULT_HASH_7  0xE4

/* CTRL register bits */
#define CTRL_START         (1u << 0)
#define CTRL_STOP          (1u << 1)
#define CTRL_DECOUPLE      (1u << 2)
#define CTRL_TRIGGER_DPR   (1u << 3)

/* STATUS register bits */
#define STATUS_BUSY        (1u << 0)
#define STATUS_FOUND       (1u << 1)
#define STATUS_DECOUPLED   (1u << 2)
#define STATUS_DPR_ACTIVE  (1u << 3)

typedef struct pdsa_csr pdsa_csr_t;

/* Open /dev/mem and map the CSR region */
pdsa_csr_t *pdsa_csr_open(void);
void        pdsa_csr_close(pdsa_csr_t *csr);

/* Write helpers */
void pdsa_csr_write32(pdsa_csr_t *csr, uint32_t offset, uint32_t val);
void pdsa_csr_write_target(pdsa_csr_t *csr, const uint32_t target[8]);
void pdsa_csr_write_midstate(pdsa_csr_t *csr, const uint32_t midstate[8]);
void pdsa_csr_write_job_data(pdsa_csr_t *csr, const uint32_t job_data[20]);

/* Read helpers */
uint32_t pdsa_csr_read32(pdsa_csr_t *csr, uint32_t offset);
uint32_t pdsa_csr_read_status(pdsa_csr_t *csr);
uint64_t pdsa_csr_read_hash_count(pdsa_csr_t *csr);
uint32_t pdsa_csr_read_golden_nonce(pdsa_csr_t *csr);
uint32_t pdsa_csr_read_hashrate(pdsa_csr_t *csr);
void     pdsa_csr_read_result_hash(pdsa_csr_t *csr, uint32_t hash[8]);

/* Control helpers */
void pdsa_csr_start(pdsa_csr_t *csr);
void pdsa_csr_stop(pdsa_csr_t *csr);
void pdsa_csr_trigger_dpr(pdsa_csr_t *csr);
void pdsa_csr_set_algo(pdsa_csr_t *csr, uint8_t algo_id);
void pdsa_csr_set_target_easy(pdsa_csr_t *csr);

/* Blocking wait for found (poll with timeout_us) */
bool pdsa_csr_wait_for_found(pdsa_csr_t *csr, int timeout_us);

#endif /* PDSA_CSR_H */
