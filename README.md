# A Pool-Driven Switching Algorithm and Dynamic Partial Reconfiguration Architecture for Multi-Algorithm FPGA Mining Accelerators

FPGA-based proof-of-work mining accelerator targeting the Xilinx Kria KV260 (Zynq UltraScale+ `xck26`). It mines SHA-256d (Bitcoin) or SHA-3-256 Keccak (Kaspa) at runtime by swapping hashing pipelines with Dynamic Partial Reconfiguration (DPR), scheduled entirely in hardware by the Pool-Driven Switching Algorithm (PDSA) state machine in the FPGA static shell — no pool-side software in the loop.

**Paper:** [`FPGA_DPR_Mining_IEEE_Paper_v8_corrected.docx`](FPGA_DPR_Mining_IEEE_Paper_v8_corrected.docx)

## Results (measured, 100 MHz fabric clock)

| Configuration | Hashrate | Power | Efficiency |
|---|---|---|---|
| SHA-256d (20-engine pipeline) | 15.04 Mhash/s | 1.235 W | 12.18 Mhash/s/W |
| SHA-3-256 Keccak | 4.0 Mhash/s | 2.529 W | 1.58 Mhash/s/W |

Static shell: 3,738 LUTs (3.19% of device), zero DSP / BRAM. Full static timing closure (WNS +0.562 ns). RTL simulation verified against a co-simulation reference model.

## Repository structure

```
├── FPGA_DPR_Mining_IEEE_Paper_v8_corrected.docx   # Manuscript (IEEE two-column format)
├── figures/                                       # Platform comparison figures + generator
└── pdsa_updated_on_25_06/                         # Full project
    ├── rtl/            # SystemVerilog/Verilog RTL (static shell, rm_bitcoin, rm_kaspa, SHA-256d / Keccak engines)
    ├── ps_software/    # Linux userspace mining app, AXI-Lite CSR driver, DT overlay, Makefile
    ├── build_scripts/  # Vivado 2025.2 TCL build flows
    ├── constraints/    # KV260 XDC (timing/physical)
    ├── bitstream/      # Full + partial bitstreams and checkpoints (BTC / Kaspa)
    ├── deployment/     # Runtime scripts (load_rm.sh)
    ├── reports/        # Utilization / timing / power reports
    ├── simulation/     # ModelSim testbenches + results
    └── docs/           # Project README, CSR register map
```

## Building the bitstreams (Vivado 2025.2)

```sh
cd pdsa_updated_on_25_06/build_scripts
vivado -source vivado_bd_dfx_separate_rp.tcl   # separate RP flow (correct partials)
# or
vivado -source vivado_bd_dfx_proper.tcl         # proper DFX / OOC flow
```

## Software (build on Kria, or cross-compile for aarch64)

```sh
cd pdsa_updated_on_25_06/ps_software
make clean all
sudo ./pdsa_main
```

## Deployment on KV260

```sh
sudo cp pdsa_updated_on_25_06/bitstream/pdsa_full.bit.bin  /lib/firmware/
sudo cp pdsa_updated_on_25_06/bitstream/pdsa_rm_kaspa.bin  /lib/firmware/

sudo fpgautil -b /lib/firmware/pdsa_full.bit.bin   # load static shell + SHA-256d RM
sudo fpgautil -b /lib/firmware/pdsa_rm_kaspa.bin   # runtime swap to Kaspa RM
```

## Verification

```sh
cd pdsa_updated_on_25_06/simulation
run_sim.bat    # rm_bitcoin + rm_kaspa testbenches (12/12 must pass)
```

## How PDSA works

The static-shell state machine evaluates two decision variables — a Blockchain Value (BCV) status flag and an observed Pool Throughput (PT) figure — against a configurable threshold, producing a priority-encoded decision (`CONTINUE`, `SWITCH_PT`, `SWITCH_BCV`) entirely in hardware. A six-mux decoupler isolates the Reconfigurable Partition during a swap to guarantee glitch-free reconfiguration.
