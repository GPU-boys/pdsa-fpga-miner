#ifndef SHA256_SW_H
#define SHA256_SW_H

// =============================================================================
// sha256_sw.h — Software SHA-256 for the ARM PS (Kria KV260)
// =============================================================================
// PURPOSE: The ARM CPU needs to compute the SHA-256 MIDSTATE before sending
// the mining job to PL hardware. The midstate is SHA-256 applied to the
// FIRST 64 bytes of the 80-byte block header. Since these bytes never change
// during mining of one block (version, prevblock, most of merkle root),
// computing midstate once in software saves the PL from doing 64 redundant
// SHA-256 rounds per nonce. The PL only handles the remaining 16 bytes
// (merkle tail, timestamp, bits, nonce) + padding.
// =============================================================================

#include <stdint.h>
#include <stddef.h>

// SHA-256 context: holds the running state during computation
typedef struct {
    uint32_t state[8];    // Current 8-word hash state (a,b,c,d,e,f,g,h)
    uint64_t count;       // Total bits processed so far
    uint8_t  buf[64];     // Partial block buffer
} sha256_ctx_t;

// Standard SHA-256 functions
void sha256_init   (sha256_ctx_t *ctx);
void sha256_update (sha256_ctx_t *ctx, const uint8_t *data, size_t len);
void sha256_final  (sha256_ctx_t *ctx, uint8_t hash[32]);

// One-shot: hash data and write 32-byte result
void sha256       (const uint8_t *data, size_t len, uint8_t hash[32]);

// Double SHA-256 — what Bitcoin mining uses
void sha256d      (const uint8_t *data, size_t len, uint8_t hash[32]);

// MIDSTATE: Apply SHA-256 compression to exactly one 64-byte block.
// This is NOT the same as sha256() — it does NOT add padding.
// Input:  iv[8]     = 8-word initial value (SHA-256 standard IV or chained state)
//         block[64] = exactly 64 bytes (one SHA-256 block)
// Output: out[8]    = 8-word state after compression (the midstate)
void sha256_midstate(const uint32_t iv[8],
                     const uint8_t  block[64],
                     uint32_t       out[8]);

// Convenience: compute Bitcoin midstate from the first 64 bytes of block header
// Input:  header_first64[64] = first 64 bytes of 80-byte Bitcoin block header
// Output: midstate[8]        = 8 x uint32 midstate (little-endian word order)
void bitcoin_compute_midstate(const uint8_t header_first64[64],
                               uint32_t midstate[8]);

// Decode Bitcoin 'bits' field (4 bytes) into 256-bit target (32 bytes big-endian)
void bitcoin_decode_target(uint32_t bits_compact, uint8_t target[32]);

#endif // SHA256_SW_H
