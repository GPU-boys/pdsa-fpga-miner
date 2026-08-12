#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "mining/sha256_sw.h"

int main() {
    uint8_t hash[32];
    uint8_t exp_genesis[32] = {0x6f,0xe2,0x8c,0x0a,0xb6,0xf1,0xb3,0x72,0xc1,0xa6,0xa2,0x46,0xae,0x63,0xf7,0x4f,0x93,0x1e,0x83,0x65,0xe1,0x5a,0x08,0x9c,0x68,0xd6,0x19,0x00,0x00,0x00,0x00,0x00};

    // Replicate pdsa_main.c's exact genesis header array
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

    printf("Header bytes 68-79 from pdsa_main.c values:\n");
    printf("  bytes[68-71] (timestamp): %02x %02x %02x %02x\n", header_bytes[68],header_bytes[69],header_bytes[70],header_bytes[71]);
    printf("  bytes[72-75] (bits):      %02x %02x %02x %02x\n", header_bytes[72],header_bytes[73],header_bytes[74],header_bytes[75]);
    printf("  bytes[76-79] (nonce):     %02x %02x %02x %02x\n", header_bytes[76],header_bytes[77],header_bytes[78],header_bytes[79]);
    printf("  (expected: 29 AB 5F 49 / FF FF 00 1D / 1D AC 2B 7C)\n\n");

    sha256d(header_bytes, 80, hash);
    printf("Hash from pdsa_main.c wrong header:\n  ");
    for (int i = 0; i < 32; i++) printf("%02x", hash[i]);
    printf("\nExpected correct genesis hash:\n  ");
    for (int i = 0; i < 32; i++) printf("%02x", exp_genesis[i]);
    printf("\nMatch: %s\n\n", memcmp(hash, exp_genesis, 32) == 0 ? "YES" : "NO");

    // Now test with CORRECT header values
    uint32_t correct_words[20] = {
        0x00000001, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000,         0xfdeda33b, 0xb2127b7a, 0x3e2cc77a,
        0x618f7667, 0xc31bc87f, 0x32518a88, 0xaab89f3a,
        0x4a5e1e4b, 0x495fab29, 0x1d00ffff, 0x7c2bac1d
    };
    for (int i = 0; i < 20; i++) {
        header_bytes[i*4+0] = correct_words[i] & 0xFF;
        header_bytes[i*4+1] = (correct_words[i] >> 8) & 0xFF;
        header_bytes[i*4+2] = (correct_words[i] >> 16) & 0xFF;
        header_bytes[i*4+3] = (correct_words[i] >> 24) & 0xFF;
    }
    printf("CORRECT header bytes 68-79:\n");
    printf("  bytes[68-71] (timestamp): %02x %02x %02x %02x\n", header_bytes[68],header_bytes[69],header_bytes[70],header_bytes[71]);
    printf("  bytes[72-75] (bits):      %02x %02x %02x %02x\n", header_bytes[72],header_bytes[73],header_bytes[74],header_bytes[75]);
    printf("  bytes[76-79] (nonce):     %02x %02x %02x %02x\n", header_bytes[76],header_bytes[77],header_bytes[78],header_bytes[79]);

    sha256d(header_bytes, 80, hash);
    printf("Hash from CORRECT header:\n  ");
    for (int i = 0; i < 32; i++) printf("%02x", hash[i]);
    printf("\nExpected correct genesis hash:\n  ");
    for (int i = 0; i < 32; i++) printf("%02x", exp_genesis[i]);
    printf("\nMatch: %s\n", memcmp(hash, exp_genesis, 32) == 0 ? "YES" : "NO");
    return 0;
}
