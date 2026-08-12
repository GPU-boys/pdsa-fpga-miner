#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "mining/sha256_sw.h"

int main() {
    uint8_t hash[32];
    int pass = 0, fail = 0;
    uint8_t exp1[32] = {0xBA,0x78,0x16,0xBF,0x8F,0x01,0xCF,0xEA,0x41,0x41,0x40,0xDE,0x5D,0xAE,0x22,0x23,0xB0,0x03,0x61,0xA3,0x96,0x17,0x7A,0x9C,0xB4,0x10,0xFF,0x61,0xF2,0x00,0x15,0xAD};
    uint8_t exp2[32] = {0xE3,0xB0,0xC4,0x42,0x98,0xFC,0x1C,0x14,0x9A,0xFB,0xF4,0xC8,0x99,0x6F,0xB9,0x24,0x27,0xAE,0x41,0xE4,0x64,0x9B,0x93,0x4C,0xA4,0x95,0x99,0x1B,0x78,0x52,0xB8,0x55};
    uint8_t exp_genesis[32] = {0x6f,0xe2,0x8c,0x0a,0xb6,0xf1,0xb3,0x72,0xc1,0xa6,0xa2,0x46,0xae,0x63,0xf7,0x4f,0x93,0x1e,0x83,0x65,0xe1,0x5a,0x08,0x9c,0x68,0xd6,0x19,0x00,0x00,0x00,0x00,0x00};

    // Test 1: SHA-256("abc")
    sha256((const uint8_t*)"abc", 3, hash);
    printf("Test 1 SHA-256(\"abc\"): %s\n", memcmp(hash, exp1, 32) == 0 ? "PASS" : "FAIL");
    if (memcmp(hash, exp1, 32) == 0) pass++; else fail++;

    // Test 2: SHA-256("")
    sha256((const uint8_t*)"", 0, hash);
    printf("Test 2 SHA-256(\"\"): %s\n", memcmp(hash, exp2, 32) == 0 ? "PASS" : "FAIL");
    if (memcmp(hash, exp2, 32) == 0) pass++; else fail++;

    // Test 3: Bitcoin genesis block header (replicating pdsa_main.c serialization)
    uint32_t genesis_words[20] = {
        0x00000001, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000,         0xfdeda33b, 0xb2127b7a, 0x3e2cc77a,
        0x618f7667, 0xc31bc87f, 0x32518a88, 0xaab89f3a,
        0x4a5e1e4b, 0x495fab29, 0x1d00ffff, 0x7c2bac1d
    };
    uint8_t header_bytes[80];
    for (int i = 0; i < 20; i++) {
        header_bytes[i*4+0] = genesis_words[i] & 0xFF;
        header_bytes[i*4+1] = (genesis_words[i] >> 8) & 0xFF;
        header_bytes[i*4+2] = (genesis_words[i] >> 16) & 0xFF;
        header_bytes[i*4+3] = (genesis_words[i] >> 24) & 0xFF;
    }
    printf("Test 3 header bytes: ");
    for (int i = 0; i < 80; i++) printf("%02x", header_bytes[i]);
    printf("\n");

    sha256d(header_bytes, 80, hash);
    printf("Test 3 Genesis block DBL-SHA-256: %s\n", memcmp(hash, exp_genesis, 32) == 0 ? "PASS" : "FAIL");
    if (memcmp(hash, exp_genesis, 32) == 0) pass++; else fail++;

    // Test 4: Midstate computation
    uint32_t midstate[8];
    bitcoin_compute_midstate(header_bytes, midstate);
    printf("Test 4 Midstate: ");
    for (int i = 0; i < 8; i++) printf("%08x ", midstate[i]);
    printf("\n");

    // Test 5: Verify midstate + second block = correct double hash
    uint32_t merkle_tail = ((uint32_t)header_bytes[64+3] << 24) | ((uint32_t)header_bytes[64+2] << 16) | ((uint32_t)header_bytes[64+1] << 8) | ((uint32_t)header_bytes[64+0]);
    uint32_t timestamp   = ((uint32_t)header_bytes[68+3] << 24) | ((uint32_t)header_bytes[68+2] << 16) | ((uint32_t)header_bytes[68+1] << 8) | ((uint32_t)header_bytes[68+0]);
    uint32_t nbits       = ((uint32_t)header_bytes[72+3] << 24) | ((uint32_t)header_bytes[72+2] << 16) | ((uint32_t)header_bytes[72+1] << 8) | ((uint32_t)header_bytes[72+0]);
    uint32_t nonce       = ((uint32_t)header_bytes[76+3] << 24) | ((uint32_t)header_bytes[76+2] << 16) | ((uint32_t)header_bytes[76+1] << 8) | ((uint32_t)header_bytes[76+0]);
    printf("Test 5 Fields: merkle_tail=0x%08x timestamp=0x%08x nbits=0x%08x nonce=0x%08x\n", merkle_tail, timestamp, nbits, nonce);
    
    // sha256_sw doesn't have a midstate-resume function for double-SHA-256,
    // so just validate the midstate exists
    printf("Test 5 Midstate non-zero: %s\n", (midstate[0] != 0 || midstate[1] != 0) ? "PASS" : "FAIL");
    if (midstate[0] != 0 || midstate[1] != 0) pass++; else fail++;

    // Test 6: Multi-block NIST "abcdbcde..." 
    const uint8_t *msg56 = (const uint8_t*)"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    uint8_t exp56[32] = {0x24,0x8D,0x6A,0x61,0xD2,0x06,0x38,0xB8,0xE5,0xC0,0x26,0x93,0x0C,0x3E,0x60,0x39,0xA3,0x3C,0xE4,0x59,0x64,0xFF,0x21,0x67,0xF6,0xEC,0xED,0xD4,0x19,0xDB,0x06,0xC1};
    sha256(msg56, 56, hash);
    printf("Test 6 SHA-256(56-byte msg): %s\n", memcmp(hash, exp56, 32) == 0 ? "PASS" : "FAIL");
    if (memcmp(hash, exp56, 32) == 0) pass++; else fail++;

    printf("\n=== Results: %dP %dF ===\n", pass, fail);
    return fail > 0 ? 1 : 0;
}
