set out_dir "D:/Projects/Crypto_miner_final_updated_on_18_06/New_updated/pdsa_updated_on_3_6_newv/bitstream"

puts "=== Verifying post_route_full.dcp (rm_bitcoin) ==="
open_checkpoint ${out_dir}/post_route_full.dcp
report_drc -file ${out_dir}/drc_post_route_full.rpt
puts "DRC for post_route_full.dcp completed"
close_project

puts "=== Verifying post_route_full_kaspa.dcp (rm_kaspa) ==="
open_checkpoint ${out_dir}/post_route_full_kaspa.dcp
report_drc -file ${out_dir}/drc_post_route_full_kaspa.rpt
puts "DRC for post_route_full_kaspa.dcp completed"
close_project

puts "=== DRC verification complete ==="
exit
