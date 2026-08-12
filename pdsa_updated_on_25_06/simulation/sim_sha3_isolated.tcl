set rtl_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/rtl
set out_dir F:/Documents/Academics/ASIC_miner/pdsa_updated_on_3_6_newv/simulation

file mkdir ${out_dir}
cd ${out_dir}
vlib work_sha3_iso
vmap work_sha3_iso work_sha3_iso
vlog -sv -work work_sha3_iso +acc ${rtl_dir}/sha3_256_pipe_engine_hp.sv
vlog -sv -work work_sha3_iso +acc ${rtl_dir}/tb_sha3_isolated.sv

vsim -c work_sha3_iso.tb_sha3_isolated -do "run -all" -logfile ${out_dir}/sim_sha3_isolated.log
quit -sim
quit -f
