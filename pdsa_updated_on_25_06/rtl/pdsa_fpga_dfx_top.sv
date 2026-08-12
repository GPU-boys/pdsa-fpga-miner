`timescale 1ns/1ps
// =============================================================================
// PDSA-FPGA DFX Top Level
// Static shell + single RP instance (swapped by DPR)
// =============================================================================
module pdsa_fpga_dfx_top (
  input  wire         clk,
  input  wire         rst_n,
  input  wire [11:0]  s_axi_awaddr,  input  wire s_axi_awvalid,
  output wire         s_axi_awready,
  input  wire [31:0]  s_axi_wdata,   input  wire [3:0] s_axi_wstrb,
  input  wire         s_axi_wvalid,  output wire s_axi_wready,
  output wire [1:0]   s_axi_bresp,   output wire s_axi_bvalid,
  input  wire         s_axi_bready,
  input  wire [11:0]  s_axi_araddr,  input  wire s_axi_arvalid,
  output wire         s_axi_arready,
  output wire [31:0]  s_axi_rdata,   output wire [1:0] s_axi_rresp,
  output wire         s_axi_rvalid,  input  wire s_axi_rready,
  output wire          irq_found,
  output wire          irq_dpr_done
);
  // Shell <-> RP wires
  wire         rp_start, rp_stop;
  wire [639:0] rp_job_data;
  wire [255:0] rp_midstate, rp_target;
  wire [31:0]  rp_start_nonce;
  wire [7:0]   rp_algo_id;
  wire [255:0] rp_hash_out;
  wire [31:0]  rp_nonce_out;
  wire         rp_found;
  wire [63:0]  rp_hash_count;
  wire         rp_busy, rp_valid_out;

  pdsa_static_shell u_shell (
    .clk(clk), .rst_n(rst_n),
    .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awready(s_axi_awready),
    .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
    .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bready(s_axi_bready),
    .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
    .s_axi_arready(s_axi_arready),
    .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp),
    .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
    .rp_start(rp_start), .rp_stop(rp_stop),
    .rp_job_data(rp_job_data), .rp_midstate(rp_midstate),
    .rp_target(rp_target), .rp_start_nonce(rp_start_nonce),
    .rp_algo_id(rp_algo_id), .rp_hash_out(rp_hash_out),
    .rp_nonce_out(rp_nonce_out), .rp_found(rp_found),
    .rp_hash_count(rp_hash_count), .rp_busy(rp_busy),
    .rp_valid_out(rp_valid_out),
    .irq_found(irq_found), .irq_dpr_done(irq_dpr_done)
  );

  // RP instance — this module gets swapped by DPR.
  // In the full bitstream: rm_bitcoin is compiled in.
  // A partial bitstream replaces it with rm_kaspa (or vice versa).
  rm_bitcoin #(.NUM_ENGINES(24)) u_rp (
    .clk(clk), .rst_n(rst_n),
    .rp_start(rp_start), .rp_stop(rp_stop),
    .rp_algo_id(rp_algo_id),
    .rp_job_data(rp_job_data), .rp_midstate(rp_midstate),
    .rp_target(rp_target), .rp_start_nonce(rp_start_nonce),
    .rp_hash_out(rp_hash_out), .rp_nonce_out(rp_nonce_out),
    .rp_found(rp_found), .rp_hash_count(rp_hash_count),
    .rp_busy(rp_busy), .rp_valid_out(rp_valid_out)
  );
endmodule
