// Verilog wrapper for rm_bitcoin (for BD module reference compatibility)
module rm_bitcoin_wrapper (
  input  wire         clk,
  input  wire         rst_n,
  input  wire         rp_start,
  input  wire         rp_stop,
  input  wire [639:0] rp_job_data,
  input  wire [255:0] rp_midstate,
  input  wire [255:0] rp_target,
  input  wire [31:0]  rp_start_nonce,
  output wire [7:0]   rp_algo_id,
  output wire [255:0] rp_hash_out,
  output wire [31:0]  rp_nonce_out,
  output wire         rp_found,
  output wire [63:0]  rp_hash_count,
  output wire         rp_busy,
  output wire         rp_valid_out
);

rm_bitcoin u_rm (
  .clk(clk), .rst_n(rst_n),
  .rp_start(rp_start), .rp_stop(rp_stop),
  .rp_job_data(rp_job_data), .rp_midstate(rp_midstate),
  .rp_target(rp_target), .rp_start_nonce(rp_start_nonce),
  .rp_algo_id(rp_algo_id), .rp_hash_out(rp_hash_out),
  .rp_nonce_out(rp_nonce_out), .rp_found(rp_found),
  .rp_hash_count(rp_hash_count), .rp_busy(rp_busy),
  .rp_valid_out(rp_valid_out)
);
endmodule
