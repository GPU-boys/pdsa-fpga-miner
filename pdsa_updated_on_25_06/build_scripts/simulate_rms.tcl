# =============================================================================
# simulate_rms.tcl — Simulation of rm_bitcoin and rm_kaspa with Vivado Simulator
# Results saved to D:/pdsa_fpga_dfx_build/output/
# =============================================================================

set rtl_dir   "F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/rtl"
set output_dir "F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/simulation"

# ============================================================
# SIMULATION 1: rm_bitcoin
# ============================================================
puts "=== SIMULATION 1: rm_bitcoin ==="

# Compile
cd ${output_dir}
file mkdir ${output_dir}/xsim_btc
cd ${output_dir}/xsim_btc

eval xvlog --work work_btc --sv ${rtl_dir}/sha256_core_baseline.sv ${rtl_dir}/sha256d_pipe_engine_hp.sv ${rtl_dir}/sha256d_multi_engine_hp.sv ${rtl_dir}/rm_bitcoin.sv ${rtl_dir}/rm_bitcoin_wrapper.v ${rtl_dir}/tb_rm_bitcoin.sv

xelab --debug typical work_btc.tb_rm_bitcoin -s tb_rm_bitcoin
xsim tb_rm_bitcoin --runall --log ${output_dir}/sim_rm_bitcoin.log 2>&1

puts "=== rm_bitcoin simulation complete ==="
puts "Results: ${output_dir}/sim_rm_bitcoin.log"

# ============================================================
# SIMULATION 2: rm_kaspa
# ============================================================
puts "=== SIMULATION 2: rm_kaspa ==="

cd ${output_dir}
file mkdir ${output_dir}/xsim_kaspa
cd ${output_dir}/xsim_kaspa

eval xvlog --work work_kaspa --sv ${rtl_dir}/sha3_256_pipe_engine_hp.sv ${rtl_dir}/rm_kaspa.sv ${rtl_dir}/rm_kaspa_wrapper.v ${rtl_dir}/tb_rm_kaspa.sv

xelab --debug typical work_kaspa.tb_rm_kaspa -s tb_rm_kaspa
xsim tb_rm_kaspa --runall --log ${output_dir}/sim_rm_kaspa.log 2>&1

puts "=== rm_kaspa simulation complete ==="
puts "Results: ${output_dir}/sim_rm_kaspa.log"

# ============================================================
# Summary
# ============================================================
puts ""
puts "=== Simulation Summary ==="
puts "rm_bitcoin: ${output_dir}/sim_rm_bitcoin.log"
puts "rm_kaspa:   ${output_dir}/sim_rm_kaspa.log"
puts "=== DONE ==="
