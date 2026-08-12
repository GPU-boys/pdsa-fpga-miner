#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <time.h>

#include "pdsa_csr.h"

struct pdsa_csr {
    int   fd;
    void *map;
};

pdsa_csr_t *pdsa_csr_open(void)
{
    pdsa_csr_t *csr = calloc(1, sizeof(*csr));
    if (!csr) { perror("calloc"); return NULL; }

    csr->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (csr->fd < 0) {
        perror("open /dev/mem (try: sudo)");
        free(csr);
        return NULL;
    }

    csr->map = mmap(NULL, PDSA_CSR_RANGE, PROT_READ | PROT_WRITE,
                    MAP_SHARED, csr->fd, PDSA_CSR_BASE);
    if (csr->map == MAP_FAILED) {
        perror("mmap CSR");
        close(csr->fd);
        free(csr);
        return NULL;
    }

    return csr;
}

void pdsa_csr_close(pdsa_csr_t *csr)
{
    if (!csr) return;
    munmap(csr->map, PDSA_CSR_RANGE);
    close(csr->fd);
    free(csr);
}

void pdsa_csr_write32(pdsa_csr_t *csr, uint32_t offset, uint32_t val)
{
    *(volatile uint32_t *)((uint8_t *)csr->map + offset) = val;
}

uint32_t pdsa_csr_read32(pdsa_csr_t *csr, uint32_t offset)
{
    return *(volatile uint32_t *)((uint8_t *)csr->map + offset);
}

uint32_t pdsa_csr_read_status(pdsa_csr_t *csr)
{
    return pdsa_csr_read32(csr, CSR_STATUS);
}

uint64_t pdsa_csr_read_hash_count(pdsa_csr_t *csr)
{
    uint32_t lo = pdsa_csr_read32(csr, CSR_HASH_COUNT_LO);
    uint32_t hi = pdsa_csr_read32(csr, CSR_HASH_COUNT_HI);
    return ((uint64_t)hi << 32) | lo;
}

uint32_t pdsa_csr_read_golden_nonce(pdsa_csr_t *csr)
{
    return pdsa_csr_read32(csr, CSR_GOLDEN_NONCE);
}

uint32_t pdsa_csr_read_hashrate(pdsa_csr_t *csr)
{
    static uint64_t last_count = 0;
    static struct timespec last_ts = {0};

    uint64_t current = pdsa_csr_read_hash_count(csr);
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    if (last_ts.tv_sec == 0) {
        last_count = current;
        last_ts = now;
        return 0;
    }

    uint64_t dt_ns = (now.tv_sec - last_ts.tv_sec) * 1000000000ULL +
                     (now.tv_nsec - last_ts.tv_nsec);
    if (dt_ns < 500000000) // less than 500ms, keep accumulating
        return 0;

    if (current < last_count) {
        last_count = current;
        last_ts = now;
        return 0;
    }

    uint64_t rate = ((current - last_count) * 1000000000ULL) / dt_ns;
    last_count = current;
    last_ts = now;
    return (uint32_t)rate;
}

void pdsa_csr_read_result_hash(pdsa_csr_t *csr, uint32_t hash[8])
{
    for (int i = 0; i < 8; i++)
        hash[i] = pdsa_csr_read32(csr, CSR_RESULT_HASH_0 + i * 4);
}

void pdsa_csr_write_target(pdsa_csr_t *csr, const uint32_t target[8])
{
    for (int i = 0; i < 8; i++)
        pdsa_csr_write32(csr, CSR_TARGET_0 + i * 4, target[i]);
}

void pdsa_csr_write_midstate(pdsa_csr_t *csr, const uint32_t midstate[8])
{
    for (int i = 0; i < 8; i++)
        pdsa_csr_write32(csr, CSR_MIDSTATE_0 + i * 4, midstate[i]);
}

void pdsa_csr_write_job_data(pdsa_csr_t *csr, const uint32_t job_data[20])
{
    for (int i = 0; i < 20; i++)
        pdsa_csr_write32(csr, CSR_JOB_DATA_0 + i * 4, job_data[i]);
}

void pdsa_csr_start(pdsa_csr_t *csr)
{
    pdsa_csr_write32(csr, CSR_CTRL, CTRL_START);
}

void pdsa_csr_stop(pdsa_csr_t *csr)
{
    pdsa_csr_write32(csr, CSR_CTRL, CTRL_STOP);
}

void pdsa_csr_trigger_dpr(pdsa_csr_t *csr)
{
    pdsa_csr_write32(csr, CSR_CTRL, CTRL_TRIGGER_DPR);
}

void pdsa_csr_set_algo(pdsa_csr_t *csr, uint8_t algo_id)
{
    pdsa_csr_write32(csr, CSR_ALGO_SEL, algo_id);
}

void pdsa_csr_set_target_easy(pdsa_csr_t *csr)
{
    uint32_t easy[8] = {
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF,
        0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF, 0xFFFFFFFF
    };
    pdsa_csr_write_target(csr, easy);
}

bool pdsa_csr_wait_for_found(pdsa_csr_t *csr, int timeout_us)
{
    int waited = 0;
    while (waited < timeout_us) {
        uint32_t st = pdsa_csr_read_status(csr);
        if (st & STATUS_FOUND)
            return true;
        usleep(10);
        waited += 10;
    }
    return false;
}
