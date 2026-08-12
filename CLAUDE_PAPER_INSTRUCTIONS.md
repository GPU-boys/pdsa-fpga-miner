# Instructions: Correct TCAS-II v8 Paper to 20-Engine Configuration

## Overview
The v8 paper incorrectly claims 24 SHA-256d engines. The actual synthesized and measured design has **20 engines**. Correct all references and recalculate hashrate/efficiency accordingly. Kaspa (SHA-3-256 Keccak) values remain **unchanged**.

## Source Data
All numbers come from the actual 20-engine build (`PDSA_FPGA_Full_Report_v2.docx`), which is the ONLY build that was ever synthesized and routed.

## What Changes

### 1. Engine Count
Every reference to "24-engine" in Bitcoin/SHA-256d context → **20-engine**.
- `NUM_ENGINES=24` → `NUM_ENGINES=20`
- `N = 24` (Bitcoin context) → `N = 20`
- `24 parallel SHA-256d engines` → `20 parallel SHA-256d engines`
- Subsection title: `"24-Engine SHA-256d Pipeline"` → `"20-Engine SHA-256d Pipeline"`

### 2. Hashrate
- `18.05 Mhash/s` → `15.04 Mhash/s` (calculation: 20/133 × 100 = 15.04)
- Formula: `(24/133)` → `(20/133)`

### 3. Power (Table II — Bitcoin column)
| Metric | Old (paper claim) | New (from v2 report) |
|---|---|---|
| Total on-chip power | 3.082 W | **1.235 W** |
| Dynamic power | 2.780 W | **0.942 W** |
| Device static power | 0.303 W | **0.293 W** |
| Est. junction temperature | 32.2 °C | **27.9 °C** |

### 4. Efficiency
- `5.86 Mhash/s/W` → **`12.18 Mhash/s/W`** (calculation: 15.04 / 1.235 = 12.18)

### 5. Resource Text Corrections (Table III unchanged — numbers were correct for 20 engines!)
- `"24 parallel SHA-256d engines"` → `"20 parallel SHA-256d engines"`
- `"each engine accounts for approximately 2,332 LUTs and 2,816 flip-flops"` → `"approximately 2,719 LUTs and 3,319 flip-flops"`
- `"static shell occupies approximately 2,145 LUTs (1.83%)"` → `"occupies 3,738 LUTs (3.19%)"`

### 6. Timing (Table II — Bitcoin column — UNCHANGED)
- WNS +0.562 ns — CORRECT for 20 engines. Do NOT change.
- Data path 9.047 ns, route 8.780 ns — CORRECT. Do NOT change.

### 7. Performance Comparison (Table V — Bitcoin row)
| Metric | Old | New |
|---|---|---|
| Hashrate | 18.05 Mhash/s | **15.04 Mhash/s** |
| Power | 3.08 W | **1.24 W** |
| Efficiency | 5.86 | **12.18** |

### 8. Table IV (Hashrate & Efficiency — Bitcoin row)
| Metric | Old | New |
|---|---|---|
| Engine count | 24 (round-robin) | **20 (round-robin)** |
| Hashrate | 18.05 Mhash/s | **15.04 Mhash/s** |
| Power | 3.082 W | **1.235 W** |
| Efficiency | 5.86 Mhash/s/W | **12.18 Mhash/s/W** |

### 9. Per-Engine Pipeline Description (Section VI-A)
Replace:
`"The synthesized bitstream instantiates N = 24 engines: the module default in rm_bitcoin.sv is 20, and the top-level wrapper pdsa_fpga_dfx_top.sv explicitly instantiates rm_bitcoin with NUM_ENGINES set to 24; the Vivado build script additionally passes -generic NUM_ENGINES=24 during out-of-context synthesis. With N = 24 and 133 cycles per hash, steady-state throughput is N/133 hashes per cycle."`

With:
`"The synthesized bitstream instantiates N = 20 engines, each a two-phase FSM completing 133 clock cycles per double-hash. With N = 20 and 133 cycles per hash, steady-state throughput is N/133 hashes per cycle."`

### 10. Fig. 6 Caption
- `"round-robin dispatch across N = 24 engines (bottom)"` → `"round-robin dispatch across N = 20 engines (bottom)"`

Also update the diagram graphic itself if feasible — change "24" labels to "20" in the round-robin timing diagram.

### 11. Static Shell References
- `"static shell's 2,145-LUT footprint"` → `"static shell's 3,738-LUT footprint"`
- `"The static shell occupies an estimated 2,145 LUTs (1.8%)"` → `"The static shell occupies 3,738 LUTs (4.1%)"`

### 12. Discussion Text (Section VIII-A)
- `"5.86 Mhash/s/W"` → `"12.18 Mhash/s/W"`
- `"this design's 18.05 Mhash/s"` → `"this design's 15.04 Mhash/s"`
- `"A single Kria KV260 draws under 3.1 W total on-chip for either configuration"` → `"A single Kria KV260 draws under 1.24 W total on-chip for the SHA-256d configuration"`

### 13. PDSA Overhead (Section VIII-B)
- `"static shell's 2,145-LUT footprint"` → `"static shell's 3,738-LUT footprint"`

### 14. Conclusion
- `"24-engine SHA-256d pipeline"` → `"20-engine SHA-256d pipeline"`
- `"18.05 Mhash/s at 3.082 W (5.86 Mhash/s/W)"` → `"15.04 Mhash/s at 1.235 W (12.18 Mhash/s/W)"`

## Kaspa Values — DO NOT CHANGE
- 4.0 Mhash/s, 2.529 W, 1.58 Mhash/s/W — unchanged
- 4,328 LUTs (3.70%), 3,454 regs (1.47%) — unchanged
- WNS +1.600 ns — unchanged
- All Keccak-f[1600] 24-round references — these are permutation rounds, NOT engine count

## Search-and-Replace Summary

| Find | Replace | Notes |
|---|---|---|
| `24-engine` (Bitcoin context) | `20-engine` | Not Keccak 24-round |
| `NUM_ENGINES=24` | `NUM_ENGINES=20` | |
| `NUM_ENGINES set to 24` | `NUM_ENGINES set to 20` | |
| `N = 24` (Bitcoin context) | `N = 20` | |
| `18.05 Mhash/s` | `15.04 Mhash/s` |  |
| `5.86 Mhash/s/W` | `12.18 Mhash/s/W` | |
| `3.082 W` (Bitcoin power) | `1.235 W` | Not Kaspa 2.529 W |
| `2.780 W` | `0.942 W` | |
| `0.303 W` | `0.293 W` | |
| `32.2 °C` | `27.9 °C` | |
| `24 parallel` | `20 parallel` | |
| `2,332 LUTs` | `2,719 LUTs` | |
| `2,816 flip-flops` | `3,319 flip-flops` | |
| `2,145 LUTs` | `3,738 LUTs` | |
| `1.83%` | `3.19%` | |
| `1.8%` | `4.1%` | |
| `3.1 W total on-chip for either configuration` | `1.24 W total on-chip for the SHA-256d configuration` | |

## Figures to Update
- **Fig. 6**: Bottom label "N = 24" → "N = 20" in the round-robin dispatch diagram. The engine FSM timing (top) stays the same.
- All other figures: unchanged.
