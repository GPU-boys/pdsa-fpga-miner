#!/bin/bash
# =============================================================================
# deploy_kv260.sh — Complete Kria KV260 Setup and Deployment Script
# =============================================================================
# Run this script ON YOUR KV260 (not your PC) after SSH-ing in as root.
# The KV260 should be running Kria Ubuntu 22.04 (from Xilinx/AMD).
#
# PREREQUISITES:
#   1. KV260 booted with Ubuntu 22.04 or PetaLinux
#   2. Ethernet connected and internet working
#   3. Vivado has generated the bitstreams in ./vivado/output/
#
# USAGE:
#   scp this file to the KV260: scp deploy_kv260.sh root@<KV260_IP>:/home/root/
#   Then on the KV260:          chmod +x deploy_kv260.sh && ./deploy_kv260.sh
# =============================================================================

set -e  # Exit immediately on any error

echo "============================================"
echo "  PDSA-FPGA KV260 Deployment Script"
echo "============================================"

# ============================================================
# STEP 1: Verify we are running on an ARM64 KV260
# ============================================================
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: This script must run on the KV260 ARM64 board, not $ARCH"
    exit 1
fi
echo "[1/8] Platform: $ARCH — OK"

# ============================================================
# STEP 2: Install build dependencies
# ============================================================
echo "[2/8] Installing build tools..."
apt-get update -qq
apt-get install -y -qq gcc make git libssl-dev

# ============================================================
# STEP 3: Load the FPGA with the full bitstream
# ============================================================
# The full bitstream initializes the entire FPGA fabric including the
# static shell. After this, partial bitstreams can swap just the RM.
echo "[3/8] Loading full FPGA bitstream..."

if [ ! -f /lib/firmware/pdsa_full_sep_btc.bit ]; then
    echo "  Copying bitstreams to /lib/firmware/..."
    cp ./output/pdsa_full_sep_btc.bit      /lib/firmware/ 2>/dev/null || \
    cp ./vivado/output/pdsa_full_sep_btc.bit /lib/firmware/ 2>/dev/null || \
    echo "  WARNING: pdsa_full_sep_btc.bit not found in ./output/ or ./vivado/output/"
fi

# FPGA Manager is the Linux kernel subsystem for loading bitstreams.
# It talks to the ICAP (Internal Configuration Access Port) in hardware.
# The sequence: write flags (0=full reconfiguration) → write firmware filename
echo 0 > /sys/class/fpga_manager/fpga0/flags
echo "pdsa_full_sep_btc.bit" > /sys/class/fpga_manager/fpga0/firmware

# Wait for configuration to complete
sleep 2

# Verify the FPGA is configured
FPGA_STATE=$(cat /sys/class/fpga_manager/fpga0/state 2>/dev/null || echo "unknown")
echo "  FPGA state: $FPGA_STATE"
if [ "$FPGA_STATE" != "operating" ]; then
    echo "WARNING: FPGA may not be fully configured (state=$FPGA_STATE)"
    echo "  Check that the .bit file matches the XCZU5EV part on your KV260"
fi

# ============================================================
# STEP 4: Configure the Device Tree for PL access
# ============================================================
# The Linux kernel needs to know about the PL hardware to allow /dev/mem access.
# We use a Device Tree Overlay (DTBO) to add the CSR region description.
echo "[4/8] Loading Device Tree Overlay..."

cat > /tmp/pdsa_fpga.dts << 'DTSEOF'
/dts-v1/;
/plugin/;

/ {
    fragment@0 {
        target = <&fpga_full>;
        __overlay__ {
            firmware-name = "pdsa_full_sep_btc.bit";
        };
    };

    fragment@1 {
        target = <&amba>;
        __overlay__ {
            #address-cells = <2>;
            #size-cells = <2>;

            /* PDSA-FPGA CSR block at 0xA0000000 */
            pdsa_csr: pdsa_csr@a0000000 {
                compatible = "generic-uio";
                reg = <0x0 0xA0000000 0x0 0x10000>;
                interrupt-parent = <&gic>;
                /* IRQ from PL: irq_found on PL-PS interrupt 0 */
                interrupts = <0 89 4>;  /* GIC SPI 89, level-high */
            };
        };
    };
};
DTSEOF

# Compile the DTS to DTBO
dtc -I dts -O dtb -o /tmp/pdsa_fpga.dtbo /tmp/pdsa_fpga.dts 2>/dev/null || \
    echo "  Note: dtc not available, skipping DTBO — /dev/mem access will still work"

# Load the overlay if dtc succeeded
if [ -f /tmp/pdsa_fpga.dtbo ]; then
    cp /tmp/pdsa_fpga.dtbo /lib/firmware/
    mkdir -p /sys/kernel/config/device-tree/overlays/pdsa 2>/dev/null || true
    echo "pdsa_fpga.dtbo" > /sys/kernel/config/device-tree/overlays/pdsa/path 2>/dev/null || true
fi

# ============================================================
# STEP 5: Configure /dev/mem access
# ============================================================
# The mining controller uses /dev/mem to map the PL registers directly.
# This requires root and may need the kernel to be built with CONFIG_STRICT_DEVMEM=n
echo "[5/8] Configuring /dev/mem access..."

# Check if strict devmem is blocking us
if ! dd if=/dev/mem bs=4 count=1 skip=$((0xA0000000/4)) 2>/dev/null | xxd | head -1; then
    echo "  /dev/mem access blocked. Checking kernel config..."
    grep STRICT_DEVMEM /boot/config-$(uname -r) 2>/dev/null || true
    echo ""
    echo "  If /dev/mem fails at runtime, use UIO instead:"
    echo "  Check /sys/class/uio/ after loading the device tree overlay"
fi

# Verify the CSR region is accessible (read the first register)
python3 -c "
import mmap, struct
try:
    with open('/dev/mem', 'rb') as f:
        m = mmap.mmap(f.fileno(), 0x1000, mmap.MAP_SHARED, mmap.PROT_READ,
                      offset=0xA0000000)
        val = struct.unpack('<I', m[0:4])[0]
        print(f'  CSR[0x00] = 0x{val:08X} — /dev/mem access OK')
        m.close()
except Exception as e:
    print(f'  /dev/mem test failed: {e}')
    print('  Will attempt to proceed anyway...')
" 2>/dev/null || echo "  Python3 test skipped"

# ============================================================
# STEP 6: Build the PS software
# ============================================================
echo "[6/8] Building PDSA mining controller..."

# Clone or copy the source (assumes source is in current directory)
if [ -f ./Makefile ]; then
    make clean
    make -j4
    echo "  Build successful: ./pdsa_main (standalone mode, no pool)"
else
    echo "  ERROR: Makefile not found. Copy the project to the KV260 first."
    exit 1
fi

# ============================================================
# STEP 7: Check network connectivity (optional for standalone mode)
# ============================================================
echo "[7/8] Checking network connectivity..."
ping -c 1 -W 3 8.8.8.8 > /dev/null 2>&1 && \
    echo "  Internet: OK (not required — standalone mode)" || \
    echo "  WARNING: No internet (fine — standalone mode, no pool needed)"

# ============================================================
# STEP 8: Create systemd service for auto-start
# ============================================================
echo "[8/8] Installing systemd service..."

cat > /etc/systemd/system/pdsa-miner.service << 'SVCEOF'
[Unit]
Description=PDSA-FPGA Bitcoin/Kaspa Adaptive Miner
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/root
ExecStart=/home/root/pdsa_main
Restart=on-failure
RestartSec=30
# Allow /dev/mem access
CapabilityBoundingSet=CAP_SYS_RAWIO CAP_IPC_LOCK
AmbientCapabilities=CAP_SYS_RAWIO CAP_IPC_LOCK
StandardOutput=journal
StandardError=journal
SyslogIdentifier=pdsa-miner

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable pdsa-miner
echo "  Service installed. Start with: systemctl start pdsa-miner"
echo "  View logs with: journalctl -u pdsa-miner -f"

# ============================================================
# DONE
# ============================================================
echo ""
echo "============================================"
echo "  Deployment Complete!"
echo "============================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Test run (foreground):"
echo "     sudo ./pdsa_main"
echo ""
echo "  2. Production run (background, auto-restart):"
echo "     systemctl start pdsa-miner"
echo "     journalctl -u pdsa-miner -f"
echo ""
echo "  3. Monitor measurements:"
echo "     tail -f /home/root/pdsa_measurements.csv"
echo ""
echo "  4. Check FPGA status:"
echo "     cat /sys/class/fpga_manager/fpga0/state"
echo ""
echo "NOTE: This build runs in standalone mode (no pool connection)."
echo "The miner creates simulated jobs and exercises the PL hash"
echo "engines with PDSA-driven DPR switching between SHA-256d and SHA-3."
echo ""
