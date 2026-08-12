`timescale 1ns/1ps
module sha256d_real_engine (
  input  wire         clk,
  input  wire         rst_n,
  input  wire [255:0] midstate,
  input  wire [31:0]  merkle_tail,
  input  wire [31:0]  timestamp,
  input  wire [31:0]  bits,
  input  wire [31:0]  nonce,
  input  wire         nonce_valid,
  output reg  [255:0] hash_out,
  output reg          hash_valid
);
  localparam [255:0] SHA256_IV = {
    32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
    32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
  };

  localparam IDLE = 2'd0, HASH1 = 2'd1, HASH2 = 2'd2;
  reg [1:0] state;

  reg [255:0] midstate_reg, first_hash;
  reg [31:0]  merkle_reg, timestamp_reg, bits_reg, nonce_reg;

  reg [511:0] blk1, blk2;
  wire [255:0] digest1, digest2;
  wire         busy1, done1, busy2, done2;

  reg start1, start2;

  sha256_core_baseline u_hash1 (
    .clk(clk), .rst_n(rst_n),
    .start(start1),
    .iv(midstate_reg),
    .block_data(blk1),
    .busy(busy1), .done(done1), .digest(digest1)
  );

  sha256_core_baseline u_hash2 (
    .clk(clk), .rst_n(rst_n),
    .start(start2),
    .iv(SHA256_IV),
    .block_data(blk2),
    .busy(busy2), .done(done2), .digest(digest2)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state       <= IDLE;
      start1      <= 1'b0;
      start2      <= 1'b0;
      hash_valid  <= 1'b0;
      hash_out    <= 256'd0;
      first_hash  <= 256'd0;
    end else begin
      start1   <= 1'b0;
      start2   <= 1'b0;
      hash_valid <= 1'b0;

      case (state)
        IDLE: begin
          if (nonce_valid) begin
            midstate_reg <= midstate;
            merkle_reg   <= merkle_tail;
            timestamp_reg <= timestamp;
            bits_reg     <= bits;
            nonce_reg    <= nonce;
            blk1 <= {merkle_tail, timestamp, bits, nonce,
                     32'h80000000, 288'd0, 32'd0, 32'h00000280};
            start1 <= 1'b1;
            state <= HASH1;
          end
        end
        HASH1: begin
          if (done1) begin
            first_hash <= digest1;
            blk2 <= {digest1, 32'h80000000, 192'd0, 32'h00000100};
            start2 <= 1'b1;
            state <= HASH2;
          end
        end
        HASH2: begin
          if (done2) begin
            hash_out   <= digest2;
            hash_valid <= 1'b1;
            state      <= IDLE;
          end
        end
      endcase
    end
  end
endmodule
