#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <inttypes.h>

#include "pdsa_csr.h"

static void hex_to_words(const char *hex, uint32_t *words, int n_words)
{
    size_t len = strlen(hex);
    char buf[9];
    for (int i = 0; i < n_words; i++) {
        int start = (int)len - (i + 1) * 8;
        if (start < 0) { words[i] = 0; continue; }
        strncpy(buf, hex + start, 8);
        buf[8] = '\0';
        words[i] = (uint32_t)strtoul(buf, NULL, 16);
    }
}

static void print_hash(const uint32_t hash[8])
{
    for (int i = 7; i >= 0; i--)
        printf("%08X", hash[i]);
}

int main(int argc, char **argv)
{
    (void)argc; (void)argv;
    printf("=== PDSA-FPGA Miner Control ===\n\n");

    pdsa_csr_t *csr = pdsa_csr_open();
    if (!csr) {
        fprintf(stderr, "Failed to open CSR (run with sudo?)\n");
        return 1;
    }

    uint32_t st = pdsa_csr_read_status(csr);
    printf("Status: busy=%d found=%d algo_id=%d\n\n",
           (st >> 0) & 1, (st >> 1) & 1, (st >> 16) & 0xFF);

    /* --- Bitcoin mining --- */
    printf("--- Bitcoin (algo_id=0x01) ---\n");

    pdsa_csr_set_algo(csr, 0x01);

    pdsa_csr_set_target_easy(csr);

    uint32_t midstate[8] = {0};
    pdsa_csr_write_midstate(csr, midstate);

    uint32_t job_data[20];
    for (int i = 0; i < 20; i++) job_data[i] = 0xAABBCCDD + i;
    pdsa_csr_write_job_data(csr, job_data);

    pdsa_csr_write32(csr, CSR_START_NONCE, 0);

    printf("Starting Bitcoin mining...\n");
    pdsa_csr_start(csr);
    usleep(10000);

    st = pdsa_csr_read_status(csr);
    printf("  busy=%d found=%d\n", (st >> 0) & 1, (st >> 1) & 1);

    if (pdsa_csr_wait_for_found(csr, 5000000)) {
        uint32_t nonce = pdsa_csr_read_golden_nonce(csr);
        uint32_t hash[8];
        pdsa_csr_read_result_hash(csr, hash);
        uint64_t hc = pdsa_csr_read_hash_count(csr);
        printf("  FOUND! nonce=0x%08X hash=", nonce);
        print_hash(hash);
        printf(" hash_count=%" PRIu64 "\n\n", hc);
    } else {
        printf("  No result found within timeout\n\n");
    }

    pdsa_csr_stop(csr);
    usleep(1000);
    uint64_t hc = pdsa_csr_read_hash_count(csr);
    printf("  Stopped. hash_count=%" PRIu64 "\n\n", hc);

    /* --- Kaspa mining --- */
    printf("--- Kaspa (algo_id=0x02) ---\n");
    printf("Triggering DPR to swap RM...\n");

    pdsa_csr_set_algo(csr, 0x02);
    pdsa_csr_trigger_dpr(csr);
    usleep(100000);

    st = pdsa_csr_read_status(csr);
    printf("  dpr_active=%d algo_id=%d\n",
           (st >> 3) & 1, (st >> 16) & 0xFF);

    pdsa_csr_set_target_easy(csr);
    for (int i = 0; i < 20; i++) job_data[i] = 0xDEADBEEF;
    pdsa_csr_write_job_data(csr, job_data);
    pdsa_csr_write32(csr, CSR_START_NONCE, 0);

    printf("Starting Kaspa mining...\n");
    pdsa_csr_start(csr);
    usleep(10000);

    if (pdsa_csr_wait_for_found(csr, 5000000)) {
        uint32_t nonce = pdsa_csr_read_golden_nonce(csr);
        uint32_t hash[8];
        pdsa_csr_read_result_hash(csr, hash);
        uint64_t hc = pdsa_csr_read_hash_count(csr);
        printf("  FOUND! nonce=0x%08X hash=", nonce);
        print_hash(hash);
        printf(" hash_count=%" PRIu64 "\n\n", hc);
    } else {
        printf("  No result found within timeout\n\n");
    }

    pdsa_csr_stop(csr);
    pdsa_csr_close(csr);

    printf("=== Done ===\n");
    return 0;
}
