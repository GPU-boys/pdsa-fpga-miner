# =============================================================================
# vivado_bd_dfx_separate_rp.tcl — PDSA-FPGA BD DFX with RM as separate BD cell
# =============================================================================

set rtl_dir       "D:/pdsa_updated_on_2_6/rtl"
set constr_dir    "D:/pdsa_updated_on_2_6/constraints"
set output_dir    "D:/pdsa_updated_on_2_6/bitstream"
set proj_dir      "D:/pdsa_updated_on_2_6/build_scripts/project_bd_dfx_sep"
set fpga_part     "xck26-sfvc784-2lv-c"

file mkdir ${output_dir}

# ============================================================
# PHASE 1: Create project + BD with separate RP cell
# ============================================================
puts "=== PHASE 1: Create project + BD ==="
create_project pdsa_fpga_bd_dfx_sep ${proj_dir} -part ${fpga_part} -force

# Add ALL source files (static + RM — both needed for BD module refs and OOC synth)
add_files -norecurse [list \
  ${rtl_dir}/pdsa_static_top.sv           \
  ${rtl_dir}/pdsa_static_top_wrapper.v    \
  ${rtl_dir}/pdsa_static_shell.sv         \
  ${rtl_dir}/axi_lite_csr.sv              \
  ${rtl_dir}/rm_bitcoin.sv                \
  ${rtl_dir}/rm_bitcoin_wrapper.v         \
  ${rtl_dir}/rm_kaspa.sv                  \
  ${rtl_dir}/sha256d_multi_engine_hp.sv   \
  ${rtl_dir}/sha256d_pipe_engine_hp.sv    \
  ${rtl_dir}/sha256d_real_engine.sv       \
  ${rtl_dir}/sha256_core_baseline.sv      \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv   \
]

create_bd_design "pdsa_system"

# Zynq PS
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__IRQ0 {1} \
] [get_bd_cells zynq_ultra_ps_e_0]

# AXI SmartConnect
create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc
set_property CONFIG.NUM_SI {1} [get_bd_cells axi_smc]
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_smc]

# Static shell (NO RM inside)
create_bd_cell -type module -reference pdsa_static_top_wrapper static_0

# RM as SEPARATE BD cell (not inside static!)
create_bd_cell -type module -reference rm_bitcoin_wrapper rm_0

# Connect PS → SmartConnect → Static
connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
                    [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
                    [get_bd_intf_pins static_0/s_axi]

# Clock and reset
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins static_0/clk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins rm_0/clk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins static_0/rst_n]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins rm_0/rst_n]

# dpr_in_progress is driven internally by csr_decouple inside static shell
# (no external connection needed — removed external port from RTL)

# Interrupt
connect_bd_net [get_bd_pins static_0/irq_found] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

# === Connect Static → RM (RP interface) ===
connect_bd_net [get_bd_pins static_0/rp_start]      [get_bd_pins rm_0/rp_start]
connect_bd_net [get_bd_pins static_0/rp_stop]       [get_bd_pins rm_0/rp_stop]
connect_bd_net [get_bd_pins static_0/rp_job_data]   [get_bd_pins rm_0/rp_job_data]
connect_bd_net [get_bd_pins static_0/rp_midstate]   [get_bd_pins rm_0/rp_midstate]
connect_bd_net [get_bd_pins static_0/rp_target]     [get_bd_pins rm_0/rp_target]
connect_bd_net [get_bd_pins static_0/rp_start_nonce] [get_bd_pins rm_0/rp_start_nonce]
connect_bd_net [get_bd_pins static_0/rp_algo_id]    [get_bd_pins rm_0/rp_algo_id]
connect_bd_net [get_bd_pins static_0/rp_hash_out]   [get_bd_pins rm_0/rp_hash_out]
connect_bd_net [get_bd_pins static_0/rp_nonce_out]  [get_bd_pins rm_0/rp_nonce_out]
connect_bd_net [get_bd_pins static_0/rp_found]      [get_bd_pins rm_0/rp_found]
connect_bd_net [get_bd_pins static_0/rp_hash_count] [get_bd_pins rm_0/rp_hash_count]
connect_bd_net [get_bd_pins static_0/rp_busy]       [get_bd_pins rm_0/rp_busy]
connect_bd_net [get_bd_pins static_0/rp_valid_out]  [get_bd_pins rm_0/rp_valid_out]

# Address mapping
assign_bd_address [get_bd_addr_segs {static_0/s_axi/reg0}]
set_property offset 0xA0000000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_static_0_reg0}]
set_property range 64K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_static_0_reg0}]

validate_bd_design
save_bd_design
generate_target all [get_files pdsa_system.bd]
make_wrapper -files [get_files pdsa_system.bd] -top
add_files -norecurse D:/pdsa_fpga_dfx_build/project_bd_dfx_sep/pdsa_fpga_bd_dfx_sep.gen/sources_1/bd/pdsa_system/hdl/pdsa_system_wrapper.v
set_property top pdsa_system_wrapper [current_fileset]

# ============================================================
# PHASE 2: Constraints
# ============================================================
puts "=== PHASE 2: Constraints ==="
add_files -fileset constrs_1 -norecurse "${constr_dir}/pdsa_kv260.xdc"
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# ============================================================
# PHASE 3: Set DFX properties on RM cell
# ============================================================
puts "=== PHASE 3: Set DFX properties on RM cell ==="
set rp_bd_cell [get_bd_cells rm_0]
set_property HD.RECONFIGURABLE 1 $rp_bd_cell
puts "HD.RECONFIGURABLE set on RM BD cell"

# ============================================================
# PHASE 4: Synthesize
# ============================================================
puts "=== PHASE 4: Synthesize ==="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1

open_run synth_1 -name synth_1

# Find RP cell (now a separate BD cell instance at top level)
set rp_cell [get_cells -hierarchical -filter {NAME =~ *rm_0}]
if {$rp_cell eq ""} {
    set rp_cell [get_cells -hierarchical -filter {NAME =~ */rm_0}]
}
if {$rp_cell eq ""} {
    error "Could not find rm_0 cell"
}
puts "Found RP cell: $rp_cell"

# Set HD.RECONFIGURABLE on physical cell (also ensures BD property is applied)
set_property HD.RECONFIGURABLE 1 $rp_cell
set hd_val [get_property HD.RECONFIGURABLE $rp_cell]
puts "HD.RECONFIGURABLE on RP cell: '${hd_val}'"

# Create Pblock for the RP cell
set_property IS_LOC_FIXED 1 $rp_cell
create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
catch { resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X89Y249} }

write_checkpoint -force ${output_dir}/post_synth_sep.dcp
report_utilization -file ${output_dir}/utilization_synth_sep.rpt

# ============================================================
# PHASE 5: Implement config 1 (rm_bitcoin)
# ============================================================
puts "=== PHASE 5: Implement config 1 ==="
opt_design
place_design
phys_opt_design
route_design
phys_opt_design

write_checkpoint -force ${output_dir}/post_route_sep_btc.dcp
report_utilization -file ${output_dir}/utilization_sep_btc.rpt
report_timing -file ${output_dir}/timing_sep_btc.rpt
report_power -file ${output_dir}/power_sep_btc.rpt

write_bitstream -force -file ${output_dir}/pdsa_full_sep_btc.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full_sep_btc.bit
puts "Full bitstream (rm_bitcoin) written"

write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_sep_btc.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_sep_btc.bit
puts "rm_bitcoin partial bitstream written"

close_design
close_project

# ============================================================
# PHASE 6: Synthesize rm_kaspa standalone
# ============================================================
puts "=== PHASE 6: Synthesize rm_kaspa ==="
create_project -force pdsa_dfx_rm_kaspa ${output_dir}/vivado_rm_kaspa_sep -part ${fpga_part}
add_files -norecurse [list \
  ${rtl_dir}/rm_kaspa.sv              \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv \
]
set_property top rm_kaspa [current_fileset]
synth_design -top rm_kaspa -part ${fpga_part} -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force ${output_dir}/post_synth_rm_kaspa_sep.dcp
report_utilization -file ${output_dir}/utilization_rm_kaspa_sep.rpt
close_project

# ============================================================
# PHASE 7: Implement config 2 (rm_kaspa swapped in)
# ============================================================
puts "=== PHASE 7: Implement config 2 (rm_kaspa) ==="
open_project ${proj_dir}/pdsa_fpga_bd_dfx_sep.xpr
open_run synth_1 -name synth_1

set rp_cell [get_cells -hierarchical -filter {NAME =~ *rm_0}]
if {$rp_cell eq ""} { error "Could not find rm_0" }
puts "RP cell: $rp_cell"

# For swap: convert RM cell to black box (OOC boundary = correct ports)
set_property HD.RECONFIGURABLE 1 $rp_cell
set_property IS_LOC_FIXED 1 $rp_cell
catch { delete_pblock pblock_u_rp }
create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
catch { resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X89Y249} }

update_design -cells $rp_cell -black_box
puts "RP cell converted to black box"

read_checkpoint -cell $rp_cell ${output_dir}/post_synth_rm_kaspa_sep.dcp
puts "rm_kaspa loaded into RP"

set rp_cell [get_cells -hierarchical -filter {NAME =~ *rm_0}]

opt_design
place_design
phys_opt_design
route_design
phys_opt_design

write_checkpoint -force ${output_dir}/post_route_sep_kaspa.dcp
report_utilization -file ${output_dir}/utilization_sep_kaspa.rpt
report_timing -file ${output_dir}/timing_sep_kaspa.rpt
report_power -file ${output_dir}/power_sep_kaspa.rpt

write_bitstream -force -file ${output_dir}/pdsa_full_sep_kaspa.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full_sep_kaspa.bit
puts "Full bitstream (rm_kaspa) written"

set rp_cell [get_cells -hierarchical -filter {NAME =~ *rm_0}]
write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_sep_kaspa.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_sep_kaspa.bit
puts "rm_kaspa partial bitstream written"

close_project

puts "\n=== DFX Separate-RP Build Complete ==="
puts "Config 1 (rm_bitcoin):"
puts "  Full:      ${output_dir}/pdsa_full_sep_btc.bit"
puts "  Partial:   ${output_dir}/pdsa_rm_sep_btc.bit"
puts "Config 2 (rm_kaspa):"
puts "  Full:      ${output_dir}/pdsa_full_sep_kaspa.bit"
puts "  Partial:   ${output_dir}/pdsa_rm_sep_kaspa.bit"

close_project
puts "\n=== DONE ==="
