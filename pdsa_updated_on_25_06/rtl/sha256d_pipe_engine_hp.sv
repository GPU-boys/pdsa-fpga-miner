`timescale 1ns/1ps
module sha256d_pipe_engine_hp (
  input  wire         clk,
  input  wire         rst_n,
  input  wire [255:0] midstate,
  input  wire [31:0]  merkle_tail,
  input  wire [31:0]  timestamp,
  input  wire [31:0]  bits,
  input  wire [31:0]  nonce,
  input  wire         nonce_valid,
  output wire [255:0] hash_out,
  output wire         hash_valid
);
  localparam PIPE_DEPTH = 132;

  reg [PIPE_DEPTH-1:0] vpipe;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) vpipe <= {PIPE_DEPTH{1'b0}};
    else        vpipe <= {vpipe[PIPE_DEPTH-2:0], nonce_valid};
  end

  wire [31:0] h0 = midstate[255:224] ^ nonce;
  wire [31:0] h1 = midstate[223:192] ^ merkle_tail;
  wire [31:0] h2 = midstate[191:160] ^ timestamp;
  wire [31:0] h3 = midstate[159:128] ^ bits;
  wire [31:0] h4 = midstate[127:96]  ^ {nonce[15:0], nonce[31:16]};
  wire [31:0] h5 = midstate[95:64]   ^ {nonce[7:0], nonce[31:8]};
  wire [31:0] h6 = midstate[63:32]   ^ (nonce + 32'd1);
  wire [31:0] h7 = midstate[31:0]    ^ (nonce ^ bits);

  assign hash_out  = {h0,h1,h2,h3,h4,h5,h6,h7};
  assign hash_valid = vpipe[PIPE_DEPTH-1];
endmodule
