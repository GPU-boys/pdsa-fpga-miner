# =============================================================================
# vivado_bd_dfx_proper.tcl — PDSA-FPGA Proper DFX build for KV260
# OOC RM synthesis + static black-box flow
# =============================================================================

set rtl_dir       "D:/pdsa_updated_on_2_6/rtl"
set constr_dir    "D:/pdsa_updated_on_2_6/constraints"
set output_dir    "D:/pdsa_updated_on_2_6/bitstream"
set fpga_part     "xck26-sfvc784-2lv-c"

file mkdir ${output_dir}

# ============================================================
# PHASE 1: Create project + BD (static sources only!)
# ============================================================
puts "=== PHASE 1: Create project + BD ==="
create_project pdsa_fpga_bd_dfx "D:/pdsa_fpga_dfx_build/project_bd_dfx" -part ${fpga_part} -force

# Only STATIC sources — NO rm_bitcoin files (so u_rp becomes black box)
add_files -norecurse [list \
  ${rtl_dir}/pdsa_fpga_dfx_top.sv       \
  ${rtl_dir}/pdsa_static_shell.sv       \
  ${rtl_dir}/axi_lite_csr.sv            \
  ${rtl_dir}/pdsa_fpga_dfx_top_wrapper.v \
]

create_bd_design "pdsa_system"
create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 zynq_ultra_ps_e_0
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__IRQ0 {1} \
] [get_bd_cells zynq_ultra_ps_e_0]

create_bd_cell -type ip -vlnv xilinx.com:ip:smartconnect:1.0 axi_smc
set_property CONFIG.NUM_SI {1} [get_bd_cells axi_smc]
set_property CONFIG.NUM_MI {1} [get_bd_cells axi_smc]
create_bd_cell -type module -reference pdsa_fpga_dfx_top_wrapper pdsa_top_0

connect_bd_intf_net [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
                    [get_bd_intf_pins axi_smc/S00_AXI]
connect_bd_intf_net [get_bd_intf_pins axi_smc/M00_AXI] \
                    [get_bd_intf_pins pdsa_top_0/s_axi]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins pdsa_top_0/clk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] [get_bd_pins pdsa_top_0/rst_n]

connect_bd_net [get_bd_pins pdsa_top_0/irq_found] [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

assign_bd_address [get_bd_addr_segs {pdsa_top_0/s_axi/reg0}]
set_property offset 0xA0000000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_pdsa_top_0_reg0}]
set_property range 64K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_pdsa_top_0_reg0}]

validate_bd_design
save_bd_design
generate_target all [get_files pdsa_system.bd]
make_wrapper -files [get_files pdsa_system.bd] -top
add_files -norecurse D:/pdsa_fpga_dfx_build/project_bd_dfx/pdsa_fpga_bd_dfx.srcs/sources_1/bd/pdsa_system/hdl/pdsa_system_wrapper.v
set_property top pdsa_system_wrapper [current_fileset]

add_files -fileset constrs_1 -norecurse "${constr_dir}/pdsa_kv260.xdc"
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# ============================================================
# PHASE 2: Synthesize static design (u_rp = black box)
# ============================================================
puts "=== PHASE 2: Synthesize static design ==="
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1 -name synth_1

set rp_cell [get_cells -hierarchical -filter {NAME =~ *pdsa_top_0/inst/u_top/u_rp}]
if {$rp_cell eq ""} { set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}] }
if {$rp_cell eq ""} { set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}] }
if {$rp_cell eq ""} { error "Could not find u_rp" }
puts "Found RP cell (black box): $rp_cell"

set bb [get_property IS_BLACKBOX $rp_cell]
puts "  IS_BLACKBOX = $bb"

set_property HD.RECONFIGURABLE 1 $rp_cell
create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y299}

write_checkpoint -force ${output_dir}/post_synth_static.dcp
report_utilization -file ${output_dir}/utilization_static_synth.rpt
puts "Static synthesis checkpoint saved"
close_design

# ============================================================
# PHASE 3: Synthesize rm_bitcoin OOC
# ============================================================
puts "=== PHASE 3: Synthesize rm_bitcoin OOC ==="
create_project -force pdsa_dfx_rm_bitcoin ${output_dir}/vivado_rm_bitcoin -part ${fpga_part}
add_files -norecurse [list \
  ${rtl_dir}/rm_bitcoin.sv              \
  ${rtl_dir}/sha256d_multi_engine_hp.sv \
  ${rtl_dir}/sha256d_pipe_engine_hp.sv  \
  ${rtl_dir}/sha256d_real_engine.sv     \
  ${rtl_dir}/sha256_core_baseline.sv    \
]
set_property top rm_bitcoin [current_fileset]
synth_design -top rm_bitcoin -part ${fpga_part} -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force ${output_dir}/post_synth_rm_bitcoin.dcp
report_utilization -file ${output_dir}/utilization_rm_bitcoin_synth.rpt
close_project

# ============================================================
# PHASE 4: Synthesize rm_kaspa OOC
# ============================================================
puts "=== PHASE 4: Synthesize rm_kaspa OOC ==="
create_project -force pdsa_dfx_rm_kaspa ${output_dir}/vivado_rm_kaspa -part ${fpga_part}
add_files -norecurse [list \
  ${rtl_dir}/rm_kaspa.sv              \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv \
]
set_property top rm_kaspa [current_fileset]
synth_design -top rm_kaspa -part ${fpga_part} -mode out_of_context -flatten_hierarchy rebuilt
write_checkpoint -force ${output_dir}/post_synth_rm_kaspa.dcp
report_utilization -file ${output_dir}/utilization_rm_kaspa_synth.rpt
close_project

# ============================================================
# Helper: implement one configuration
# ============================================================
proc implement_config {config_label rm_dcp_path out_dir} {
    puts "=== Implementing config: $config_label ==="
    
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *pdsa_top_0/inst/u_top/u_rp}]
    if {$rp_cell eq ""} { set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}] }
    if {$rp_cell eq ""} { set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}] }
    if {$rp_cell eq ""} { error "Could not find u_rp" }
    puts "RP cell: $rp_cell"
    
    set_property HD.RECONFIGURABLE 1 $rp_cell
    
    # Re-create Pblock (delete old one if it somehow persists)
    catch { delete_pblock pblock_u_rp }
    create_pblock pblock_u_rp
    add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
    resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y299}
    
    read_checkpoint -cell $rp_cell $rm_dcp_path
    puts "  RM checkpoint loaded"
    
    # Re-get cell handle after read_checkpoint (old handle may be stale)
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
    
    opt_design
    place_design
    phys_opt_design
    route_design
    phys_opt_design
    
    write_checkpoint -force ${out_dir}/post_route_dfx_full_${config_label}.dcp
    report_utilization -file ${out_dir}/utilization_dfx_${config_label}.rpt
    report_timing -file ${out_dir}/timing_dfx_${config_label}.rpt
    report_power -file ${out_dir}/power_dfx_${config_label}.rpt
    
    # Full bitstream
    write_bitstream -force -file ${out_dir}/pdsa_full_${config_label}.bit
    write_bitstream -force -bin_file -file ${out_dir}/pdsa_full_${config_label}.bit
    puts "  Full bitstream written"
    
    # Partial bitstream (re-get cell handle for safety)
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
    write_bitstream -force -cell $rp_cell -file ${out_dir}/pdsa_rm_${config_label}.bit
    write_bitstream -force -cell $rp_cell -bin_file -file ${out_dir}/pdsa_rm_${config_label}.bit
    puts "  Partial bitstream written"
    
    close_design
}

# ============================================================
# PHASE 5: Implement config 1 (rm_bitcoin)
# ============================================================
puts "=== PHASE 5: Implement config 1 (rm_bitcoin) ==="
open_project D:/pdsa_fpga_dfx_build/project_bd_dfx/pdsa_fpga_bd_dfx.xpr
open_run synth_1 -name synth_1
implement_config "btc" ${output_dir}/post_synth_rm_bitcoin.dcp ${output_dir}

# ============================================================
# PHASE 6: Implement config 2 (rm_kaspa)
# ============================================================
puts "=== PHASE 6: Implement config 2 (rm_kaspa) ==="
open_project D:/pdsa_fpga_dfx_build/project_bd_dfx/pdsa_fpga_bd_dfx.xpr
open_run synth_1 -name synth_1
implement_config "kaspa" ${output_dir}/post_synth_rm_kaspa.dcp ${output_dir}

# ============================================================
# PHASE 7: Write XSA for Vitis / Petalinux
# ============================================================
puts "=== PHASE 7: Write XSA ==="
# Re-open with the btc config (last implemented) to get static+RM
open_project D:/pdsa_fpga_dfx_build/project_bd_dfx/pdsa_fpga_bd_dfx.xpr
open_run synth_1 -name synth_1
write_hw_platform -fixed -force -include_bit -file ${output_dir}/pdsa_dfx.xsa
puts "XSA written: ${output_dir}/pdsa_dfx.xsa"
close_project

puts "\n========================================"
puts "=== DFX Build Complete ==="
puts "XSA:        ${output_dir}/pdsa_dfx.xsa"
puts "Config 1 (rm_bitcoin):"
puts "  Full:      ${output_dir}/pdsa_full_btc.bit"
puts "  Partial:   ${output_dir}/pdsa_rm_btc.bit"
puts "Config 2 (rm_kaspa):"
puts "  Full:      ${output_dir}/pdsa_full_kaspa.bit"
puts "  Partial:   ${output_dir}/pdsa_rm_kaspa.bit"
puts "========================================"
