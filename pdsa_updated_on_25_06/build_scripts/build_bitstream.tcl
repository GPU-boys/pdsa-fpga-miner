# =============================================================================
# PDSA-FPGA DFX Build Script
# Uses -flatten_hierarchy none (preserves 1551-port RTL interface)
# black-box + read_checkpoint for RM swap
# =============================================================================
set top_dir    "D:/Projects/Crypto_miner_final_updated_on_18_06/New_updated/pdsa_updated_on_3_6_newv"
set rtl_dir    "${top_dir}/rtl"
set xdc_dir    "${top_dir}/constraints"
set out_dir    "${top_dir}/bitstream"
set part       "xck26-sfvc784-2LV-c"
set top_module "pdsa_fpga_dfx_top"
set num_eng    "20"

file mkdir ${out_dir}

# ============================
# STEP 1: Synthesize full design (static + rm_bitcoin)
# ============================
create_project -force pdsa_dfx ${out_dir}/vivado_project -part ${part}

add_files -norecurse [list \
  ${rtl_dir}/pdsa_fpga_dfx_top.sv       \
  ${rtl_dir}/pdsa_static_shell.sv       \
  ${rtl_dir}/pdsa_static_top.sv         \
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

synth_design -top ${top_module} -part ${part} -flatten_hierarchy none
set_property HD.RECONFIGURABLE 1 [get_cells u_rp]
write_checkpoint -force ${out_dir}/post_synth_static.dcp

# ============================
# STEP 2: Synthesize rm_bitcoin standalone for RM checkpoint
# ============================
synth_design -top rm_bitcoin -part ${part} -mode out_of_context -generic NUM_ENGINES=${num_eng}
write_checkpoint -force ${out_dir}/post_synth_rm_bitcoin.dcp
report_utilization -file ${out_dir}/utilization_rm_bitcoin.rpt
puts "=== rm_bitcoin synthesis complete ==="

# ============================
# STEP 3: Implement static + rm_bitcoin
# ============================
open_checkpoint ${out_dir}/post_synth_static.dcp

update_design -cell u_rp -black_box
read_checkpoint -cell u_rp ${out_dir}/post_synth_rm_bitcoin.dcp
set_property HD.RECONFIGURABLE 1 [get_cells u_rp]
set_property SEVERITY {Warning} [get_drc_checks KLOC-1]

create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] [get_cells u_rp]
resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y239}
resize_pblock pblock_u_rp -add {BUFGCE_X0Y0:BUFGCE_X0Y95}

opt_design -retarget -propconst -sweep -bram_power_opt -remap -shift_register_opt -dsp_register_opt
place_design -directive ExtraPostPlacementOpt
phys_opt_design
route_design -directive NoTimingRelaxation
write_checkpoint -force ${out_dir}/post_route_full.dcp
report_utilization -file ${out_dir}/utilization_static_full.rpt
report_timing -file ${out_dir}/timing_static_full.rpt

set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks KLOC-1]
write_bitstream -force -file ${out_dir}/pdsa_full.bit

puts "=== Full bitstream (rm_bitcoin) generated ==="

# ============================
# STEP 4: Synthesize rm_kaspa standalone for RM checkpoint
# ============================
close_project

create_project -force pdsa_dfx_rm2 ${out_dir}/vivado_project_rm2 -part ${part}
add_files -norecurse [list \
  ${rtl_dir}/rm_kaspa.sv              \
  ${rtl_dir}/sha3_256_pipe_engine_hp.sv \
]
set_property top rm_kaspa [current_fileset]
update_compile_order -fileset sources_1

synth_design -top rm_kaspa -part ${part} -mode out_of_context
write_checkpoint -force ${out_dir}/post_synth_rm_kaspa.dcp
report_utilization -file ${out_dir}/utilization_rm_kaspa.rpt
puts "=== rm_kaspa synthesis complete ==="

# ============================
# STEP 5: Generate partial bitstream (rm_kaspa swap)
# ============================
close_project
open_checkpoint ${out_dir}/post_route_full.dcp

# Lock static routing, then swap RM
lock_design -level placement
update_design -cell u_rp -black_box
read_checkpoint -cell u_rp ${out_dir}/post_synth_rm_kaspa.dcp
set_property HD.RECONFIGURABLE 1 [get_cells u_rp]
set_property SEVERITY {Warning} [get_drc_checks KLOC-1]

# Re-implement within the RP only (static placement is locked)
opt_design
place_design
phys_opt_design
route_design
write_checkpoint -force ${out_dir}/post_route_full_kaspa.dcp
report_utilization -file ${out_dir}/utilization_with_kaspa.rpt
report_timing -file ${out_dir}/timing_with_kaspa.rpt

set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
set_property SEVERITY {Warning} [get_drc_checks KLOC-1]
write_bitstream -force -file ${out_dir}/pdsa_full_kaspa.bit
write_bitstream -force -cell u_rp -file ${out_dir}/pdsa_rm_kaspa.bit

puts "=== DFX Build Complete ==="
puts "Full bitstream (rm_bitcoin):    ${out_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):      ${out_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_kaspa):   ${out_dir}/pdsa_rm_kaspa.bit"

close_project
exit
