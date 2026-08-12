// =============================================================================
// sha256_sw.c — Software SHA-256 Implementation
// =============================================================================
// Used by the PS to compute midstate before sending jobs to the PL hardware.
// Standard FIPS 180-4 SHA-256 — identical to what the PL hardware computes.
// =============================================================================

#include "sha256_sw.h"
#include <string.h>

// ---- SHA-256 Constants (K): cube roots of first 64 primes ----
static const uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

// ---- SHA-256 Initial Values: square roots of first 8 primes ----
static const uint32_t IV[8] = {
    0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
    0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
};

// ---- Rotation and shift macros ----
#define ROTR(x,n)   (((x)>>(n))|((x)<<(32-(n))))
#define SHR(x,n)    ((x)>>(n))
#define CH(x,y,z)   (((x)&(y))^((~(x))&(z)))
#define MAJ(x,y,z)  (((x)&(y))^((x)&(z))^((y)&(z)))
#define BSIG0(x)    (ROTR(x,2) ^ROTR(x,13)^ROTR(x,22))
#define BSIG1(x)    (ROTR(x,6) ^ROTR(x,11)^ROTR(x,25))
#define SSIG0(x)    (ROTR(x,7) ^ROTR(x,18)^SHR(x,3))
#define SSIG1(x)    (ROTR(x,17)^ROTR(x,19)^SHR(x,10))

// ---- Big-endian helpers ----
static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0]<<24)|((uint32_t)p[1]<<16)|
           ((uint32_t)p[2]<<8) |((uint32_t)p[3]);
}
static void put_be32(uint8_t *p, uint32_t v) {
    p[0]=v>>24; p[1]=v>>16; p[2]=v>>8; p[3]=v;
}
static void put_be64(uint8_t *p, uint64_t v) {
    put_be32(p,   (uint32_t)(v>>32));
    put_be32(p+4, (uint32_t)(v));
}

// ---- Core SHA-256 compression: one 64-byte block ----
// This function is the heart of SHA-256.
// It takes an 8-word state and a 16-word message block,
// runs 64 rounds, and adds the round outputs back to the input state.
static void sha256_compress(uint32_t state[8], const uint8_t block[64]) {
    uint32_t a,b,c,d,e,f,g,h, T1,T2, W[64];
    int i;

    // Prepare message schedule W[0..63]
    // W[0..15]: loaded directly from block bytes (big-endian)
    for (i = 0; i < 16; i++)
        W[i] = be32(block + i*4);
    // W[16..63]: expanded from earlier words
    for (i = 16; i < 64; i++)
        W[i] = SSIG1(W[i-2]) + W[i-7] + SSIG0(W[i-15]) + W[i-16];

    // Initialize working variables from current state
    a=state[0]; b=state[1]; c=state[2]; d=state[3];
    e=state[4]; f=state[5]; g=state[6]; h=state[7];

    // 64 rounds of SHA-256
    for (i = 0; i < 64; i++) {
        T1 = h + BSIG1(e) + CH(e,f,g)  + K[i] + W[i];
        T2 =     BSIG0(a) + MAJ(a,b,c);
        h=g; g=f; f=e; e=d+T1;
        d=c; c=b; b=a; a=T1+T2;
    }

    // Add compressed chunk to current hash state
    state[0]+=a; state[1]+=b; state[2]+=c; state[3]+=d;
    state[4]+=e; state[5]+=f; state[6]+=g; state[7]+=h;
}

// ---- Public API ----

void sha256_init(sha256_ctx_t *ctx) {
    memcpy(ctx->state, IV, sizeof(IV));
    ctx->count = 0;
    memset(ctx->buf, 0, sizeof(ctx->buf));
}

void sha256_update(sha256_ctx_t *ctx, const uint8_t *data, size_t len) {
    size_t used = (size_t)(ctx->count/8) & 63;
    ctx->count += (uint64_t)len * 8;

    if (used) {
        size_t free = 64 - used;
        if (len < free) {
            memcpy(ctx->buf + used, data, len);
            return;
        }
        memcpy(ctx->buf + used, data, free);
        sha256_compress(ctx->state, ctx->buf);
        data += free; len -= free;
    }
    while (len >= 64) {
        sha256_compress(ctx->state, data);
        data += 64; len -= 64;
    }
    memcpy(ctx->buf, data, len);
}

void sha256_final(sha256_ctx_t *ctx, uint8_t hash[32]) {
    size_t used = (size_t)(ctx->count/8) & 63;
    int i;
    ctx->buf[used++] = 0x80;
    if (used > 56) {
        memset(ctx->buf + used, 0, 64 - used);
        sha256_compress(ctx->state, ctx->buf);
        used = 0;
    }
    memset(ctx->buf + used, 0, 56 - used);
    put_be64(ctx->buf + 56, ctx->count);
    sha256_compress(ctx->state, ctx->buf);
    for (i = 0; i < 8; i++)
        put_be32(hash + i*4, ctx->state[i]);
}

void sha256(const uint8_t *data, size_t len, uint8_t hash[32]) {
    sha256_ctx_t ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, data, len);
    sha256_final(&ctx, hash);
}

void sha256d(const uint8_t *data, size_t len, uint8_t hash[32]) {
    // Bitcoin's double SHA-256: hash the hash
    sha256(data, len, hash);
    sha256(hash, 32, hash);
}

// =============================================================================
// MIDSTATE COMPUTATION
// =============================================================================
// CONCEPT: Bitcoin's 80-byte block header is split into two 64-byte chunks.
// Chunk 1 (bytes 0-63):  version(4) + prevblock(32) + merkle_first28(28)
//   → This NEVER changes during mining of one block
//   → We compute SHA-256_compress(IV, chunk1) ONCE on the PS = midstate
//   → PL hardware starts from midstate instead of re-doing this every time
//
// Chunk 2 (bytes 64-79): merkle_last4(4) + time(4) + bits(4) + nonce(4)
//   → The nonce changes every attempt
//   → PL hardware computes SHA-256_compress(midstate, chunk2+padding) per nonce
//
// This saves 64 SHA-256 rounds (50% of SHA-256d work) per hash attempt.
// =============================================================================

void sha256_midstate(const uint32_t iv[8], const uint8_t block[64], uint32_t out[8]) {
    // Run one SHA-256 compression block WITHOUT padding or finalization
    // This is the raw internal step, not the padded sha256() call
    memcpy(out, iv, 8 * sizeof(uint32_t));
    sha256_compress(out, block);
}

void bitcoin_compute_midstate(const uint8_t header_first64[64], uint32_t midstate[8]) {
    // Apply SHA-256 compression (no padding) to first 64 bytes using standard IV
    memcpy(midstate, IV, sizeof(IV));
    sha256_compress(midstate, header_first64);
    // midstate[0..7] now holds the SHA-256 internal state after block 1
    // The PL hardware uses this as its starting state for block 2
}

// =============================================================================
// TARGET DECODING
// =============================================================================
// CONCEPT: Bitcoin encodes difficulty as a compact 4-byte 'bits' field.
// Format: bits = (exponent << 24) | mantissa
// Decoded as: target = mantissa × 256^(exponent - 3)
// Example: bits = 0x1903a30c
//   exponent = 0x19 = 25
//   mantissa = 0x03a30c
//   target = 0x03a30c × 256^(25-3) = 0x03a30c × 256^22
// Result: a 256-bit number where most significant bytes are zero (leading zeros)
// =============================================================================

void bitcoin_decode_target(uint32_t bits_compact, uint8_t target[32]) {
    uint32_t exp     = (bits_compact >> 24) & 0xFF;    // exponent byte
    uint32_t mant    = bits_compact & 0x007FFFFF;      // 23-bit mantissa
    int      byte_pos;

    memset(target, 0, 32);

    if (exp < 3 || exp > 32) return;  // invalid

    // Place mantissa bytes at position (32 - exp) from the end
    // Target is big-endian: index 0 = most significant byte
    byte_pos = 32 - (int)exp;

    if (byte_pos >= 0 && byte_pos < 30) {
        target[byte_pos]   = (mant >> 16) & 0xFF;
        target[byte_pos+1] = (mant >>  8) & 0xFF;
        target[byte_pos+2] = (mant >>  0) & 0xFF;
    }
}
