# =============================================================================
# Continue DFX build — reuse existing synthesis result
# =============================================================================

set project_name  "pdsa_fpga_bd_dfx"
set project_dir   "D:/pdsa_fpga_dfx_build/project_bd_dfx"
set rtl_dir       "D:/pdsa_fpga_dfx_build/src/rtl"
set constr_dir    "D:/pdsa_fpga_dfx_build/src/constraints"
set output_dir    "D:/pdsa_fpga_dfx_build/output"
set fpga_part     "xck26-sfvc784-2lv-c"

file mkdir ${output_dir}

# Open existing project
open_project ${project_dir}/${project_name}.xpr

# Open synthesized design
open_run synth_1 -name synth_1

# Find RP cell
set rp_cell [get_cells -hierarchical -filter {NAME =~ *pdsa_top_0/inst/u_top/u_rp}]
if {$rp_cell eq ""} {
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_top/u_rp}]
}
if {$rp_cell eq ""} {
    set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
}
if {$rp_cell eq ""} {
    set all [get_cells -hierarchical -regexp .*]
    puts "All leaf cells: $all"
    error "Could not find u_rp in synthesis"
}
puts "Found RP cell: $rp_cell"

# Clean up any stale Pblock/properties from previous runs
if {[get_pblocks -quiet pblock_u_rp] ne ""} {
    delete_pblocks [get_pblocks pblock_u_rp]
}

# Mark as reconfigurable
set_property HD.RECONFIGURABLE 1 $rp_cell

# Create Pblock for RP with SLICE range (PL fabric only, avoids PS area)
create_pblock pblock_u_rp
add_cells_to_pblock [get_pblocks pblock_u_rp] $rp_cell
resize_pblock pblock_u_rp -add {SLICE_X0Y0:SLICE_X227Y299}

write_checkpoint -force ${output_dir}/post_synth_dfx.dcp
report_utilization -file ${output_dir}/utilization_synth.rpt

# Implement manually in-process
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

# Write bitstreams (rm_bitcoin active)
write_bitstream -force -file ${output_dir}/pdsa_full.bit
write_bitstream -force -bin_file -file ${output_dir}/pdsa_full.bit
puts "Full bitstream written"

write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_bitcoin.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_bitcoin.bit
puts "rm_bitcoin partial bitstream written"

close_design

# Synthesize rm_kaspa standalone
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

# Read rm_kaspa into RP, re-route, write bitstreams
puts "Swapping rm_kaspa into RP..."
open_checkpoint ${output_dir}/post_route_dfx_full_btc.dcp

set rp_cell [get_cells -hierarchical -filter {NAME =~ *u_rp}]
if {$rp_cell eq ""} {
    error "Could not find u_rp in post-route checkpoint"
}
puts "RP cell: $rp_cell"

# Must convert to black box before reading in alternate RM
set_property HD.RECONFIGURABLE 1 $rp_cell
update_design -cells $rp_cell -black_box
puts "RP cell converted to black box"

read_checkpoint -cell $rp_cell ${output_dir}/post_synth_rm_kaspa.dcp
puts "rm_kaspa RM checkpoint loaded into RP"

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

# Partial bitstream for rm_kaspa
write_bitstream -force -cell $rp_cell -file ${output_dir}/pdsa_rm_kaspa.bit
write_bitstream -force -cell $rp_cell -bin_file -file ${output_dir}/pdsa_rm_kaspa.bit

puts "\n=== DFX BD Build Complete ==="
puts "Full bitstream (rm_bitcoin):   ${output_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):     ${output_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_bitcoin):${output_dir}/pdsa_rm_bitcoin.bit"
puts "Partial bitstream (rm_kaspa):  ${output_dir}/pdsa_rm_kaspa.bit"

close_project
puts "\n=== DONE ==="
