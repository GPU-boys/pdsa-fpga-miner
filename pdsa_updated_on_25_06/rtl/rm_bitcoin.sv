`timescale 1ns/1ps
module rm_bitcoin #(
  parameter integer NUM_ENGINES = 20
)(
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
  output wire          rp_found,
  output wire [63:0]   rp_hash_count,
  output wire          rp_busy,
  output wire          rp_valid_out
);
  assign rp_algo_id = 8'h01;

  wire [31:0] merkle_tail = rp_job_data[639:608];
  wire [31:0] timestamp   = rp_job_data[607:576];
  wire [31:0] bits        = rp_job_data[575:544];

  // ===== KAT mode: NIST Known-Answer Test =====
  // Activated when rp_target == 256'd0 (impossible mining target).
  // Feeds rp_midstate + rp_job_data[511:0] directly into a single
  // sha256_core_baseline for single-SHA-256 KAT verification.
  // Result driven onto rp_found / rp_hash_out / rp_busy.
  wire kat_mode = (rp_target == 256'd0);

  reg kat_start, kat_running;
  reg kat_found;
  reg [255:0] kat_digest;
  wire kat_done;

  sha256_core_baseline u_kat (
    .clk(clk), .rst_n(rst_n),
    .start(kat_start),
    .iv(rp_midstate),
    .block_data(rp_job_data[511:0]),
    .busy(),
    .done(kat_done),
    .digest(kat_digest)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      kat_start   <= 1'b0;
      kat_running <= 1'b0;
      kat_found   <= 1'b0;
    end else begin
      kat_start <= 1'b0;
      if (kat_mode && rp_start && !kat_running) begin
        kat_start   <= 1'b1;
        kat_running <= 1'b1;
        kat_found   <= 1'b0;
      end else if (kat_running && kat_done) begin
        kat_running <= 1'b0;
        kat_found   <= 1'b1;
      end else begin
        // clear found when a new start is requested in kat_mode
        if (rp_start) kat_found <= 1'b0;
      end
    end
  end

  // ===== Normal mining engine =====
  wire engine_start  = !kat_mode && rp_start;
  wire engine_stop   = !kat_mode && rp_stop;

  wire        eng_found;
  wire [31:0] eng_nonce;
  wire [255:0] eng_hash;
  wire [63:0]  eng_hash_count;
  wire         eng_busy;

  sha256d_multi_engine_hp #(.NUM_ENGINES(NUM_ENGINES)) u_btc (
    .clk(clk), .rst_n(rst_n),
    .midstate(rp_midstate),
    .merkle_tail(merkle_tail), .timestamp(timestamp), .bits(bits),
    .start_nonce(rp_start_nonce),
    .target(rp_target),
    .start_job(engine_start), .stop_job(engine_stop),
    .found_nonce(eng_nonce), .found_hash(eng_hash),
    .found(eng_found), .hash_count(eng_hash_count),
    .engines_busy(eng_busy)
  );

  // ===== Output mux =====
  assign rp_found      = kat_mode ? kat_found              : eng_found;
  assign rp_hash_out   = kat_mode ? kat_digest             : eng_hash;
  assign rp_nonce_out  = kat_mode ? 32'd0                   : eng_nonce;
  assign rp_hash_count = kat_mode ? 64'd0                   : eng_hash_count;
  assign rp_busy       = kat_mode ? kat_running             : eng_busy;
  assign rp_valid_out  = rp_found;
endmodule
