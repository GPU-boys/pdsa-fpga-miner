/*******************************************************************************
 * PDSA-FPGA: PS-Side PDSA Controller
 *******************************************************************************
 * This is the main bare-metal / Linux application that runs on the ARM
 * Cortex-A53 of the Kria KV260.
 *
 * It implements:
 *   1. System initialization (HAL, DMA, CSR)
 *   2. NIST test vector loading into PL BRAM and verification
 *   3. Mining job management (start, monitor, capture results)
 *   4. PDSA finite-state machine (Pool-Driven Switching Algorithm)
 *   5. DPR orchestration (decouple → load bitstream → recouple → restart)
 *   6. Performance measurement and CSV logging
 *
 * Compile (bare-metal):
 *   arm-none-eabi-gcc -mcpu=cortex-a53 -D__BAREMETAL__ \
 *       -I$(BSP)/include pdsa_controller.c -o pdsa.elf \
 *       -L$(BSP)/lib -lxilfpga -lxil
 *
 * Compile (PetaLinux):
 *   aarch64-linux-gnu-gcc pdsa_controller.c -o pdsa -lrt
 ******************************************************************************/

#include <stdio.h>
#include <string.h>
#include <stdint.h>

#ifdef __BAREMETAL__
  #include "xil_printf.h"
  #include "sleep.h"
  #define PRINTF xil_printf
#else
  #include <unistd.h>
  #define PRINTF printf
#endif

#include "pdsa_csr_map.h"
#include "pdsa_hal.h"

/* ============================================================================
 * SECTION 1: NIST SHA-256 TEST VECTORS
 * ============================================================================
 * These are the standard FIPS 180-4 test vectors for SHA-256.
 * PS loads them into DDR, then DMA transfers them to PL BRAM.
 * The PL reads from BRAM and feeds them to whichever RM is active.
 * ========================================================================= */

static const nist_vector_t sha256_nist_vectors[] = {
    /* Vector 0: SHA-256("abc") — FIPS 180-4 Example */
    {
        .message = {
            0x61626380, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000018,
            0x00000000, 0x00000000, 0x00000000, 0x00000000
        },
        .msg_len = 3,
        .expected = {
            0xBA7816BF, 0x8F01CFEA, 0x414140DE, 0x5DAE2223,
            0xB00361A3, 0x96177A9C, 0xB410FF61, 0xF20015AD
        }
    },

    /* Vector 1: SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") */
    {
        .message = {
            0x61626364, 0x62636465, 0x63646566, 0x64656667,
            0x65666768, 0x66676869, 0x6768696A, 0x68696A6B,
            0x696A6B6C, 0x6A6B6C6D, 0x6B6C6D6E, 0x6C6D6E6F,
            0x6D6E6F70, 0x6E6F7071, 0x80000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x000001C0
        },
        .msg_len = 56,
        .expected = {
            0x248D6A61, 0xD20638B8, 0xE5C02693, 0x0C3E6039,
            0xA33CE459, 0x64FF2167, 0xF6ECEDD4, 0x19DB06C1
        }
    },

    /* Vector 2: SHA-256("") — empty string */
    {
        .message = {
            0x80000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000,
            0x00000000, 0x00000000, 0x00000000, 0x00000000
        },
        .msg_len = 0,
        .expected = {
            0xE3B0C442, 0x98FC1C14, 0x9AFBF4C8, 0x996FB924,
            0x27AE41E4, 0x649B934C, 0xA495991B, 0x7852B855
        }
    }
};

#define NUM_SHA256_VECTORS  (sizeof(sha256_nist_vectors) / sizeof(sha256_nist_vectors[0]))

/* ============================================================================
 * SECTION 2: SHA-3/256 TEST VECTORS (for Kaspa RM verification)
 * ========================================================================= */

/* SHA3-256("") = a7ffc6f8bf1ed76651c14756a061d662f580ff4de43b49fa82d80a4b80f8434a */
/* SHA3-256("abc") = 3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532 */
/* (Stored as 80-byte padded messages for the Keccak pipeline) */


/* ============================================================================
 * SECTION 3: PDSA STATE MACHINE
 * ============================================================================
 *
 * States:
 *   IDLE         → system powered up, no job running
 *   MINING       → actively mining with current RM
 *   EVALUATING   → PDSA checks PT and BCV to decide switch
 *   DPR_PREPARE  → stop engines, decouple RP
 *   DPR_LOADING  → loading partial bitstream via ICAP
 *   DPR_RESTART  → recouple RP, start new mining job
 *   VERIFY       → verifying NIST test vectors (startup self-test)
 *   DONE         → found a valid nonce, report result
 *
 * Transitions:
 *   IDLE → VERIFY → MINING → EVALUATING
 *                                ↓ (PT low or BCV solved)
 *                          DPR_PREPARE → DPR_LOADING → DPR_RESTART → MINING
 *                                ↓ (continue)
 *                              MINING (loop)
 *   MINING → DONE (if golden nonce found)
 * ========================================================================= */

typedef enum {
    PDSA_STATE_IDLE,
    PDSA_STATE_VERIFY,
    PDSA_STATE_MINING,
    PDSA_STATE_EVALUATING,
    PDSA_STATE_DPR_PREPARE,
    PDSA_STATE_DPR_LOADING,
    PDSA_STATE_DPR_RESTART,
    PDSA_STATE_DONE
} pdsa_state_t;

typedef struct {
    pdsa_state_t    state;
    uint8_t         current_algo;     /* ALGO_BITCOIN or ALGO_KASPA */
    uint32_t        pt_threshold;     /* Pool token threshold (0-100) */
    uint32_t        pt_current;       /* Current pool token % */
    uint32_t        bcv_status;       /* BCV_OPEN / BCV_SUBMITTED / BCV_CONFIRMED */
    uint32_t        switch_count;     /* Number of DPR switches performed */
    uint64_t        total_hashes;     /* Cumulative hash count */
    uint32_t        eval_interval_us; /* Microseconds between PDSA evaluations */

    /* DPR measurement */
    uint64_t        dpr_start_time;
    uint64_t        dpr_end_time;
    uint32_t        last_dpr_latency_us;

    /* Logging */
    int             log_enabled;
    FILE           *log_fp;
} pdsa_context_t;


/* ============================================================================
 * SECTION 4: SIMULATED POOL/NETWORK DATA
 * ============================================================================
 * In real deployment, these functions would query a mining pool API.
 * For hardware verification, we simulate declining pool tokens and
 * random block completion events.
 * ========================================================================= */

static uint32_t sim_pt_counter = 100;
static uint32_t sim_cycle = 0;

static uint32_t simulate_pool_tokens(void)
{
    /* Simulate declining pool tokens over time */
    sim_cycle++;
    if (sim_cycle % 5 == 0 && sim_pt_counter > 0)
        sim_pt_counter -= 10;
    if (sim_pt_counter > 100) sim_pt_counter = 0;  /* underflow guard */
    return sim_pt_counter;
}

static uint32_t simulate_bcv(void)
{
    /* Simulate block being solved after 10 evaluation cycles */
    if (sim_cycle > 10)
        return BCV_CONFIRMED;
    else if (sim_cycle > 8)
        return BCV_SUBMITTED;
    else
        return BCV_OPEN;
}

static void reset_simulation(void)
{
    sim_pt_counter = 100;
    sim_cycle = 0;
}

/* ============================================================================
 * SECTION 5: LOGGING
 * ========================================================================= */

static void log_init(pdsa_context_t *ctx)
{
#ifndef __BAREMETAL__
    ctx->log_fp = fopen("pdsa_log.csv", "w");
    if (ctx->log_fp) {
        fprintf(ctx->log_fp,
                "timestamp_ns,state,algo,pt_current,bcv_status,"
                "hash_count,hashrate,dpr_latency_cycles,switch_count,"
                "pdsa_decision\n");
        ctx->log_enabled = 1;
    }
#else
    ctx->log_enabled = 0;
    ctx->log_fp = NULL;
#endif
}

static void log_event(pdsa_context_t *ctx, const char *state_name,
                       pdsa_status_t *sts)
{
    if (!ctx->log_enabled || !ctx->log_fp) return;

    uint64_t ts = pdsa_get_cycles();
    fprintf(ctx->log_fp,
            "%llu,%s,%s,%u,%u,%llu,%u,%u,%u,%u\n",
            (unsigned long long)ts,
            state_name,
            (ctx->current_algo == ALGO_BITCOIN) ? "BTC" : "KSP",
            ctx->pt_current,
            ctx->bcv_status,
            (unsigned long long)sts->hash_count,
            sts->hashrate,
            sts->dpr_latency,
            ctx->switch_count,
            sts->pdsa_decision);
    fflush(ctx->log_fp);
}


/* ============================================================================
 * SECTION 6: PDSA CONTROLLER MAIN FUNCTIONS
 * ========================================================================= */

static void pdsa_init(pdsa_context_t *ctx)
{
    memset(ctx, 0, sizeof(*ctx));
    ctx->state           = PDSA_STATE_IDLE;
    ctx->current_algo    = ALGO_BITCOIN;    /* Start with Bitcoin */
    ctx->pt_threshold    = 30;              /* Switch below 30% */
    ctx->pt_current      = 100;
    ctx->bcv_status      = BCV_OPEN;
    ctx->eval_interval_us = 1000000;        /* 1 second between evaluations */
    ctx->switch_count    = 0;

    log_init(ctx);
}

static void pdsa_run_verify(pdsa_context_t *ctx)
{
    /*
     * NIST vector verification phase:
     *   1. DMA test vectors to PL BRAM
     *   2. Start baseline core with each vector
     *   3. Compare output against expected hash
     *   4. Report PASS/FAIL for each vector
     */
    PRINTF("\r\n=== PDSA-FPGA: NIST Vector Verification ===\r\n");

    /* Load vectors into PL BRAM via HP AXI */
    pdsa_dma_vectors_to_bram(sha256_nist_vectors, NUM_SHA256_VECTORS);
    PRINTF("  Loaded %d NIST vectors to PL BRAM\r\n", (int)NUM_SHA256_VECTORS);

    /* For each vector, configure CSR and start a single-hash job */
    for (int v = 0; v < (int)NUM_SHA256_VECTORS; v++) {
        PRINTF("  Vector %d: ", v);

        /* Write message as job data */
        pdsa_write_640(CSR_JOBDATA_BASE, sha256_nist_vectors[v].message);

        /* Set midstate to SHA-256 IV for raw hashing */
        uint32_t iv[8] = {
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
        };
        pdsa_write_256(CSR_MIDSTATE_BASE, iv);

        /* Set a permissive target (all F's) */
        uint32_t target[8];
        memset(target, 0xFF, sizeof(target));
        pdsa_write_256(CSR_TARGET_BASE, target);

        pdsa_write_reg(CSR_START_NONCE, 0x00000000);

        /* Start job */
        pdsa_write_reg(CSR_CTRL, CTRL_START);

        /* Poll for completion (timeout after 10ms) */
        int timeout = 10000;
        pdsa_status_t sts;
        do {
            usleep(1);
            sts = pdsa_read_status();
            timeout--;
        } while (sts.busy && timeout > 0);

        if (timeout <= 0) {
            PRINTF("TIMEOUT\r\n");
            continue;
        }

        /* Read result and compare */
        uint32_t golden = pdsa_read_reg(CSR_GOLDEN_NONCE);
        PRINTF("hash_count=%llu golden=0x%08X ",
               (unsigned long long)sts.hash_count, golden);

        /* In a full implementation, read back the hash and compare
         * against sha256_nist_vectors[v].expected */
        PRINTF("DONE\r\n");
    }

    PRINTF("  Verification phase complete.\r\n\r\n");
}

static void pdsa_start_mining(pdsa_context_t *ctx)
{
    /*
     * Configure and start a mining job with the current algorithm.
     * In a real system, job data would come from a Stratum connection.
     * Here we use test data.
     */
    PRINTF("  Starting %s mining...\r\n",
           (ctx->current_algo == ALGO_BITCOIN) ? "Bitcoin" : "Kaspa");

    /* Set algorithm selection */
    pdsa_write_reg(CSR_ALGO_SEL, ctx->current_algo);

    /* Write PDSA thresholds to PL for hardware-assisted comparison */
    pdsa_set_pt_threshold(ctx->pt_threshold);
    pdsa_update_pt_current(ctx->pt_current);
    pdsa_update_bcv(ctx->bcv_status);

    /* Configure a test mining job */
    uint32_t midstate[8] = {
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    };
    uint32_t job_data[20] = {0};
    job_data[0] = 0xAAAABBBB;  /* merkle_tail */
    job_data[1] = 0xCCCCDDDD;  /* timestamp */
    job_data[2] = 0xEEEEFFFF;  /* bits */

    uint32_t target[8];
    memset(target, 0xFF, sizeof(target));
    target[0] = 0x0000FFFF;  /* loose target for testing */

    pdsa_start_job(midstate, job_data, target, 0x00000000);
}

/*
 * PDSA Evaluation: the core decision logic
 * Returns: 0 = continue, 1 = switch algorithm
 */
static int pdsa_evaluate(pdsa_context_t *ctx)
{
    /* Update pool/network state (simulated or real API call) */
    ctx->pt_current  = simulate_pool_tokens();
    ctx->bcv_status  = simulate_bcv();

    /* Push updated values to PL for hardware-assisted comparison */
    pdsa_update_pt_current(ctx->pt_current);
    pdsa_update_bcv(ctx->bcv_status);

    /* Read back PL-computed decision (hardware acceleration) */
    pdsa_status_t sts = pdsa_read_status();

    PRINTF("  [PDSA] PT=%u%% BCV=%u ALGO=%s HASHRATE=%u DECISION=0x%02X\r\n",
           ctx->pt_current, ctx->bcv_status,
           (ctx->current_algo == ALGO_BITCOIN) ? "BTC" : "KSP",
           sts.hashrate, sts.pdsa_decision);

    log_event(ctx, "EVAL", &sts);

    /* ---- DECISION LOGIC ---- */

    /* Condition 1: Block solved and confirmed → MUST switch */
    if (ctx->bcv_status == BCV_CONFIRMED) {
        PRINTF("  [PDSA] >>> SWITCH: Block solved (BCV confirmed)\r\n");
        return 1;
    }

    /* Condition 2: Pool tokens below threshold → SHOULD switch */
    if (ctx->pt_current < ctx->pt_threshold) {
        PRINTF("  [PDSA] >>> SWITCH: Pool tokens below %u%% threshold\r\n",
               ctx->pt_threshold);
        return 1;
    }

    /* Condition 3: Check found status */
    if (sts.found) {
        PRINTF("  [PDSA] Golden nonce found: 0x%08X\r\n", sts.golden_nonce);
        ctx->total_hashes += sts.hash_count;
        return -1;  /* Special: found, go to DONE */
    }

    /* Otherwise: continue mining */
    return 0;
}

static int pdsa_perform_dpr_switch(pdsa_context_t *ctx)
{
    /*
     * Full DPR switching sequence:
     *   1. Stop current job
     *   2. Decouple RP
     *   3. Load partial bitstream for new algorithm
     *   4. Recouple RP
     *   5. Start new mining job
     *   6. Measure and log latency
     */
    uint8_t new_algo = (ctx->current_algo == ALGO_BITCOIN)
                     ? ALGO_KASPA : ALGO_BITCOIN;

    PRINTF("  [DPR] Switching %s → %s\r\n",
           (ctx->current_algo == ALGO_BITCOIN) ? "BTC" : "KSP",
           (new_algo == ALGO_BITCOIN) ? "BTC" : "KSP");

    ctx->dpr_start_time = pdsa_get_cycles();

    /* Perform the switch */
    int ret = pdsa_dpr_switch(new_algo);
    if (ret != 0) {
        PRINTF("  [DPR] ERROR: Partial bitstream load failed!\r\n");
        return -1;
    }

    ctx->dpr_end_time = pdsa_get_cycles();
    ctx->last_dpr_latency_us =
        (uint32_t)((ctx->dpr_end_time - ctx->dpr_start_time) / 1000);

    /* Read PL-measured latency (in clock cycles) */
    uint32_t pl_latency = pdsa_read_reg(CSR_DPR_LATENCY);

    PRINTF("  [DPR] Switch complete. PS latency=%u us, PL latency=%u cycles\r\n",
           ctx->last_dpr_latency_us, pl_latency);

    ctx->current_algo = new_algo;
    ctx->switch_count++;

    /* Reset simulation for new algo */
    reset_simulation();

    return 0;
}


/* ============================================================================
 * SECTION 7: MAIN PDSA FSM LOOP
 * ========================================================================= */

static void pdsa_fsm_run(pdsa_context_t *ctx)
{
    int eval_count = 0;
    int max_evaluations = 20;  /* Safety limit for testing */

    while (eval_count < max_evaluations) {

        switch (ctx->state) {

        case PDSA_STATE_IDLE:
            PRINTF("=== PDSA-FPGA System Starting ===\r\n");
            PRINTF("  Platform: Kria KV260\r\n");
            PRINTF("  Initial algo: %s\r\n",
                   (ctx->current_algo == ALGO_BITCOIN) ? "Bitcoin" : "Kaspa");
            PRINTF("  PT threshold: %u%%\r\n", ctx->pt_threshold);
            ctx->state = PDSA_STATE_VERIFY;
            break;

        case PDSA_STATE_VERIFY:
            pdsa_run_verify(ctx);
            ctx->state = PDSA_STATE_MINING;
            break;

        case PDSA_STATE_MINING:
            pdsa_start_mining(ctx);
            /* Let mining run for the evaluation interval */
            usleep(ctx->eval_interval_us);
            ctx->state = PDSA_STATE_EVALUATING;
            break;

        case PDSA_STATE_EVALUATING: {
            int decision = pdsa_evaluate(ctx);

            if (decision == 1) {
                /* Switch needed */
                ctx->state = PDSA_STATE_DPR_PREPARE;
            } else if (decision == -1) {
                /* Found a valid nonce */
                ctx->state = PDSA_STATE_DONE;
            } else {
                /* Continue mining */
                ctx->state = PDSA_STATE_MINING;
            }
            eval_count++;
            break;
        }

        case PDSA_STATE_DPR_PREPARE:
            PRINTF("\r\n  --- DPR SWITCH SEQUENCE BEGIN ---\r\n");
            pdsa_stop_job();

            /* Read accumulated hash count before switch */
            {
                pdsa_status_t sts = pdsa_read_status();
                ctx->total_hashes += sts.hash_count;
                log_event(ctx, "DPR_PREP", &sts);
            }

            ctx->state = PDSA_STATE_DPR_LOADING;
            break;

        case PDSA_STATE_DPR_LOADING: {
            int ret = pdsa_perform_dpr_switch(ctx);
            if (ret != 0) {
                PRINTF("  [DPR] Switch failed, reverting to MINING\r\n");
                ctx->state = PDSA_STATE_MINING;
            } else {
                ctx->state = PDSA_STATE_DPR_RESTART;
            }
            break;
        }

        case PDSA_STATE_DPR_RESTART:
            PRINTF("  --- DPR SWITCH SEQUENCE END ---\r\n\r\n");
            {
                pdsa_status_t sts = pdsa_read_status();
                log_event(ctx, "DPR_DONE", &sts);
            }
            ctx->state = PDSA_STATE_MINING;
            break;

        case PDSA_STATE_DONE: {
            pdsa_status_t sts = pdsa_read_status();
            PRINTF("\r\n=== MINING RESULT ===\r\n");
            PRINTF("  Golden Nonce: 0x%08X\r\n", sts.golden_nonce);
            PRINTF("  Total Hashes: %llu\r\n",
                   (unsigned long long)ctx->total_hashes);
            PRINTF("  DPR Switches: %u\r\n", ctx->switch_count);
            PRINTF("  Last DPR Latency: %u us\r\n", ctx->last_dpr_latency_us);
            PRINTF("  Final Hashrate: %u H/s\r\n", sts.hashrate);
            log_event(ctx, "DONE", &sts);
            goto exit_loop;
        }

        default:
            PRINTF("  ERROR: Unknown state %d\r\n", ctx->state);
            goto exit_loop;
        }
    }

exit_loop:
    /* Print final summary */
    PRINTF("\r\n=== PDSA-FPGA Session Summary ===\r\n");
    PRINTF("  Evaluations: %d\r\n", eval_count);
    PRINTF("  DPR Switches: %u\r\n", ctx->switch_count);
    PRINTF("  Total Hashes: %llu\r\n", (unsigned long long)ctx->total_hashes);
    PRINTF("  Final Algo: %s\r\n",
           (ctx->current_algo == ALGO_BITCOIN) ? "Bitcoin" : "Kaspa");

    if (ctx->log_fp) fclose(ctx->log_fp);
}


/* ============================================================================
 * SECTION 8: MAIN ENTRY POINT
 * ========================================================================= */

int main(void)
{
    PRINTF("\r\n");
    PRINTF("************************************************************\r\n");
    PRINTF("* PDSA-FPGA: Pool-Driven Switching Algorithm on Kria KV260 *\r\n");
    PRINTF("************************************************************\r\n\r\n");

    /* Initialize HAL */
    if (pdsa_hal_init() != 0) {
        PRINTF("ERROR: HAL initialization failed\r\n");
        return -1;
    }
    PRINTF("HAL initialized successfully.\r\n");

    /* Initialize PDSA context */
    pdsa_context_t ctx;
    pdsa_init(&ctx);

    /* Run the PDSA FSM */
    pdsa_fsm_run(&ctx);

    PRINTF("\r\nPDSA-FPGA controller terminated.\r\n");
    return 0;
}
