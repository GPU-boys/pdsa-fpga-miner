# ModelSim DO file for rm_kaspa simulation
# Result: log written to D:/pdsa_fpga_dfx_build/output/sim_rm_kaspa.log

set rtl_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/rtl
set out_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/simulation

file mkdir ${out_dir}
cd ${out_dir}
vlib work_kaspa
vmap work_kaspa work_kaspa
vlog -sv -work work_kaspa +acc ${rtl_dir}/sha3_256_pipe_engine_hp.sv
vlog -sv -work work_kaspa +acc ${rtl_dir}/rm_kaspa.sv
vlog -sv -work work_kaspa +acc ${rtl_dir}/rm_kaspa_wrapper.v
vlog -sv -work work_kaspa +acc ${rtl_dir}/tb_rm_kaspa.sv

vsim -c work_kaspa.tb_rm_kaspa -do "run -all" -logfile ${out_dir}/sim_rm_kaspa.log
quit -sim
quit -f
