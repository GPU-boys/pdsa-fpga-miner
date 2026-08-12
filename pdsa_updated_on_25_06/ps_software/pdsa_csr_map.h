#ifndef PDSA_CSR_MAP_H
#define PDSA_CSR_MAP_H
// =============================================================================
// pdsa_csr_map.h — Complete CSR Register Map (shared by PL and PS)
// =============================================================================
// Byte offsets from PL_CSR_BASE_ADDR (0xA0000000 on KV260)

// ---- Control / Status ----
#define CSR_CTRL            0x000  // [W] bit0=start bit1=stop bit2=decouple bit3=trigger_dpr
#define CSR_STATUS          0x004  // [R] bit0=busy bit1=found bit2=decoupled bit3=dpr_active [15:8]=algo_id
#define CSR_ALGO_SEL        0x008  // [W] 0=Bitcoin 1=Kaspa
#define CSR_NONCE           0x00C  // [W] Starting nonce

// ---- Difficulty Target (256-bit = 8 x 32-bit words) ----
#define CSR_TARGET_BASE     0x010  // [W] target[0..7] at offsets 0x10,0x14,...0x2C

// ---- Midstate (256-bit = 8 x 32-bit words, Bitcoin only) ----
#define CSR_MIDSTATE_BASE   0x030  // [W] midstate[0..7] at offsets 0x30,0x34,...0x4C

// ---- Job Data (640-bit = 20 x 32-bit words) ----
#define CSR_JOBDATA_BASE    0x050  // [W] job_data[0..19] at 0x50,0x54,...0x9C

// ---- Result Hash Readback (8 x 32-bit words at 0xC8-0xE4) ----
#define CSR_RESULT_HASH_BASE  0x0C8  // [R] result_hash[0..7] at offsets 0xC8,0xCC,...0xE4

// ---- PDSA Inputs (PS writes these, PL decision logic reads them) ----
#define CSR_PT_THRESH       0x0A0  // [W] Pool token threshold % (default 30)
#define CSR_PT_CURR         0x0A4  // [W] Current pool token % (PS writes after API query)
#define CSR_BCV_STATUS      0x0A8  // [W] 0=open 1=submitted 2=confirmed

// ---- Status Readbacks ----
#define CSR_HCNT_LO         0x0B0  // [R] Hash count bits [31:0]
#define CSR_HCNT_HI         0x0B4  // [R] Hash count bits [63:32]
#define CSR_GOLDEN_NONCE    0x0B8  // [R] Found nonce value
#define CSR_DPR_LATENCY     0x0BC  // [R] DPR switch time in clock cycles
#define CSR_HASHRATE        0x0C0  // [R] Hashes per 1-second window
#define CSR_PDSA_DECISION   0x0C4  // [R] 0x00=CONTINUE 0x01=SWITCH_PT 0x02=SWITCH_BCV

// ---- Control bit masks ----
#define CTRL_START          0x01
#define CTRL_STOP           0x02
#define CTRL_DECOUPLE       0x04
#define CTRL_TRIGGER_DPR    0x08

// ---- Status bit masks ----
#define STATUS_BUSY         0x01
#define STATUS_FOUND        0x02
#define STATUS_DECOUPLED    0x04
#define STATUS_DPR_ACTIVE   0x08

#endif // PDSA_CSR_MAP_H
