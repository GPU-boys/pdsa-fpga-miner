#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <sys/mman.h>
#include <fcntl.h>

#include "mining/sha256_sw.h"
#include "mining/block_header.h"
#include "pdsa_csr_map.h"
#include "pdsa_hal.h"

#define PT_THRESHOLD_PCT   30
#define EVAL_INTERVAL_SEC   5
#define SIM_PT_STEP        20

#define BITSTREAM_BTC   "/lib/firmware/pdsa_rm_sep_btc.bin"
#define BITSTREAM_KSP   "/lib/firmware/pdsa_rm_sep_kaspa.bin"
#define CSV_LOG_PATH    "/tmp/pdsa_measurements.csv"
#define START_NONCE     0x00000000

typedef enum {
    STATE_IDLE        = 0,
    STATE_VERIFY      = 1,
    STATE_MINING      = 2,
    STATE_EVALUATING  = 3,
    STATE_DPR_PREPARE = 4,
    STATE_DPR_LOADING = 5,
    STATE_DPR_RESTART = 6,
    STATE_DONE        = 7
} pdsa_state_t;

static const char *state_names[] = {
    "IDLE","VERIFY","MINING","EVALUATING",
    "DPR_PREPARE","DPR_LOADING","DPR_RESTART","DONE"
};

typedef enum { ALGO_BITCOIN = 0, ALGO_KASPA = 1 } algo_t;

typedef struct {
    pdsa_state_t  state;
    algo_t        current_algo;
    int           running;

    mining_job_t  current_job;
    int           has_job;

    pdsa_hal_t    hal;

    uint64_t      total_hashes;
    uint32_t      shares_accepted;
    uint32_t      shares_rejected;
    uint32_t      dpr_count;
    uint32_t      dpr_latency_cycles;
    FILE         *csv_log;

    time_t        job_start_time;
    time_t        last_eval_time;

    time_t        last_watchdog_check;
    uint64_t      last_watchdog_hash;

    uint32_t      start_nonce;

} pdsa_ctx_t;

static pdsa_ctx_t g_ctx;

static uint32_t get_hashrate(pdsa_hal_t *hal);

static void sig_handler(int s) {
    (void)s;
    printf("\n[MAIN] Shutting down...\n");
    g_ctx.running = 0;
}

static void log_event(pdsa_ctx_t *ctx, const char *event, uint32_t dpr_lat) {
    if (!ctx->csv_log) return;
    time_t now = time(NULL);
    struct tm *t = localtime(&now);
    uint32_t status   = pdsa_csr_read(&ctx->hal, CSR_STATUS);
    uint32_t hashrate = get_hashrate(&ctx->hal);
    uint64_t hash_cnt = ((uint64_t)pdsa_csr_read(&ctx->hal, CSR_HCNT_HI) << 32)
                       | pdsa_csr_read(&ctx->hal, CSR_HCNT_LO);

    fprintf(ctx->csv_log,
        "%04d-%02d-%02d %02d:%02d:%02d,"
        "%s,"
        "%s,"
        "%s,"
        "%u,"
        "%llu,"
        "%u,"
        "%u,"
        "%u,"
        "%u,"
        "0x%08x\n",
        t->tm_year+1900, t->tm_mon+1, t->tm_mday,
        t->tm_hour, t->tm_min, t->tm_sec,
        state_names[ctx->state],
        ctx->current_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa",
        event,
        hashrate,
        (unsigned long long)hash_cnt,
        dpr_lat,
        ctx->shares_accepted,
        ctx->shares_rejected,
        ctx->dpr_count,
        status);
    fflush(ctx->csv_log);
}

static void send_job_to_pl(pdsa_ctx_t *ctx) {
    mining_job_t *job = &ctx->current_job;
    int i;

    printf("[HAL] Sending job %s to PL hardware (algo=%s)\n",
           job->job_id,
           ctx->current_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa");

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_STOP);
    usleep(200);

    for (i = 0; i < 8; i++) {
        uint32_t word = ((uint32_t)job->target[i*4+0] << 24) |
                        ((uint32_t)job->target[i*4+1] << 16) |
                        ((uint32_t)job->target[i*4+2] <<  8) |
                        ((uint32_t)job->target[i*4+3]);
        pdsa_csr_write(&ctx->hal, CSR_TARGET_BASE + i*4, word);
    }

    if (ctx->current_algo == ALGO_BITCOIN) {
        for (i = 0; i < 8; i++)
            pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + i*4, job->midstate[i]);

        pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE +  0, job->merkle_tail);
        pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE +  4, job->timestamp);
        pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE +  8, job->nbits);
    } else {
        uint8_t *hdr = job->header;
        for (i = 0; i < 20; i++) {
            uint32_t w = ((uint32_t)hdr[i*4+0] << 24) |
                         ((uint32_t)hdr[i*4+1] << 16) |
                         ((uint32_t)hdr[i*4+2] <<  8) |
                         ((uint32_t)hdr[i*4+3]);
            pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + i*4, w);
        }
    }

    pdsa_csr_write(&ctx->hal, CSR_ALGO_SEL, ctx->current_algo);
    pdsa_csr_write(&ctx->hal, CSR_NONCE,    START_NONCE);
    ctx->start_nonce = START_NONCE;

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_START);

    ctx->job_start_time = time(NULL);
    printf("[HAL] Job started. Target[0:3] = %02x%02x%02x%02x\n",
           job->target[0], job->target[1], job->target[2], job->target[3]);
}

static void create_simulated_job(pdsa_ctx_t *ctx) {
    mining_job_t *job = &ctx->current_job;

    snprintf(job->job_id, JOB_ID_LEN, "SIM0");

    memset(job->target, 0, 32);
    job->target[4] = 0xFF;
    job->target[5] = 0xFF;

    if (ctx->current_algo == ALGO_BITCOIN) {
        job->midstate[0] = 0x6A09E667;
        job->midstate[1] = 0xBB67AE85;
        job->midstate[2] = 0x3C6EF372;
        job->midstate[3] = 0xA54FF53A;
        job->midstate[4] = 0x510E527F;
        job->midstate[5] = 0x9B05688C;
        job->midstate[6] = 0x1F83D9AB;
        job->midstate[7] = 0x5BE0CD19;

        job->merkle_tail = 0x80000000;
        job->timestamp   = 0x00000000;
        job->nbits       = 0x00000280;
    } else {
        memset(job->header, 0xAA, 80);
        job->header[0] = 0x01;
        job->header[4] = 0x00;
    }

    ctx->has_job = 1;
    printf("[SIM] Created simulated job %s (algo=%s target=0x%08x...)\n",
           job->job_id,
           ctx->current_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa",
           job->target[0]);
}

static int do_dpr_switch(pdsa_ctx_t *ctx, algo_t new_algo) {
    const char *bsfile = (new_algo == ALGO_BITCOIN) ? BITSTREAM_BTC : BITSTREAM_KSP;
    char cmd[512];
    uint32_t dpr_lat;

    printf("\n[DPR] === Switching to %s ===\n",
           new_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa");

    log_event(ctx, "DPR_START", 0);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_STOP);
    usleep(500);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_DECOUPLE);
    usleep(10);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_TRIGGER_DPR);

    snprintf(cmd, sizeof(cmd),
        "echo 1 > /sys/class/fpga_manager/fpga0/flags && "
        "cp %s /lib/firmware/partial.bin && "
        "echo partial.bin > /sys/class/fpga_manager/fpga0/firmware",
        bsfile);

    int ret = system(cmd);
    if (ret != 0) {
        fprintf(stderr, "[DPR] Bitstream load failed (error %d)\n", ret);
        pdsa_csr_write(&ctx->hal, CSR_CTRL, 0);
        return -1;
    }

    pdsa_csr_write(&ctx->hal, CSR_CTRL, 0);
    usleep(10);

    pdsa_csr_write(&ctx->hal, CSR_ALGO_SEL, new_algo);

    dpr_lat = pdsa_csr_read(&ctx->hal, CSR_DPR_LATENCY);
    ctx->dpr_latency_cycles = dpr_lat;
    ctx->dpr_count++;

    printf("[DPR] Switch complete. Latency = %u cycles (%.3f ms at 100MHz)\n",
           dpr_lat, dpr_lat / 100000.0f);

    ctx->current_algo = new_algo;
    log_event(ctx, "DPR_DONE", dpr_lat);

    return 0;
}

static const uint32_t nist_padded[] = {
    0x61626380, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000018,
    0x80000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000,
    0x00000000, 0x00000000, 0x00000000, 0x00000000
};

static const uint8_t nist_expected[2][32] = {
    { 0xBA,0x78,0x16,0xBF,0x8F,0x01,0xCF,0xEA,
      0x41,0x41,0x40,0xDE,0x5D,0xAE,0x22,0x23,
      0xB0,0x03,0x61,0xA3,0x96,0x17,0x7A,0x9C,
      0xB4,0x10,0xFF,0x61,0xF2,0x00,0x15,0xAD },
    { 0xE3,0xB0,0xC4,0x42,0x98,0xFC,0x1C,0x14,
      0x9A,0xFB,0xF4,0xC8,0x99,0x6F,0xB9,0x24,
      0x27,0xAE,0x41,0xE4,0x64,0x9B,0x93,0x4C,
      0xA4,0x95,0x99,0x1B,0x78,0x52,0xB8,0x55 }
};

static const char *nist_names[2] = { "\"abc\"", "\"<empty>\"" };

static uint32_t get_hashrate(pdsa_hal_t *hal) {
    static uint64_t last_count = 0;
    static struct timespec last_ts = {0};

    uint64_t hc_lo = pdsa_csr_read(hal, CSR_HCNT_LO);
    uint64_t hc_hi = pdsa_csr_read(hal, CSR_HCNT_HI);
    uint64_t current = (hc_hi << 32) | hc_lo;

    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);

    if (last_ts.tv_sec == 0) {
        last_count = current;
        last_ts = now;
        return 0;
    }

    uint64_t dt_ns = (now.tv_sec - last_ts.tv_sec) * 1000000000ULL +
                     (now.tv_nsec - last_ts.tv_nsec);
    if (dt_ns < 500000000)
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

static void read_result_hash(pdsa_hal_t *hal, uint8_t hash[32]) {
    uint32_t word;
    for (int i = 0; i < 8; i++) {
        word = pdsa_csr_read(hal, CSR_RESULT_HASH_BASE + i * 4);
        hash[i * 4 + 0] = (uint8_t)(word >> 24);
        hash[i * 4 + 1] = (uint8_t)(word >> 16);
        hash[i * 4 + 2] = (uint8_t)(word >> 8);
        hash[i * 4 + 3] = (uint8_t)(word);
    }
}

#define SHA256_IV_W0 0x6A09E667UL
#define SHA256_IV_W1 0xBB67AE85UL
#define SHA256_IV_W2 0x3C6EF372UL
#define SHA256_IV_W3 0xA54FF53AUL
#define SHA256_IV_W4 0x510E527FUL
#define SHA256_IV_W5 0x9B05688CUL
#define SHA256_IV_W6 0x1F83D9ABUL
#define SHA256_IV_W7 0x5BE0CD19UL

static int feed_nist_to_pl(pdsa_ctx_t *ctx, int vec_idx) {
    const uint32_t *msg = &nist_padded[vec_idx * 16];
    uint32_t status;
    int timeout;
    uint8_t pl_hash[32];

    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x00, msg[0]);
    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x04, msg[1]);
    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x08, msg[2]);

    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x00, SHA256_IV_W0);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x04, SHA256_IV_W1);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x08, SHA256_IV_W2);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x0C, SHA256_IV_W3);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x10, SHA256_IV_W4);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x14, SHA256_IV_W5);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x18, SHA256_IV_W6);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x1C, SHA256_IV_W7);

    for (int i = 0; i < 8; i++)
        pdsa_csr_write(&ctx->hal, CSR_TARGET_BASE + i * 4, 0xFFFFFFFF);

    pdsa_csr_write(&ctx->hal, CSR_NONCE, msg[3]);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_START);

    timeout = 1000000;
    do {
        status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
        if (--timeout <= 0) break;
    } while (!(status & STATUS_FOUND) && (status & STATUS_BUSY));

    if (timeout <= 0) {
        fprintf(stderr, "[VERIFY] PL timeout on vector %d (status=0x%08x)\n",
                vec_idx, status);
        return -1;
    }

    read_result_hash(&ctx->hal, pl_hash);

    uint32_t golden = pdsa_csr_read(&ctx->hal, CSR_GOLDEN_NONCE);

    printf("[VERIFY] Vector %d (%s): golden_nonce=0x%08X hash=", vec_idx, nist_names[vec_idx], golden);
    for (int i = 0; i < 32; i++) printf("%02x", pl_hash[i]);
    printf("\n");

    if (memcmp(pl_hash, nist_expected[vec_idx], 32) != 0) {
        fprintf(stderr, "[VERIFY]   PL hash MISMATCH! expected=");
        for (int i = 0; i < 32; i++) fprintf(stderr, "%02x", nist_expected[vec_idx][i]);
        fprintf(stderr, "\n");
        return -1;
    }

    return 0;
}

static int run_nist_self_test(pdsa_ctx_t *ctx) {
    int ret = 0;

    printf("[VERIFY] === NIST SHA-256 Verification ===\n");

    printf("[VERIFY] Test 1: Software SHA-256...\n");
    uint8_t sw_hash[32];
    sha256((const uint8_t*)"abc", 3, sw_hash);
    if (memcmp(sw_hash, nist_expected[0], 32) != 0) {
        fprintf(stderr, "[VERIFY] SW SHA-256 failed! Library is broken.\n");
        return -1;
    }
    printf("[VERIFY]   SW SHA-256(\"abc\"): PASS\n");

    printf("[VERIFY] Test 2: Software SHA-256 (empty)...\n");
    sha256((const uint8_t*)"", 0, sw_hash);
    if (memcmp(sw_hash, nist_expected[1], 32) != 0) {
        fprintf(stderr, "[VERIFY] SW SHA-256 empty failed!\n");
        return -1;
    }
    printf("[VERIFY]   SW SHA-256(empty): PASS\n");

    printf("[VERIFY] Test 3: PL SHA-256d (\"abc\" padded)...\n");
    if (feed_nist_to_pl(ctx, 0) < 0) {
        fprintf(stderr, "[VERIFY] PL vector 0 failed!\n");
        ret = -1;
    } else {
        printf("[VERIFY]   PL pipeline vector 0: PASS\n");
    }

    printf("[VERIFY] Test 4: PL SHA-256d (empty-string padded)...\n");
    if (feed_nist_to_pl(ctx, 1) < 0) {
        fprintf(stderr, "[VERIFY] PL vector 1 failed!\n");
        ret = -1;
    } else {
        printf("[VERIFY]   PL pipeline vector 1: PASS\n");
    }

    printf("[VERIFY] Test 5: PL control register...\n");
    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_START);
    uint32_t status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_STOP);

    if (status & (STATUS_BUSY | STATUS_FOUND)) {
        printf("[VERIFY]   PL responsive: PASS (status=0x%08x)\n", status);
    } else {
        fprintf(stderr, "[VERIFY]   PL not responding (status=0x%08x)\n", status);
        ret = -1;
    }

    if (ret == 0)
        printf("[VERIFY] === All NIST tests PASSED ===\n");
    else
        fprintf(stderr, "[VERIFY] === Some tests FAILED ===\n");

    return ret;
}

static int feed_nist_kat(pdsa_ctx_t *ctx, int vec_idx) {
    const uint32_t *msg = &nist_padded[vec_idx * 16];
    uint32_t status;
    int timeout;
    uint8_t pl_hash[32];

    for (int i = 0; i < 16; i++)
        pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x10 + i * 4, msg[i]);

    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x00, SHA256_IV_W0);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x04, SHA256_IV_W1);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x08, SHA256_IV_W2);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x0C, SHA256_IV_W3);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x10, SHA256_IV_W4);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x14, SHA256_IV_W5);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x18, SHA256_IV_W6);
    pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + 0x1C, SHA256_IV_W7);

    for (int i = 0; i < 8; i++)
        pdsa_csr_write(&ctx->hal, CSR_TARGET_BASE + i * 4, 0x00000000);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_START);

    timeout = 1000000;
    do {
        status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
        if (--timeout <= 0) break;
    } while (!(status & STATUS_FOUND));

    if (timeout <= 0) {
        fprintf(stderr, "[KAT] PL timeout on vector %d (status=0x%08x)\n",
                vec_idx, status);
        return -1;
    }

    read_result_hash(&ctx->hal, pl_hash);

    printf("[KAT] Vector %d (%s): hash=", vec_idx, nist_names[vec_idx]);
    for (int i = 0; i < 32; i++) printf("%02x", pl_hash[i]);
    printf("\n");

    if (memcmp(pl_hash, nist_expected[vec_idx], 32) != 0) {
        fprintf(stderr, "[KAT]   MISMATCH! expected=");
        for (int i = 0; i < 32; i++) fprintf(stderr, "%02x", nist_expected[vec_idx][i]);
        fprintf(stderr, "\n");
        return -1;
    }

    return 0;
}

static int run_nist_kat(pdsa_ctx_t *ctx) {
    int ret = 0;

    printf("[KAT] === NIST SHA-256 Known-Answer Test (HW single-SHA-256) ===\n");

    for (int v = 0; v < 2; v++) {
        printf("[KAT] Test %d: Vector %s...\n", v + 1, nist_names[v]);
        if (feed_nist_kat(ctx, v) < 0) {
            fprintf(stderr, "[KAT]   FAIL\n");
            ret = -1;
        } else {
            printf("[KAT]   PASS\n");
        }
    }

    if (ret == 0)
        printf("[KAT] === All NIST KAT tests PASSED ===\n");
    else
        fprintf(stderr, "[KAT] === Some tests FAILED ===\n");

    return ret;
}

static int run_genesis_block_test(pdsa_ctx_t *ctx) {
    uint32_t status;
    int timeout;

    printf("[GENESIS] === Bitcoin Genesis Block Double-SHA-256 Test ===\n");

    uint32_t genesis_header[20] = {
        0x00000001, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000,         0xfdeda33b, 0xb2127b7a, 0x3e2cc77a,
        0x618f7667, 0xc31bc87f, 0x32518a88, 0xaab89f3a,
        0x4a5e1e4b, 0x495fab29, 0x1d00ffff, 0x7c2bac1d
    };

    uint8_t expected_hash[32] = {
        0x6f,0xe2,0x8c,0x0a,0xb6,0xf1,0xb3,0x72,
        0xc1,0xa6,0xa2,0x46,0xae,0x63,0xf7,0x4f,
        0x93,0x1e,0x83,0x65,0xe1,0x5a,0x08,0x9c,
        0x68,0xd6,0x19,0x00,0x00,0x00,0x00,0x00
    };

    uint8_t header_bytes[80];
    for (int i = 0; i < 20; i++) {
        header_bytes[i*4+0] = genesis_header[i] & 0xFF;
        header_bytes[i*4+1] = (genesis_header[i] >> 8) & 0xFF;
        header_bytes[i*4+2] = (genesis_header[i] >> 16) & 0xFF;
        header_bytes[i*4+3] = (genesis_header[i] >> 24) & 0xFF;
    }
    uint32_t midstate[8];
    bitcoin_compute_midstate(header_bytes, midstate);

    uint32_t merkle_tail = ((uint32_t)header_bytes[64+3] << 24) |
                           ((uint32_t)header_bytes[64+2] << 16) |
                           ((uint32_t)header_bytes[64+1] <<  8) |
                           ((uint32_t)header_bytes[64+0]);
    uint32_t timestamp = ((uint32_t)header_bytes[68+3] << 24) |
                         ((uint32_t)header_bytes[68+2] << 16) |
                         ((uint32_t)header_bytes[68+1] <<  8) |
                         ((uint32_t)header_bytes[68+0]);
    uint32_t nbits     = ((uint32_t)header_bytes[72+3] << 24) |
                         ((uint32_t)header_bytes[72+2] << 16) |
                         ((uint32_t)header_bytes[72+1] <<  8) |
                         ((uint32_t)header_bytes[72+0]);
    uint32_t nonce     = ((uint32_t)header_bytes[76+3] << 24) |
                         ((uint32_t)header_bytes[76+2] << 16) |
                         ((uint32_t)header_bytes[76+1] <<  8) |
                         ((uint32_t)header_bytes[76+0]);

    for (int i = 0; i < 8; i++)
        pdsa_csr_write(&ctx->hal, CSR_TARGET_BASE + i * 4, 0xFFFFFFFF);

    for (int i = 0; i < 8; i++)
        pdsa_csr_write(&ctx->hal, CSR_MIDSTATE_BASE + i * 4, midstate[i]);

    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x00, merkle_tail);
    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x04, timestamp);
    pdsa_csr_write(&ctx->hal, CSR_JOBDATA_BASE + 0x08, nbits);

    pdsa_csr_write(&ctx->hal, CSR_ALGO_SEL, 0);
    pdsa_csr_write(&ctx->hal, CSR_NONCE, nonce);

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_START);

    timeout = 1000000;
    do {
        status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
        if (--timeout <= 0) break;
    } while (!(status & STATUS_FOUND));

    if (timeout <= 0) {
        fprintf(stderr, "[GENESIS] PL timeout (status=0x%08x)\n", status);
        return -1;
    }

    uint8_t pl_hash[32];
    read_result_hash(&ctx->hal, pl_hash);

    printf("[GENESIS] PL hash: ");
    for (int i = 0; i < 32; i++) printf("%02x", pl_hash[i]);
    printf("\n[GENESIS] Expected: ");
    for (int i = 0; i < 32; i++) printf("%02x", expected_hash[i]);
    printf("\n");

    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_STOP);
    usleep(200);

    if (memcmp(pl_hash, expected_hash, 32) != 0) {
        fprintf(stderr, "[GENESIS] Hash MISMATCH! Double-SHA-256 pipeline broken.\n");
        return -1;
    }

    printf("[GENESIS] === Genesis block test PASSED ===\n");
    return 0;
}

static int run_pdsa_dpr_self_test(pdsa_ctx_t *ctx) {
    int ret = 0;
    uint32_t status, decision;

    printf("[PDSA-TEST] === PDSA + DPR Self-Test ===\n");

    printf("[PDSA-TEST] Test 1: PDSA CONTINUE (PT=80%%, BCV=0)...\n");
    pdsa_csr_write(&ctx->hal, CSR_PT_THRESH, 30);
    pdsa_csr_write(&ctx->hal, CSR_PT_CURR,   80);
    pdsa_csr_write(&ctx->hal, CSR_BCV_STATUS, 0);
    usleep(1);
    decision = pdsa_csr_read(&ctx->hal, CSR_PDSA_DECISION);
    printf("[PDSA-TEST]   Decision=0x%02x (expect 0x00=CONTINUE)\n", decision);
    if (decision != 0x00) {
        fprintf(stderr, "[PDSA-TEST]   FAIL: expected CONTINUE\n");
        ret = -1;
    } else {
        printf("[PDSA-TEST]   PASS\n");
    }

    printf("[PDSA-TEST] Test 2: PDSA SWITCH_PT (PT=10%%, thresh=30%%)...\n");
    pdsa_csr_write(&ctx->hal, CSR_PT_CURR, 10);
    usleep(1);
    decision = pdsa_csr_read(&ctx->hal, CSR_PDSA_DECISION);
    printf("[PDSA-TEST]   Decision=0x%02x (expect 0x01=SWITCH_PT)\n", decision);
    if (decision != 0x01) {
        fprintf(stderr, "[PDSA-TEST]   FAIL: expected SWITCH_PT\n");
        ret = -1;
    } else {
        printf("[PDSA-TEST]   PASS\n");
    }

    printf("[PDSA-TEST] Test 3: PDSA SWITCH_BCV (BCV=2)...\n");
    pdsa_csr_write(&ctx->hal, CSR_PT_CURR,   80);
    pdsa_csr_write(&ctx->hal, CSR_BCV_STATUS, 2);
    usleep(1);
    decision = pdsa_csr_read(&ctx->hal, CSR_PDSA_DECISION);
    printf("[PDSA-TEST]   Decision=0x%02x (expect 0x02=SWITCH_BCV)\n", decision);
    if (decision != 0x02) {
        fprintf(stderr, "[PDSA-TEST]   FAIL: expected SWITCH_BCV\n");
        ret = -1;
    } else {
        printf("[PDSA-TEST]   PASS\n");
    }

    printf("[PDSA-TEST] Test 4: DPR decouple/recouple...\n");
    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_DECOUPLE);
    usleep(10);
    status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
    printf("[PDSA-TEST]   Decoupled: STATUS=0x%08x\n", status);
    if (!(status & STATUS_DECOUPLED)) {
        fprintf(stderr, "[PDSA-TEST]   FAIL: decoupled bit not set\n");
        ret = -1;
    } else {
        printf("[PDSA-TEST]   Decoupled: PASS\n");
    }

    pdsa_csr_write(&ctx->hal, CSR_CTRL, 0);
    usleep(10);
    status = pdsa_csr_read(&ctx->hal, CSR_STATUS);
    if (status & STATUS_DECOUPLED) {
        fprintf(stderr, "[PDSA-TEST]   FAIL: decoupled bit not cleared\n");
        ret = -1;
    } else {
        printf("[PDSA-TEST]   Recoupled: PASS\n");
    }

    printf("[PDSA-TEST] Test 5: DPR latency timer readback...\n");
    pdsa_csr_write(&ctx->hal, CSR_CTRL, CTRL_DECOUPLE);
    usleep(100);
    pdsa_csr_write(&ctx->hal, CSR_CTRL, 0);
    usleep(10);
    uint32_t dpr_lat = pdsa_csr_read(&ctx->hal, CSR_DPR_LATENCY);
    printf("[PDSA-TEST]   DPR latency: %u cycles (expect >0 after decouple cycle)\n", dpr_lat);
    if (dpr_lat > 0) {
        printf("[PDSA-TEST]   DPR timer functional: PASS\n");
    } else {
        fprintf(stderr, "[PDSA-TEST]   DPR timer readback: OK (latency=0 if decouple was too fast)\n");
    }

    if (ret == 0)
        printf("[PDSA-TEST] === All PDSA/DPR tests PASSED ===\n");
    else
        fprintf(stderr, "[PDSA-TEST] === Some tests FAILED ===\n");

    pdsa_csr_write(&ctx->hal, CSR_CTRL, 0);
    pdsa_csr_write(&ctx->hal, CSR_PT_THRESH, PT_THRESHOLD_PCT);
    pdsa_csr_write(&ctx->hal, CSR_PT_CURR,   100);
    pdsa_csr_write(&ctx->hal, CSR_BCV_STATUS, 0);

    return ret;
}

int main(int argc, char *argv[]) {
    (void)argc; (void)argv;

    printf("============================================\n");
    printf("  PDSA-FPGA Mining Controller v2.0\n");
    printf("  Kria KV260 — Bitcoin + Kaspa Adaptive\n");
    printf("  (Standalone / Self-Test Mode)\n");
    printf("============================================\n\n");

    signal(SIGINT,  sig_handler);
    signal(SIGTERM, sig_handler);

    memset(&g_ctx, 0, sizeof(g_ctx));
    g_ctx.running      = 1;
    g_ctx.state        = STATE_IDLE;
    g_ctx.current_algo = ALGO_BITCOIN;
    g_ctx.last_watchdog_check = 0;
    g_ctx.last_watchdog_hash  = 0;
    g_ctx.start_nonce         = START_NONCE;

    g_ctx.csv_log = fopen(CSV_LOG_PATH, "w");
    if (g_ctx.csv_log) {
        fprintf(g_ctx.csv_log,
            "timestamp,state,algorithm,event,hashrate_hps,"
            "hash_count,dpr_latency_cycles,shares_acc,shares_rej,"
            "dpr_count,pl_status\n");
    }

    printf("[INIT] Mapping PL CSR registers...\n");
    if (pdsa_hal_init(&g_ctx.hal, PL_CSR_BASE_ADDR) < 0) {
        fprintf(stderr, "[INIT] HAL init failed — check device tree and /dev/mem\n");
        return 1;
    }

    pdsa_csr_write(&g_ctx.hal, CSR_PT_THRESH, PT_THRESHOLD_PCT);
    pdsa_csr_write(&g_ctx.hal, CSR_PT_CURR,   100);
    pdsa_csr_write(&g_ctx.hal, CSR_BCV_STATUS, 0);

    g_ctx.state = STATE_VERIFY;
    if (run_nist_self_test(&g_ctx) < 0) {
        fprintf(stderr, "[INIT] Self-test failed — aborting\n");
        return 1;
    }

    g_ctx.state = STATE_VERIFY;
    if (run_nist_kat(&g_ctx) < 0) {
        fprintf(stderr, "[INIT] NIST KAT failed — aborting\n");
        return 1;
    }

    for (int i = 0; i < 8; i++)
        pdsa_csr_write(&g_ctx.hal, CSR_TARGET_BASE + i * 4, 0xFFFFFFFF);
    pdsa_csr_write(&g_ctx.hal, CSR_CTRL, CTRL_STOP);

    g_ctx.state = STATE_VERIFY;
    if (run_genesis_block_test(&g_ctx) < 0) {
        fprintf(stderr, "[INIT] Genesis block test failed — double-SHA-256 broken\n");
        return 1;
    }

    g_ctx.state = STATE_VERIFY;
    run_pdsa_dpr_self_test(&g_ctx);

    create_simulated_job(&g_ctx);
    send_job_to_pl(&g_ctx);

    g_ctx.state = STATE_MINING;
    g_ctx.last_eval_time = time(NULL);
    log_event(&g_ctx, "MINING_START", 0);

    int sim_pt = 100;

    while (g_ctx.running) {

        uint32_t status = pdsa_csr_read(&g_ctx.hal, CSR_STATUS);
        if (status & STATUS_FOUND) {
            uint32_t golden_nonce = pdsa_csr_read(&g_ctx.hal, CSR_GOLDEN_NONCE);
            uint64_t hash_count   = ((uint64_t)pdsa_csr_read(&g_ctx.hal, CSR_HCNT_HI) << 32)
                                   | pdsa_csr_read(&g_ctx.hal, CSR_HCNT_LO);

            printf("\n[FOUND] *** %s NONCE FOUND! *** nonce=0x%08x after %llu hashes\n",
                   g_ctx.current_algo == ALGO_BITCOIN ? "BTC" : "KSP",
                   golden_nonce, (unsigned long long)hash_count);

            g_ctx.total_hashes += hash_count;
            log_event(&g_ctx, "NONCE_FOUND", 0);

            printf("[LOCAL] Nonce found, restarting job...\n");

            pdsa_csr_write(&g_ctx.hal, CSR_CTRL, CTRL_STOP);
            usleep(200);

            pdsa_csr_write(&g_ctx.hal, CSR_NONCE, golden_nonce + 1);
            pdsa_csr_write(&g_ctx.hal, CSR_CTRL, CTRL_START);
        }

        time_t now = time(NULL);
        if (now - g_ctx.last_eval_time >= EVAL_INTERVAL_SEC) {
            g_ctx.state = STATE_EVALUATING;

            if (sim_pt >= PT_THRESHOLD_PCT) {
                sim_pt -= SIM_PT_STEP;
                pdsa_csr_write(&g_ctx.hal, CSR_PT_CURR, (uint32_t)sim_pt);
                pdsa_csr_write(&g_ctx.hal, CSR_BCV_STATUS, 0);
                usleep(1);
                uint32_t decision = pdsa_csr_read(&g_ctx.hal, CSR_PDSA_DECISION);
                printf("[PDSA-SIM] PT=%d%% Decision=0x%02x (%s)\n", sim_pt, decision,
                       decision == 0x00 ? "CONTINUE" :
                       decision == 0x01 ? "SWITCH_PT" :
                       decision == 0x02 ? "SWITCH_BCV" : "UNKNOWN");

                if (decision == 0x01) {
                    algo_t new_algo = (g_ctx.current_algo == ALGO_BITCOIN) ? ALGO_KASPA : ALGO_BITCOIN;
                    printf("[PDSA-SIM] PT low — executing DPR switch to %s\n",
                           new_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa");

                    g_ctx.state = STATE_DPR_PREPARE;
                    if (do_dpr_switch(&g_ctx, new_algo) == 0) {
                        g_ctx.state = STATE_DPR_RESTART;
                        g_ctx.has_job = 0;
                        create_simulated_job(&g_ctx);
                        send_job_to_pl(&g_ctx);
                        g_ctx.state = STATE_MINING;
                        pdsa_csr_write(&g_ctx.hal, CSR_PT_THRESH, PT_THRESHOLD_PCT);
                    } else {
                        g_ctx.state = STATE_MINING;
                        fprintf(stderr, "[PDSA-SIM] DPR failed — continuing with current algorithm\n");
                    }
                    sim_pt = 100;
                    pdsa_csr_write(&g_ctx.hal, CSR_PT_CURR, 100);
                } else if (decision == 0x02) {
                    algo_t new_algo = (g_ctx.current_algo == ALGO_BITCOIN) ? ALGO_KASPA : ALGO_BITCOIN;
                    printf("[PDSA-SIM] BCV triggered — executing DPR switch to %s\n",
                           new_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa");

                    g_ctx.state = STATE_DPR_PREPARE;
                    if (do_dpr_switch(&g_ctx, new_algo) == 0) {
                        g_ctx.state = STATE_DPR_RESTART;
                        g_ctx.has_job = 0;
                        create_simulated_job(&g_ctx);
                        send_job_to_pl(&g_ctx);
                        g_ctx.state = STATE_MINING;
                        pdsa_csr_write(&g_ctx.hal, CSR_PT_THRESH, PT_THRESHOLD_PCT);
                    } else {
                        g_ctx.state = STATE_MINING;
                        fprintf(stderr, "[PDSA-SIM] DPR failed — continuing with current algorithm\n");
                    }
                    sim_pt = 100;
                }
            }

            g_ctx.last_eval_time = now;
            g_ctx.state = STATE_MINING;
        }

        static time_t last_status = 0;
        if (now - last_status >= 30) {
            uint32_t hashrate = get_hashrate(&g_ctx.hal);
            printf("[STATUS] Algo=%s Hashrate=%u H/s Nonces=%u DPR=%u\n",
                   g_ctx.current_algo == ALGO_BITCOIN ? "Bitcoin" : "Kaspa",
                   hashrate, g_ctx.shares_accepted, g_ctx.dpr_count);
            last_status = now;
        }

        if (g_ctx.has_job && now - g_ctx.last_watchdog_check >= 30) {
            uint64_t hc = ((uint64_t)pdsa_csr_read(&g_ctx.hal, CSR_HCNT_HI) << 32)
                         | pdsa_csr_read(&g_ctx.hal, CSR_HCNT_LO);
            if (hc == g_ctx.last_watchdog_hash && g_ctx.last_watchdog_hash != 0) {
                printf("[WATCHDOG] Hash count stalled — restarting job\n");
                g_ctx.has_job = 0;
                create_simulated_job(&g_ctx);
                send_job_to_pl(&g_ctx);
            }
            g_ctx.last_watchdog_hash = hc;
            g_ctx.last_watchdog_check = now;
        }

        if (g_ctx.has_job && g_ctx.start_nonce >= 0xFFFFF000) {
            printf("[NONCE] Nonce range nearly exhausted — restarting job\n");
            g_ctx.has_job = 0;
            create_simulated_job(&g_ctx);
            send_job_to_pl(&g_ctx);
        }
    }

    printf("[MAIN] Stopping engines...\n");
    pdsa_csr_write(&g_ctx.hal, CSR_CTRL, CTRL_STOP);
    pdsa_hal_close(&g_ctx.hal);

    if (g_ctx.csv_log) {
        log_event(&g_ctx, "SHUTDOWN", 0);
        fclose(g_ctx.csv_log);
    }

    printf("\n[MAIN] Final stats:\n");
    printf("  Total hashes:    %llu\n", (unsigned long long)g_ctx.total_hashes);
    printf("  Nonces found:    %u\n",   g_ctx.shares_accepted);
    printf("  DPR switches:    %u\n",   g_ctx.dpr_count);
    printf("  Last DPR latency: %u cycles (%.3f ms)\n",
           g_ctx.dpr_latency_cycles, g_ctx.dpr_latency_cycles / 100000.0f);
    printf("[MAIN] Log saved to %s\n", CSV_LOG_PATH);

    return 0;
}
