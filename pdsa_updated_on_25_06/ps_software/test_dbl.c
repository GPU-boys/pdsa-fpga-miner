#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "mining/sha256_sw.h"

void print_hash(const char *label, const uint8_t h[32]) {
    printf("%s: ", label);
    for (int i = 0; i < 32; i++) printf("%02x", h[i]);
    printf("\n");
}

int main() {
    uint8_t h1[32], h2[32];

    // Verify SHA-256d of empty string
    sha256d((const uint8_t*)"", 0, h1);
    print_hash("sha256d(\"\")", h1);
    uint8_t exp_dbl_empty[32] = {0x5d,0xf6,0xe0,0xe2,0x76,0x13,0x59,0xd3,0x0a,0x82,0x75,0x05,0x8e,0x29,0x9f,0xcc,0x03,0x81,0x53,0x45,0x45,0xf5,0x5c,0xf4,0x3e,0x41,0x98,0x3f,0x5d,0x4c,0x94,0x56};
    printf("Expected: 5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456\nMatch: %s\n\n", memcmp(h1, exp_dbl_empty, 32) == 0 ? "YES" : "NO");

    // Now test SHA-256d of single byte
    uint8_t msg8[1] = {0x80};
    sha256d(msg8, 1, h1);
    print_hash("sha256d(0x80)", h1);

    // Debug genesis: compute SHA-256 manually then double
    uint32_t correct_words[20] = {
        0x00000001, 0x00000000, 0x00000000, 0x00000000,
        0x00000000, 0x00000000, 0x00000000, 0x00000000,
        0x00000000,         0xfdeda33b, 0xb2127b7a, 0x3e2cc77a,
        0x618f7667, 0xc31bc87f, 0x32518a88, 0xaab89f3a,
        0x4a5e1e4b, 0x495fab29, 0x1d00ffff, 0x7c2bac1d
    };
    uint8_t header[80];
    for (int i = 0; i < 20; i++) {
        header[i*4+0] = correct_words[i] & 0xFF;
        header[i*4+1] = (correct_words[i] >> 8) & 0xFF;
        header[i*4+2] = (correct_words[i] >> 16) & 0xFF;
        header[i*4+3] = (correct_words[i] >> 24) & 0xFF;
    }
    printf("Full header hex:\n  ");
    for (int i = 0; i < 80; i++) printf("%02x", header[i]);
    printf("\n\n");

    // SHA-256 first pass (standard SHA-256 of 80 bytes = 1 block + padding)
    sha256(header, 80, h1);
    print_hash("SHA256(header)", h1);

    // SHA-256 second pass (on the 32-byte hash)
    sha256(h1, 32, h2);
    print_hash("SHA256(SHA256(header))", h2);

    uint8_t exp[32] = {0x6f,0xe2,0x8c,0x0a,0xb6,0xf1,0xb3,0x72,0xc1,0xa6,0xa2,0x46,0xae,0x63,0xf7,0x4f,0x93,0x1e,0x83,0x65,0xe1,0x5a,0x08,0x9c,0x68,0xd6,0x19,0x00,0x00,0x00,0x00,0x00};
    printf("Expected genesis: 6fe28c0ab6f1b372c1a6a246ae63f74f931e8365e15a089c68d6190000000000\nMatch: %s\n", memcmp(h2, exp, 32) == 0 ? "YES" : "NO");
    return 0;
}
