# =============================================================================
# vivado_bd_dfx_project.tcl — PDSA-FPGA DFX on KV260
# Uses launch_runs for BD synthesis, manual in-process impl for DFX persistence
# =============================================================================

set project_name  "pdsa_fpga_bd_dfx"
set project_dir   "D:/pdsa_fpga_dfx_build/project_bd_dfx"
set rtl_dir       "D:/pdsa_updated_on_2_6/rtl"
set constr_dir    "D:/pdsa_updated_on_2_6/constraints"
set output_dir    "D:/pdsa_updated_on_2_6/bitstream"
set fpga_part     "xck26-sfvc784-2lv-c"

file mkdir ${output_dir}

# ============================================================
# STEP 1: Create project
# ============================================================
create_project ${project_name} ${project_dir} -part ${fpga_part} -force

# ============================================================
# STEP 2: Add DFX RTL sources
# ============================================================
add_files -norecurse [list \
  ${rtl_dir}/pdsa_fpga_dfx_top.sv       \
  ${rtl_dir}/pdsa_static_shell.sv       \
  ${rtl_dir}/axi_lite_csr.sv            \
  ${rtl_dir}/rm_bitcoin.sv              \
  ${rtl_dir}/sha256d_multi_engine_hp.sv \
  ${rtl_dir}/sha256d_pipe_engine_hp.sv  \
  ${rtl_dir}/sha256_core_baseline.sv    \
  ${rtl_dir}/pdsa_fpga_dfx_top_wrapper.v \
]

# ============================================================
# STEP 3: Block Design
# ============================================================
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

connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
               [get_bd_pins pdsa_top_0/clk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
               [get_bd_pins axi_smc/aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
               [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
               [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_lpd_aclk]
connect_bd_net [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
               [get_bd_pins pdsa_top_0/rst_n]

connect_bd_net [get_bd_pins pdsa_top_0/irq_found] \
               [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

assign_bd_address [get_bd_addr_segs {pdsa_top_0/s_axi/reg0}]
set_property offset 0xA0000000 [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_pdsa_top_0_reg0}]
set_property range 64K [get_bd_addr_segs {zynq_ultra_ps_e_0/Data/SEG_pdsa_top_0_reg0}]

validate_bd_design
save_bd_design
generate_target all [get_files pdsa_system.bd]
make_wrapper -files [get_files pdsa_system.bd] -top
add_files -norecurse ${project_dir}/${project_name}.srcs/sources_1/bd/pdsa_system/hdl/pdsa_system_wrapper.v
set_property top pdsa_system_wrapper [current_fileset]

# ============================================================
# STEP 4: Constraints
# ============================================================
add_files -fileset constrs_1 -norecurse "${constr_dir}/pdsa_kv260.xdc"
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]

# ============================================================
# STEP 5: Synthesize via launch_runs (handles BD IP correctly)
# ============================================================
reset_run synth_1
set_property -dict [list STRATEGY "Vivado Synthesis Defaults" FLOW "Vivado Synthesis 2025"] [get_runs synth_1]
launch_runs synth_1 -jobs 4
wait_on_run synth_1

# ============================================================
# STEP 6: Open synth design, set DFX properties, save checkpoint
# ============================================================
open_run synth_1 -name synth_1

# Find RP cell via multiple patterns
set rp_cell [get_cells -hierarchical -filter {NAME =~ *pdsa_top_0/inst/u_top/u_rp}]
if {$rp_cell eq ""} {
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}]
}
if {$rp_cell eq ""} {
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
}
if {$rp_cell eq ""} {
    set all [get_cells -hierarchical -regexp .*rp.*]
    puts "Cells matching .*rp.*: $all"
    error "Could not find u_rp in synthesized design"
}
puts "Found RP cell: $rp_cell"
set_property HD.RECONFIGURABLE 1 $rp_cell

create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y299}

write_checkpoint -force ${output_dir}/post_synth_dfx.dcp
report_utilization -file ${output_dir}/utilization_synth.rpt

# ============================================================
# STEP 7: Implement manually in-process (DFX props persist)
# ============================================================
puts "Starting opt_design..."
opt_design
puts "Starting place_design..."
place_design
puts "Starting phys_opt_design..."
phys_opt_design
puts "Starting route_design..."
route_design
puts "Starting post-route phys_opt..."
phys_opt_design

write_checkpoint -force ${output_dir}/post_route_dfx_full_btc.dcp
report_utilization -file ${output_dir}/utilization_dfx.rpt
report_timing -file ${output_dir}/timing_dfx.rpt
report_power -file ${output_dir}/power_dfx.rpt

# ============================================================
# STEP 8: Write bitstreams (rm_bitcoin active)
# ============================================================
write_bitstream -force -file ${output_dir}/pdsa_full.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full.bit
puts "Full bitstream written"

write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_bitcoin.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_bitcoin.bit
puts "rm_bitcoin partial bitstream written"

close_design

# ============================================================
# STEP 9: Synthesize rm_kaspa standalone
# ============================================================
puts "Starting rm_kaspa standalone synthesis..."
create_project -force pdsa_dfx_rm_kaspa ${output_dir}/vivado_rm_kaspa -part ${fpga_part}
add_files -norecurse [list \
  ${rtl_dir}/rm_kaspa.sv              \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv \
]
set_property top rm_kaspa [current_fileset]
update_compile_order -fileset sources_1
synth_design -top rm_kaspa -part ${fpga_part} -flatten_hierarchy rebuilt
write_checkpoint -force ${output_dir}/post_synth_rm_kaspa.dcp
report_utilization -file ${output_dir}/utilization_rm_kaspa.rpt
close_project

# ============================================================
# STEP 10: Read rm_kaspa into RP, re-route, write bitstreams
# ============================================================
puts "Swapping rm_kaspa into RP..."
open_checkpoint ${output_dir}/post_route_dfx_full_btc.dcp

set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
if {$rp_cell eq ""} {
    error "Could not find u_rp in post-route checkpoint (step 10)"
}
puts "RP cell: $rp_cell"

# Must set HD.RECONFIGURABLE again (checkpoint may not preserve it)
set_property HD.RECONFIGURABLE 1 $rp_cell

read_checkpoint -cell $rp_cell ${output_dir}/post_synth_rm_kaspa.dcp
puts "RM checkpoint loaded"

opt_design
place_design
phys_opt_design
route_design
phys_opt_design

write_checkpoint -force ${output_dir}/post_route_dfx_full_kaspa.dcp
report_utilization -file ${output_dir}/utilization_dfx_kaspa.rpt

# Full bitstream with rm_kaspa
write_bitstream -force -file ${output_dir}/pdsa_full_kaspa.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full_kaspa.bit
puts "Full bitstream (rm_kaspa) written"

# Partial bitstream for rm_kaspa
write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_kaspa.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_kaspa.bit
puts "rm_kaspa partial bitstream written"

puts "\n=== DFX BD Build Complete ==="
puts "Full bitstream (rm_bitcoin):      ${output_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):        ${output_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_bitcoin):   ${output_dir}/pdsa_rm_bitcoin.bit"
puts "Partial bitstream (rm_kaspa):     ${output_dir}/pdsa_rm_kaspa.bit"

close_project
puts "\n=== DONE ==="
