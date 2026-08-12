set top_dir    "D:/Projects/Crypto_miner_final_updated_on_18_06/New_updated/pdsa_updated_on_3_6_newv"
set out_dir    "${top_dir}/bitstream"

# STEP 5: Generate partial bitstream (rm_kaspa swap)
open_checkpoint ${out_dir}/post_route_full.dcp

# Lock static routing, then swap RM
lock_design -level placement
update_design -cell u_rp -black_box
read_checkpoint -cell u_rp ${out_dir}/post_synth_rm_kaspa.dcp
set_property HD.RECONFIGURABLE 1 [get_cells u_rp]

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
write_bitstream -force -bin_file -file ${out_dir}/pdsa_full_kaspa.bit
write_bitstream -force -cell u_rp -file ${out_dir}/pdsa_rm_kaspa.bit
write_bitstream -force -cell u_rp -bin_file -file ${out_dir}/pdsa_rm_kaspa.bit

puts "=== DFX Build Complete ==="
puts "Full bitstream (rm_bitcoin):    ${out_dir}/pdsa_full.bit"
puts "Full bitstream (rm_kaspa):      ${out_dir}/pdsa_full_kaspa.bit"
puts "Partial bitstream (rm_kaspa):   ${out_dir}/pdsa_rm_kaspa.bit"

close_project
exit
