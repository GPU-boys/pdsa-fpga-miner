#ifndef PDSA_HAL_H
#define PDSA_HAL_H

// =============================================================================
// pdsa_hal.h — Hardware Abstraction Layer for Kria KV260 Linux
// =============================================================================
// On the Kria KV260, the PL registers are accessed via /dev/mem + mmap.
// Physical address 0xA0000000 = AXI-Lite slave port from Vivado block design.
// =============================================================================

#include <stdint.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>

#define PL_CSR_BASE_ADDR  0xA0000000UL
#define PL_CSR_MAP_SIZE   0x10000UL

typedef struct {
    int      fd;
    void    *base;
    uint32_t phys_base;
    uint32_t map_size;
} pdsa_hal_t;

static inline int pdsa_hal_init(pdsa_hal_t *hal, uint32_t phys_base) {
    hal->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (hal->fd < 0) { perror("[HAL] open /dev/mem"); return -1; }
    hal->phys_base = phys_base;
    hal->map_size  = PL_CSR_MAP_SIZE;
    hal->base = mmap(NULL, hal->map_size, PROT_READ|PROT_WRITE,
                     MAP_SHARED, hal->fd, (off_t)phys_base);
    if (hal->base == MAP_FAILED) {
        perror("[HAL] mmap"); close(hal->fd); hal->fd=-1; return -1;
    }
    printf("[HAL] Mapped PL CSR @ 0x%08X\n", phys_base);
    return 0;
}

static inline void pdsa_csr_write(pdsa_hal_t *hal, uint32_t off, uint32_t val) {
    volatile uint32_t *r = (volatile uint32_t*)((uint8_t*)hal->base + off);
    *r = val;
    __asm__ volatile("dsb sy":::"memory");
}

static inline uint32_t pdsa_csr_read(pdsa_hal_t *hal, uint32_t off) {
    volatile uint32_t *r = (volatile uint32_t*)((uint8_t*)hal->base + off);
    __asm__ volatile("dsb sy":::"memory");
    return *r;
}

static inline void pdsa_hal_close(pdsa_hal_t *hal) {
    if (hal->base && hal->base != MAP_FAILED) munmap(hal->base, hal->map_size);
    if (hal->fd >= 0) { close(hal->fd); hal->fd = -1; }
}

#endif // PDSA_HAL_H
