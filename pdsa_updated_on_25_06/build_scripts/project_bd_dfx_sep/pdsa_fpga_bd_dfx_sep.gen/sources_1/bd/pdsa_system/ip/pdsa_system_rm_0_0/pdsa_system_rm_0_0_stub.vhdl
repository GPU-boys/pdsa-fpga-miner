-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2025.2 (win64) Build 6299465 Fri Nov 14 19:35:11 GMT 2025
-- Date        : Wed Jun  3 13:16:54 2026
-- Host        : Abhishek running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               d:/pdsa_updated_on_2_6/build_scripts/project_bd_dfx_sep/pdsa_fpga_bd_dfx_sep.gen/sources_1/bd/pdsa_system/ip/pdsa_system_rm_0_0/pdsa_system_rm_0_0_stub.vhdl
-- Design      : pdsa_system_rm_0_0
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xck26-sfvc784-2LV-c
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity pdsa_system_rm_0_0 is
  Port ( 
    clk : in STD_LOGIC;
    rst_n : in STD_LOGIC;
    rp_start : in STD_LOGIC;
    rp_stop : in STD_LOGIC;
    rp_job_data : in STD_LOGIC_VECTOR ( 639 downto 0 );
    rp_midstate : in STD_LOGIC_VECTOR ( 255 downto 0 );
    rp_target : in STD_LOGIC_VECTOR ( 255 downto 0 );
    rp_start_nonce : in STD_LOGIC_VECTOR ( 31 downto 0 );
    rp_algo_id : out STD_LOGIC_VECTOR ( 7 downto 0 );
    rp_hash_out : out STD_LOGIC_VECTOR ( 255 downto 0 );
    rp_nonce_out : out STD_LOGIC_VECTOR ( 31 downto 0 );
    rp_found : out STD_LOGIC;
    rp_hash_count : out STD_LOGIC_VECTOR ( 63 downto 0 );
    rp_busy : out STD_LOGIC;
    rp_valid_out : out STD_LOGIC
  );

  attribute CHECK_LICENSE_TYPE : string;
  attribute CHECK_LICENSE_TYPE of pdsa_system_rm_0_0 : entity is "pdsa_system_rm_0_0,rm_bitcoin_wrapper,{}";
  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of pdsa_system_rm_0_0 : entity is "pdsa_system_rm_0_0,rm_bitcoin_wrapper,{x_ipProduct=Vivado 2025.2,x_ipVendor=xilinx.com,x_ipLibrary=module_ref,x_ipName=rm_bitcoin_wrapper,x_ipVersion=1.0,x_ipCoreRevision=1,x_ipLanguage=VERILOG,x_ipSimLanguage=MIXED}";
  attribute DowngradeIPIdentifiedWarnings : string;
  attribute DowngradeIPIdentifiedWarnings of pdsa_system_rm_0_0 : entity is "yes";
  attribute IP_DEFINITION_SOURCE : string;
  attribute IP_DEFINITION_SOURCE of pdsa_system_rm_0_0 : entity is "module_ref";
end pdsa_system_rm_0_0;

architecture stub of pdsa_system_rm_0_0 is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "clk,rst_n,rp_start,rp_stop,rp_job_data[639:0],rp_midstate[255:0],rp_target[255:0],rp_start_nonce[31:0],rp_algo_id[7:0],rp_hash_out[255:0],rp_nonce_out[31:0],rp_found,rp_hash_count[63:0],rp_busy,rp_valid_out";
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_INFO of clk : signal is "xilinx.com:signal:clock:1.0 clk CLK";
  attribute X_INTERFACE_MODE : string;
  attribute X_INTERFACE_MODE of clk : signal is "slave";
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_PARAMETER of clk : signal is "XIL_INTERFACENAME clk, FREQ_HZ 96968727, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN pdsa_system_zynq_ultra_ps_e_0_0_pl_clk0, INSERT_VIP 0";
  attribute X_INTERFACE_INFO of rst_n : signal is "xilinx.com:signal:reset:1.0 rst_n RST";
  attribute X_INTERFACE_MODE of rst_n : signal is "slave";
  attribute X_INTERFACE_PARAMETER of rst_n : signal is "XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW, INSERT_VIP 0";
  attribute X_CORE_INFO : string;
  attribute X_CORE_INFO of stub : architecture is "rm_bitcoin_wrapper,Vivado 2025.2";
begin
end;
