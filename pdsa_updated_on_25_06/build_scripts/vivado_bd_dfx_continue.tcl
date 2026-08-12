# =============================================================================
# Continue DFX build from checkpoint — write partials + rm_kaspa swap
# =============================================================================

set output_dir   "D:/pdsa_fpga_dfx_build/output"
set rtl_dir      "D:/pdsa_fpga_dfx_build/src/rtl"
set fpga_part    "xck26-sfvc784-2lv-c"

# STEP A: Open routed checkpoint, write bin + rm_bitcoin partial
open_checkpoint ${output_dir}/post_route_dfx_full_btc.dcp

# Write .bin (binary) — the -bin_file flag adds .bin alongside .bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full.bit

# Find RP cell
set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}]
if {$rp_cell eq ""} {
    error "Could not find u_rp in post-route checkpoint"
}
puts "Found RP cell: $rp_cell"

# Write partial bitstream for rm_bitcoin (from the routed design)
write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_bitcoin.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_bitcoin.bit
puts "rm_bitcoin partial bitstream written"

close_design

# STEP B: Synthesize rm_kaspa standalone (OOC)
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

# STEP C: Read rm_kaspa into RP, re-route, write bitstreams
open_checkpoint ${output_dir}/post_route_dfx_full_btc.dcp

set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}]
if {$rp_cell eq ""} {
    error "Could not find u_rp in post-route checkpoint (STEP C)"
}
puts "Reading rm_kaspa into RP cell: $rp_cell"
read_checkpoint -cell $rp_cell ${output_dir}/post_synth_rm_kaspa.dcp

opt_design
place_design
phys_opt_design
route_design

write_checkpoint -force ${output_dir}/post_route_dfx_full_kaspa.dcp
report_utilization -file ${output_dir}/utilization_dfx_kaspa.rpt

# Full bitstream with rm_kaspa
write_bitstream -force -file ${output_dir}/pdsa_full_kaspa.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full_kaspa.bit

# Partial bitstream for rm_kaspa
write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_kaspa.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_kaspa.bit

puts "\n=== DFX BD Build Complete ==="
puts "Full bitstream (rm_bitcoin):      ${output_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):        ${output_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_bitcoin):   ${output_dir}/pdsa_rm_bitcoin.bit"
puts "Partial bitstream (rm_kaspa):     ${output_dir}/pdsa_rm_kaspa.bit"
puts "Reports:"
puts "  Utilization: ${output_dir}/utilization_dfx.rpt"
puts "  Timing:      ${output_dir}/timing_dfx.rpt"
puts "  Power:       ${output_dir}/power_dfx.rpt"

close_project
puts "\n=== DONE ==="
