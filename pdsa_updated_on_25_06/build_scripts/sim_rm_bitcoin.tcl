# ModelSim DO file for rm_bitcoin simulation
# Result: log written to D:/pdsa_fpga_dfx_build/output/sim_rm_bitcoin.log

set rtl_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/rtl
set out_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/simulation

file mkdir ${out_dir}
cd ${out_dir}
vlib work_btc
vmap work_btc work_btc
vlog -sv -work work_btc +acc ${rtl_dir}/sha256_core_baseline.sv
vlog -sv -work work_btc +acc ${rtl_dir}/sha256d_pipe_engine_hp.sv
vlog -sv -work work_btc +acc ${rtl_dir}/sha256d_multi_engine_hp.sv
vlog -sv -work work_btc +acc ${rtl_dir}/rm_bitcoin.sv
vlog -sv -work work_btc +acc ${rtl_dir}/rm_bitcoin_wrapper.v
vlog -sv -work work_btc +acc ${rtl_dir}/tb_rm_bitcoin.sv

vsim -c work_btc.tb_rm_bitcoin -do "run -all" -logfile ${out_dir}/sim_rm_bitcoin.log
quit -sim
quit -f
