# =============================================================================
# PDSA-FPGA DFX Build Script (Simplified)
# Generates:
#   1. Full bitstream (static + rm_bitcoin)
#   2. Partial bitstream: pdsa_rm_kaspa.bit/.bin
# =============================================================================
set top_dir    "D:/pdsa_fpga_dfx"
set rtl_dir    "${top_dir}/rtl"
set xdc_dir    "${top_dir}/constraints"
set out_dir    "${top_dir}/output"
set part       "xck26-sfvc784-2LV-c"
set top_module "pdsa_fpga_dfx_top"

file mkdir ${out_dir}

# === STEP 1: Synthesize Static + rm_bitcoin together ===
create_project -force pdsa_dfx ${out_dir}/vivado_project -part ${part}

add_files -norecurse [list \
  ${rtl_dir}/pdsa_fpga_dfx_top.sv       \
  ${rtl_dir}/pdsa_static_shell.sv       \
  ${rtl_dir}/axi_lite_csr.sv            \
  ${rtl_dir}/rm_bitcoin.sv              \
  ${rtl_dir}/sha256d_multi_engine_hp.sv \
  ${rtl_dir}/sha256d_pipe_engine_hp.sv  \
  ${rtl_dir}/sha256d_real_engine.sv     \
  ${rtl_dir}/sha256_core_baseline.sv    \
]
add_files -fileset constrs_1 ${xdc_dir}/pdsa_kv260.xdc
set_property top ${top_module} [current_fileset]
update_compile_order -fileset sources_1

synth_design -top ${top_module} -part ${part} -flatten_hierarchy rebuilt
set_property HD.RECONFIGURABLE 1 [get_cells u_rp]
write_checkpoint -force ${out_dir}/post_synth_static.dcp

# --- Create Pblock for reconfigurable partition u_rp ---
# We define a region covering approximately 40% of the device
# (CLBs X0Y0 to X140Y200 — adjust if DRC fails)
create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] [get_cells u_rp]
resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y299}

# === STEP 2: Open checkpoint, implement, write full bitstream ===
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force ${out_dir}/post_route_full.dcp

report_utilization -file ${out_dir}/utilization_static_full.rpt
report_timing -file ${out_dir}/timing_static_full.rpt

write_bitstream -force -file ${out_dir}/pdsa_full.bit
write_bitstream -force -bin_file -file ${out_dir}/pdsa_full.bin

puts "=== Full bitstream (rm_bitcoin) generated ==="

# === STEP 3: Synthesize rm_kaspa as a standalone module ===
close_project

create_project -force pdsa_dfx_rm ${out_dir}/vivado_project_rm -part ${part}
add_files -norecurse [list \
  ${rtl_dir}/rm_kaspa.sv              \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv \
]
set_property top rm_kaspa [current_fileset]
update_compile_order -fileset sources_1

synth_design -top rm_kaspa -part ${part} -flatten_hierarchy rebuilt
write_checkpoint -force ${out_dir}/post_synth_rm_kaspa.dcp
report_utilization -file ${out_dir}/utilization_rm_kaspa.rpt

# === STEP 4: Generate partial bitstream using pr_recombine ===
close_project
open_checkpoint ${out_dir}/post_route_full.dcp

# Read Kaspa RM into the RP cell
read_checkpoint -cell u_rp ${out_dir}/post_synth_rm_kaspa.dcp

# Re-run route on the modified design
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force ${out_dir}/post_route_full_kaspa.dcp

report_utilization -file ${out_dir}/utilization_with_kaspa.rpt
report_timing -file ${out_dir}/timing_with_kaspa.rpt

# Write full config (static + rm_kaspa)
write_bitstream -force -file ${out_dir}/pdsa_full_kaspa.bit
write_bitstream -force -bin_file -file ${out_dir}/pdsa_full_kaspa.bin

# Write partial bitstream (rm_kaspa only) for DPR
write_bitstream -force -cell u_rp -file ${out_dir}/pdsa_rm_kaspa.bit
write_bitstream -force -cell u_rp -bin_file -file ${out_dir}/pdsa_rm_kaspa.bin

# Also write rm_bitcoin partial for completeness (from the original route)
write_bitstream -force -cell u_rp -file ${out_dir}/pdsa_rm_bitcoin.bit

puts "=== DFX Build Complete ==="
puts "Full bitstream (rm_bitcoin):    ${out_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):      ${out_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_kaspa):   ${out_dir}/pdsa_rm_kaspa.bit"
puts "Partial bitstream (rm_kaspa).bin: ${out_dir}/pdsa_rm_kaspa.bin"
puts "Partial bitstream (rm_bitcoin): ${out_dir}/pdsa_rm_bitcoin.bit"

close_project
