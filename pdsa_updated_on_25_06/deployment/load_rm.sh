#!/bin/bash
# PDSA-FPGA DFX Runtime: Load shell and swap RMs
# Run on Kria KV260 (Ubuntu)
set -e

BITSTREAM_DIR="/lib/firmware"
FPGAUTIL="sudo fpgautil"

usage() {
    echo "Usage: $0 {load|swap_btc|swap_kaspa|status}"
    echo ""
    echo "  load         - Load full shell + rm_bitcoin"
    echo "  swap_btc     - Swap RP to Bitcoin"
    echo "  swap_kaspa   - Swap RP to Kaspa"
    echo "  status       - Show FPGA status"
    exit 1
}

case "${1:-}" in
    load)
        echo "=== Loading full shell + rm_bitcoin ==="
        # Copy bitstreams to /lib/firmware
        sudo cp output/pdsa_full_sep_btc.bit.bin  /lib/firmware/
        sudo cp output/pdsa_rm_sep_btc.bit.bin    /lib/firmware/
        sudo cp output/pdsa_rm_sep_kaspa.bit.bin  /lib/firmware/

        # Load full bitstream via FPGA manager
        echo "Loading full bitstream..."
        ${FPGAUTIL} -b /lib/firmware/pdsa_full_sep_btc.bit.bin

        # Apply device tree overlay
        echo "Applying device tree overlay..."
        sudo mkdir -p /configfs/device-tree/overlays/pdsa
        sudo cp ps_software/pdsa_dfx.dtbo /configfs/device-tree/overlays/pdsa/dtbo

        echo "Shell loaded. CSR at 0xA000_0000"
        ;;
    swap_btc)
        echo "=== Swapping RP to Bitcoin ==="
        ${FPGAUTIL} -b /lib/firmware/pdsa_rm_sep_btc.bit.bin
        echo "Bitcoin RM loaded"
        ;;
    swap_kaspa)
        echo "=== Swapping RP to Kaspa ==="
        ${FPGAUTIL} -b /lib/firmware/pdsa_rm_sep_kaspa.bit.bin
        echo "Kaspa RM loaded"
        ;;
    status)
        echo "=== FPGA Status ==="
        cat /sys/class/fpga_manager/fpga0/state 2>/dev/null || echo "no fpga_manager"
        ls /configfs/device-tree/overlays/ 2>/dev/null || echo "no overlays"
        sudo cat /sys/kernel/debug/gpio 2>/dev/null | head -20 || true
        ;;
    *)
        usage
        ;;
esac
