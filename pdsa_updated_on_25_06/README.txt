PDSA-FPGA — Updated 2 June 2026
=================================

Current working files organized for Kria KV260 deployment.

Directories
-----------
bitstream/      - Full + partial bitstreams (BTC and Kaspa)
build_scripts/  - Vivado TCL build flows
constraints/    - XDC timing/physical constraints
deployment/     - Runtime scripts (load_rm.sh)
docs/           - README + explanation PDF
ps_software/    - Linux userspace C app, DT overlay, Makefile
reports/        - Utilization, timing, power reports from synthesis
rtl/            - All SystemVerilog/Verilog RTL sources
simulation/     - ModelSim DO scripts + pass/fail logs

RTL Changes (Increased Utilization)
-------------------------------------
- rm_bitcoin.sv:  NUM_ENGINES default = 2 → 32
- sha256d_multi_engine_hp.sv:  Rewritten with generate-loop for N engines
                              (was hardcoded 2). Uses real SHA-256d engines.
- sha256d_real_engine.sv (NEW):  Real SHA-256d using sha256_core_baseline.sv
                                (2x SHA-256 cores per engine, 133 cycles/nonce)
- sha256d_pipe_engine_hp.sv:  Retained (was XOR fake, no longer used by default)
- tb_rm_bitcoin.sv:  Rewritten for real engine + co-simulation reference model

Build Requirement
------------------
The current bitstreams in bitstream/ still have the old (low-utilization) design.
To generate new bitstreams with ~30-65% LUT utilization, re-run Vivado:

    cd build_scripts
    vivado -source vivado_bd_dfx_separate_rp.tcl   (for _sep_ variants)
    or
    vivado -source vivado_bd_dfx_proper.tcl         (for proper DFX flow)

Estimated utilization with NUM_ENGINES=32:
  - 32 engines x 2 SHA-256 cores x ~1000 LUTs = ~64K LUTs (~55%)
  - Plus control logic, routing = ~70-75K LUTs (~60-65%)

Key Bitstreams (in bitstream/)
-------------------------------
pdsa_full_sep_btc.bit       - Shell + Bitcoin RM (old, low util)
pdsa_rm_sep_btc.bit         - Partial: swap to Bitcoin (old, low util)
pdsa_rm_sep_kaspa.bit       - Partial: swap to Kaspa (old, low util)

NOTE: Rebuild Vivado to get new high-utilization bitstreams.

Verification (in simulation/)
------------------------------
sim_rm_bitcoin.log  - 6/6 PASS (old)
sim_rm_kaspa.log    - 6/6 PASS (old)
TEST_RESULTS.txt    - Summary (old)

NOTE: Run ModelSim with updated testbench after rebuild.

Bug Fixes Applied (18 June 2026)
---------------------------------
=== Critical ===
1. rtl/sha256d_real_engine.sv:69 — blk1 length field changed from 0x80 (128) to
   0x280 (640) — every double-SHA-256 hash was wrong due to incorrect SHA-256
   padding length encoding for the 80-byte (640-bit) block header.
2. ps_software/pdsa_main.c — STATUS_FOUND now cleared via STOP/START sequence
   after nonce submission to prevent duplicate share submissions (pool ban).
3. ps_software/pdsa_main.c — DPR flags corrected from "echo 0" to "echo 1"
   (partial bitstream flag, not full bitstream).
4. rtl/sha3_256_pipe_engine_hp.sv — Replaced XOR placeholder with real
   Keccak-f[1600] SHA-3-256 implementation (24 rounds of θ/ρ/π/χ/ι).

=== High ===
5. ps_software/pdsa_main.c — feed_nist_to_pl() now compares PL result hash
   against expected NIST vector; previously printed but never checked.
6. rtl/pdsa_fpga_dfx_top.sv — NUM_ENGINES parameter changed from 2 to 32
   (was limiting hashrate to ~1.5 Mhash/s instead of ~24 Mhash/s).
7. ps_software/pdsa_main.c — Added Bitcoin genesis block double-SHA-256
   self-test that validates the full PL pipeline against a known hash.
8. rtl/sha256d_multi_engine_hp.sv — Added engine_done guard in dispatch logic
   to prevent same-cycle write conflict on engine_started/engine_valid.

=== Medium ===
9. ps_software/pdsa_main.c — Added FPGA watchdog that monitors hash_count
   every 30s and restarts the job if the counter stalls.
10. rtl/sha256_core_baseline.sv — Removed unused SHA256_IV localparam and
    dead block_reg register (loaded but never read).
11. rtl/sha256d_real_engine.sv — Removed dead DONE=2'd3 localparam (PSM uses
    only IDLE/HASH1/HASH2, 3 states not 4).
12. rtl/sha256d_multi_engine_hp.sv — hash_count now reset to 0 on stop_job
    (prevents drifting stats after stop/restart).

=== Low ===
13. ps_software/pdsa_main.c — Removed dead-code first snprintf() in
    do_dpr_switch() that was immediately overwritten by the second.
14. ps_software/pdsa_main.c — Added nonce range tracking: detects when the
    starting nonce approaches 0xFFFFF000 and requests a new job before the
    32-bit nonce space is exhausted.
15. [DELETED] ps_software/stratum/ — Entire stratum/ directory removed
    (stratum_client.c/h). Project now runs in standalone mode with no
    pool dependency. See pdsa_main.c for local mining loop.

Build Status
--------------
Vivado 2025.2, Part: xck26-sfvc784-2LV-c
- Rebuild required for new high-utilization bitstreams
