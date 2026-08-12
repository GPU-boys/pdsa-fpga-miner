`timescale 1ns/1ps
module sha256d_multi_engine_hp #(
  parameter integer NUM_ENGINES = 32
)(
  input  wire         clk,
  input  wire         rst_n,
  input  wire [255:0] midstate,
  input  wire [31:0]  merkle_tail,
  input  wire [31:0]  timestamp,
  input  wire [31:0]  bits,
  input  wire [31:0]  start_nonce,
  input  wire [255:0] target,
  input  wire         start_job,
  input  wire         stop_job,
  output reg  [31:0]  found_nonce,
  output reg  [255:0] found_hash,
  output reg          found,
  output reg  [63:0]  hash_count,
  output wire         engines_busy
);

  localparam CYCLES_PER_HASH = 133;
  localparam [255:0] SHA256_IV = {
    32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
    32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
  };

  reg running;
  assign engines_busy = running;

  reg [31:0] engine_nonce   [0:NUM_ENGINES-1];
  reg        engine_valid   [0:NUM_ENGINES-1];
  reg        engine_started [0:NUM_ENGINES-1];
  wire [255:0] engine_hash  [0:NUM_ENGINES-1];
  wire        engine_done   [0:NUM_ENGINES-1];

  reg [$clog2(NUM_ENGINES)-1:0] dispatch_idx;
  reg [31:0] next_nonce_val;

  reg [31:0] ndelayed [0:NUM_ENGINES-1];
  integer nd;

  always @(posedge clk) begin
    for (nd = 0; nd < NUM_ENGINES; nd = nd + 1)
      ndelayed[nd] <= engine_nonce[nd];
  end

  genvar g;
  generate
    for (g = 0; g < NUM_ENGINES; g = g + 1) begin : gen_eng
      sha256d_real_engine u_eng (
        .clk(clk), .rst_n(rst_n),
        .midstate(midstate),
        .merkle_tail(merkle_tail),
        .timestamp(timestamp),
        .bits(bits),
        .nonce(engine_nonce[g]),
        .nonce_valid(engine_valid[g]),
        .hash_out(engine_hash[g]),
        .hash_valid(engine_done[g])
      );
    end
  endgenerate

  always @(posedge clk or negedge rst_n) begin
    integer i;
    if (!rst_n) begin
      running         <= 1'b0;
      hash_count      <= 64'd0;
      found           <= 1'b0;
      found_hash      <= 256'd0;
      found_nonce     <= 32'd0;
      dispatch_idx    <= 0;
      next_nonce_val  <= 32'd0;
      for (i = 0; i < NUM_ENGINES; i = i + 1) begin
        engine_valid[i]   <= 1'b0;
        engine_started[i] <= 1'b0;
      end
    end else begin
      found <= 1'b0;

      for (i = 0; i < NUM_ENGINES; i = i + 1) begin
        if (engine_started[i] && engine_done[i]) begin
          engine_started[i] <= 1'b0;
          if (engine_hash[i] < target) begin
            found       <= 1'b1;
            found_hash  <= engine_hash[i];
            found_nonce <= ndelayed[i];
            running     <= 1'b0;
          end
        end
      end

      if (start_job) begin
        running        <= 1'b1;
        hash_count     <= 64'd0;
        found          <= 1'b0;
        dispatch_idx   <= 0;
        next_nonce_val <= start_nonce;
        for (i = 0; i < NUM_ENGINES; i = i + 1) begin
          engine_valid[i]   <= 1'b0;
          engine_started[i] <= 1'b0;
        end
      end else if (stop_job) begin
        running    <= 1'b0;
        hash_count <= 64'd0;
      end else if (running) begin
        for (i = 0; i < NUM_ENGINES; i = i + 1)
          engine_valid[i] <= 1'b0;

        if (!engine_started[dispatch_idx] && !engine_done[dispatch_idx]) begin
          engine_nonce[dispatch_idx] <= next_nonce_val;
          engine_valid[dispatch_idx]   <= 1'b1;
          engine_started[dispatch_idx] <= 1'b1;
          next_nonce_val <= next_nonce_val + 32'd1;
          hash_count <= hash_count + 64'd1;
          if (dispatch_idx == NUM_ENGINES - 1)
            dispatch_idx <= 0;
          else
            dispatch_idx <= dispatch_idx + 1;
        end
      end
    end
  end
endmodule
