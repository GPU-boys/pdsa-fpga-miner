// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
// Date        : Wed Jun  3 13:16:54 2026
// Host        : Abhishek running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               d:/pdsa_updated_on_2_6/build_scripts/project_bd_dfx_sep/pdsa_fpga_bd_dfx_sep.gen/sources_1/bd/pdsa_system/ip/pdsa_system_rm_0_0/pdsa_system_rm_0_0_stub.v
// Design      : pdsa_system_rm_0_0
// Purpose     : Stub declaration of top-level module interface
// Device      : xck26-sfvc784-2LV-c
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CHECK_LICENSE_TYPE = "pdsa_system_rm_0_0,rm_bitcoin_wrapper,{}" *) (* CORE_GENERATION_INFO = "pdsa_system_rm_0_0,rm_bitcoin_wrapper,{x_ipProduct=Vivado 2025.2,x_ipVendor=xilinx.com,x_ipLibrary=module_ref,x_ipName=rm_bitcoin_wrapper,x_ipVersion=1.0,x_ipCoreRevision=1,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}" *) (* DowngradeIPIdentifiedWarnings = "yes" *) 
(* IP_DEFINITION_SOURCE = "module_ref" *) (* X_CORE_INFO = "rm_bitcoin_wrapper,Vivado 2025.2" *) 
module pdsa_system_rm_0_0(clk, rst_n, rp_start, rp_stop, rp_job_data, 
  rp_midstate, rp_target, rp_start_nonce, rp_algo_id, rp_hash_out, rp_nonce_out, rp_found, 
  rp_hash_count, rp_busy, rp_valid_out)
/* synthesis syn_black_box black_box_pad_pin="rst_n,rp_start,rp_stop,rp_job_data[639:0],rp_midstate[255:0],rp_target[255:0],rp_start_nonce[31:0],rp_algo_id[7:0],rp_hash_out[255:0],rp_nonce_out[31:0],rp_found,rp_hash_count[63:0],rp_busy,rp_valid_out" */
/* synthesis syn_force_seq_prim="clk" */;
  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk CLK" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME clk, FREQ_HZ 96968727, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN pdsa_system_zynq_ultra_ps_e_0_0_pl_clk0, INSERT_VIP 0" *) input clk /* synthesis syn_isclock = 1 */;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_n RST" *) (* X_INTERFACE_MODE = "slave" *) (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0" *) input rst_n;
  input rp_start;
  input rp_stop;
  input [639:0]rp_job_data;
  input [255:0]rp_midstate;
  input [255:0]rp_target;
  input [31:0]rp_start_nonce;
  output [7:0]rp_algo_id;
  output [255:0]rp_hash_out;
  output [31:0]rp_nonce_out;
  output rp_found;
  output [63:0]rp_hash_count;
  output rp_busy;
  output rp_valid_out;
endmodule
