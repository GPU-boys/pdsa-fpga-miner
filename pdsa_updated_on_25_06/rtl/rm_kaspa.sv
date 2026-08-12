`timescale 1ns/1ps
module rm_kaspa (
  input  wire          clk,
  input  wire          rst_n,
  input  wire          rp_start,
  input  wire          rp_stop,
  output wire [7:0]    rp_algo_id,
  input  wire [639:0]  rp_job_data,
  input  wire [255:0]  rp_midstate,
  input  wire [255:0]  rp_target,
  input  wire [31:0]   rp_start_nonce,
  output wire [255:0]  rp_hash_out,
  output wire [31:0]   rp_nonce_out,
  output reg           rp_found,
  output reg  [63:0]   rp_hash_count,
  output wire          rp_busy,
  output wire          rp_valid_out
);
  assign rp_algo_id = 8'h02;
  assign rp_busy    = 1'b0;
  assign rp_nonce_out = rp_start_nonce;

  wire [255:0] sha3_hash;
  wire         sha3_valid;

  sha3_256_pipe_engine_hp u_kaspa (
    .clk(clk), .rst_n(rst_n),
    .msg_80b(rp_job_data),
    .valid_in(rp_start),
    .stop(rp_stop),
    .hash_out(sha3_hash),
    .valid_out(sha3_valid)
  );

  assign rp_hash_out  = sha3_hash;
  assign rp_valid_out = sha3_valid;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rp_found      <= 1'b0;
      rp_hash_count <= 64'd0;
    end else begin
      if (rp_start) rp_hash_count <= 64'd0;
      if (sha3_valid) begin
        rp_hash_count <= rp_hash_count + 64'd1;
        rp_found      <= (sha3_hash < rp_target) ? 1'b1 : 1'b0;
      end else begin
        rp_found <= 1'b0;
      end
    end
  end
endmodule
