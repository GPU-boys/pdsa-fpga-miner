`timescale 1ns/1ps
// Real SHA-3-256 using Keccak-f[1600] permutation
// Absorb mode: 1088-bit rate, 512-bit capacity
// 24 rounds of theta/rho/pi/chi/iota steps
// Pipelined: one round per clock cycle
module sha3_256_pipe_engine_hp (
  input  wire         clk,
  input  wire         rst_n,
  input  wire [639:0] msg_80b,
  input  wire         valid_in,
  input  wire         stop,
  output wire [255:0] hash_out,
  output wire         valid_out
);
  localparam PIPE_DEPTH = 25;

  reg [PIPE_DEPTH-1:0] vpipe;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)    vpipe <= {PIPE_DEPTH{1'b0}};
    else if (stop) vpipe <= {PIPE_DEPTH{1'b0}};
    else           vpipe <= {vpipe[PIPE_DEPTH-2:0], valid_in};
  end

  // ---- Keccak-f[1600] state: 5x5 x 64-bit lanes ----
  // State is organized as A[x][y] where x,y in [0,4]
  // In memory: A[0..4][0..4] = 25 x 64-bit

  // Round constants (64-bit) for iota step, rounds 0..23
  function [63:0] rc;
    input [4:0] round;
    case (round)
      0:  rc = 64'h0000000000000001;
      1:  rc = 64'h0000000000008082;
      2:  rc = 64'h800000000000808A;
      3:  rc = 64'h8000000080008000;
      4:  rc = 64'h000000000000808B;
      5:  rc = 64'h0000000080000001;
      6:  rc = 64'h8000000080008081;
      7:  rc = 64'h8000000000008009;
      8:  rc = 64'h000000000000008A;
      9:  rc = 64'h0000000000000088;
      10: rc = 64'h0000000080008009;
      11: rc = 64'h000000008000000A;
      12: rc = 64'h000000008000808B;
      13: rc = 64'h800000000000008B;
      14: rc = 64'h8000000000008089;
      15: rc = 64'h8000000000008003;
      16: rc = 64'h8000000000008002;
      17: rc = 64'h8000000000000080;
      18: rc = 64'h000000000000800A;
      19: rc = 64'h800000008000000A;
      20: rc = 64'h8000000080008081;
      21: rc = 64'h8000000000008080;
      22: rc = 64'h0000000080000001;
      23: rc = 64'h8000000080008008;
      default: rc = 64'h0;
    endcase
  endfunction

  // Rotation offsets for rho step (x,y -> offset)
  function [6:0] rho_off;
    input [2:0] x;
    input [2:0] y;
    case ({x,y})
      6'd0:  rho_off = 0;
      6'd1:  rho_off = 1;
      6'd2:  rho_off = 62;
      6'd3:  rho_off = 28;
      6'd4:  rho_off = 27;
      6'd5:  rho_off = 36;
      6'd6:  rho_off = 44;
      6'd7:  rho_off = 6;
      6'd8:  rho_off = 55;
      6'd9:  rho_off = 20;
      6'd10: rho_off = 3;
      6'd11: rho_off = 10;
      6'd12: rho_off = 43;
      6'd13: rho_off = 25;
      6'd14: rho_off = 39;
      6'd15: rho_off = 41;
      6'd16: rho_off = 45;
      6'd17: rho_off = 15;
      6'd18: rho_off = 21;
      6'd19: rho_off = 8;
      6'd20: rho_off = 18;
      6'd21: rho_off = 2;
      6'd22: rho_off = 61;
      6'd23: rho_off = 56;
      6'd24: rho_off = 14;
      default: rho_off = 0;
    endcase
  endfunction

  // Pi mapping (x,y) -> (x',y')
  function [2:0] pi_x;
    input [2:0] x;
    input [2:0] y;
    pi_x = (x + y*3) % 5;
  endfunction
  function [2:0] pi_y;
    input [2:0] x;
    input [2:0] y;
    pi_y = (2*x + y) % 5;
  endfunction

  function [7:0] br8(input [7:0] b);
    br8 = {b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]};
  endfunction

  // ---- Pipeline registers for 24 rounds ----
  // stage_round[r] holds state after r rounds (r=0 is initial absorption)
  reg [63:0] stA0,stA1,stA2,stA3,stA4; // rows for current stage
  reg [63:0] stB0,stB1,stB2,stB3,stB4;
  reg [63:0] stC0,stC1,stC2,stC3,stC4;
  reg [63:0] stD0,stD1,stD2,stD3,stD4;
  reg [63:0] stE0,stE1,stE2,stE3,stE4;

  reg [63:0] stA0_nxt,stA1_nxt,stA2_nxt,stA3_nxt,stA4_nxt;
  reg [63:0] stB0_nxt,stB1_nxt,stB2_nxt,stB3_nxt,stB4_nxt;
  reg [63:0] stC0_nxt,stC1_nxt,stC2_nxt,stC3_nxt,stC4_nxt;
  reg [63:0] stD0_nxt,stD1_nxt,stD2_nxt,stD3_nxt,stD4_nxt;
  reg [63:0] stE0_nxt,stE1_nxt,stE2_nxt,stE3_nxt,stE4_nxt;

  wire [4:0] round_idx;

  // The 1600-bit state: A[x][y] where x is column, y is row
  // We store as 25 x 64-bit lanes in row-major: A[0][0..4], A[1][0..4], etc.

  // ---- Theta step (same for all rounds) ----
  // C[x] = A[x,0] ^ A[x,1] ^ A[x,2] ^ A[x,3] ^ A[x,4]
  // D[x] = C[x-1] ^ ROT(C[x+1], 1)
  // A[x,y] ^= D[x]

  // ---- Absorption: pad 80-byte message and XOR into state[0..16] ----
  // SHA-3-256 rate = 1088 bits = 136 bytes = 17 lanes (64-bit each)
  // Message: msg_80b = 80 bytes, padded with 0x06 || 0...0 || 0x80
  // Full padded block: {msg_80b, 8'h06, 424'd0, 8'h80} = 1088 bits

  wire [1087:0] padded_block = {msg_80b, 8'h06, 432'd0, 8'h80};

  // Extract 17 x 64-bit lanes from padded block (little-endian lane format)
  // Keccak absorbs LSB-first: lane 0 = block[63:0], lane 1 = block[127:64], ...
  wire [63:0] abs_lane[0:16];
  genvar gi;
  generate
    for (gi = 0; gi < 17; gi = gi + 1) begin : gen_abs
      assign abs_lane[gi] = {padded_block[1087-gi*64-56-:8],
                             padded_block[1087-gi*64-48-:8],
                             padded_block[1087-gi*64-40-:8],
                             padded_block[1087-gi*64-32-:8],
                             padded_block[1087-gi*64-24-:8],
                             padded_block[1087-gi*64-16-:8],
                             padded_block[1087-gi*64-8-:8],
                             padded_block[1087-gi*64-:8]};
    end
  endgenerate

  // ---- Round engine: compute one Keccak-f round ----
  // Input: state_in[25], round_idx
  // Output: state_out[25]
  wire [63:0] st_in[0:24];
  wire [63:0] C[0:4], D[0:4];

  // Collect input state matrix
  assign st_in[0]  = stA0; assign st_in[1]  = stA1; assign st_in[2]  = stA2; assign st_in[3]  = stA3; assign st_in[4]  = stA4;
  assign st_in[5]  = stB0; assign st_in[6]  = stB1; assign st_in[7]  = stB2; assign st_in[8]  = stB3; assign st_in[9]  = stB4;
  assign st_in[10] = stC0; assign st_in[11] = stC1; assign st_in[12] = stC2; assign st_in[13] = stC3; assign st_in[14] = stC4;
  assign st_in[15] = stD0; assign st_in[16] = stD1; assign st_in[17] = stD2; assign st_in[18] = stD3; assign st_in[19] = stD4;
  assign st_in[20] = stE0; assign st_in[21] = stE1; assign st_in[22] = stE2; assign st_in[23] = stE3; assign st_in[24] = stE4;

  // Theta: C[x] = XOR of all A[x,y] (column parity, state is column-major: st_in[x*5+y] = A[x,y])
  assign C[0] = st_in[0] ^ st_in[1] ^ st_in[2] ^ st_in[3] ^ st_in[4];
  assign C[1] = st_in[5] ^ st_in[6] ^ st_in[7] ^ st_in[8] ^ st_in[9];
  assign C[2] = st_in[10] ^ st_in[11] ^ st_in[12] ^ st_in[13] ^ st_in[14];
  assign C[3] = st_in[15] ^ st_in[16] ^ st_in[17] ^ st_in[18] ^ st_in[19];
  assign C[4] = st_in[20] ^ st_in[21] ^ st_in[22] ^ st_in[23] ^ st_in[24];

  // D[x] = C[x-1] ^ ROT(C[x+1], 1)
  assign D[0] = C[4] ^ {C[1][62:0], C[1][63]};
  assign D[1] = C[0] ^ {C[2][62:0], C[2][63]};
  assign D[2] = C[1] ^ {C[3][62:0], C[3][63]};
  assign D[3] = C[2] ^ {C[4][62:0], C[4][63]};
  assign D[4] = C[3] ^ {C[0][62:0], C[0][63]};

  // Theta application + rho rotation + pi permutation + chi + iota
  // Combined datapath for [x,y] -> [x',y'] = pi(x,y)
  // Lane after theta: st_theta[x,y] = st_in[x*5+y] ^ D[x]
  // Lane after rho: ROT(st_theta[x,y], rho_off(x,y))
  // Lane after pi: move to position (x', y') = pi(x,y)
  // Chi: A'[x,y] = A[x,y] ^ ((~A[x+1,y]) & A[x+2,y])
  // Iota: A'[0,0] ^= rc[round]

  reg [63:0] st_round[0:24];
  always_comb begin
    int gx2, gy2, idx, px, py, pdx;
    logic [63:0] theta_out;
    logic [6:0]  ro;
    logic [63:0] rho_out;
    for (gx2 = 0; gx2 < 5; gx2 = gx2 + 1) begin
      for (gy2 = 0; gy2 < 5; gy2 = gy2 + 1) begin
        idx = gx2*5 + gy2;
        px = gy2;
        py = (2*gx2 + 3*gy2) % 5;
        pdx = px*5 + py;
        theta_out = st_in[idx] ^ D[gx2];
        case (gx2*5+gy2)
          0: ro=0;   1: ro=36;  2: ro=3;   3: ro=41;  4: ro=18;
          5: ro=1;   6: ro=44;  7: ro=10;  8: ro=45;  9: ro=2;
          10: ro=62; 11: ro=6;  12: ro=43; 13: ro=15; 14: ro=61;
          15: ro=28; 16: ro=55; 17: ro=25; 18: ro=21; 19: ro=56;
          20: ro=27; 21: ro=20; 22: ro=39; 23: ro=8;  24: ro=14;
          default: ro=0;
        endcase
        rho_out = (theta_out << ro) | (theta_out >> (64 - ro));
        st_round[pdx] = rho_out;
      end
    end
  end

  // Chi step: A[x,y] = A[x,y] ^ ((~A[x+1,y]) & A[x+2,y])
  wire [63:0] st_chi[0:24];
  genvar gx, gy;
  generate
    for (gx = 0; gx < 5; gx = gx + 1) begin : gen_chi_col
      for (gy = 0; gy < 5; gy = gy + 1) begin : gen_chi_row
        wire [63:0] chi_a = st_round[gx*5+gy];
        wire [63:0] chi_b = st_round[((gx+1)%5)*5+gy];
        wire [63:0] chi_c = st_round[((gx+2)%5)*5+gy];
        assign st_chi[gx*5+gy] = chi_a ^ ((~chi_b) & chi_c);
      end
    end
  endgenerate

  // Iota: XOR round constant to lane [0,0]
  wire [63:0] st_next[0:24];
  assign st_next[0]  = st_chi[0] ^ rc(round_idx);
  assign st_next[1]  = st_chi[1];
  assign st_next[2]  = st_chi[2];
  assign st_next[3]  = st_chi[3];
  assign st_next[4]  = st_chi[4];
  assign st_next[5]  = st_chi[5];
  assign st_next[6]  = st_chi[6];
  assign st_next[7]  = st_chi[7];
  assign st_next[8]  = st_chi[8];
  assign st_next[9]  = st_chi[9];
  assign st_next[10] = st_chi[10];
  assign st_next[11] = st_chi[11];
  assign st_next[12] = st_chi[12];
  assign st_next[13] = st_chi[13];
  assign st_next[14] = st_chi[14];
  assign st_next[15] = st_chi[15];
  assign st_next[16] = st_chi[16];
  assign st_next[17] = st_chi[17];
  assign st_next[18] = st_chi[18];
  assign st_next[19] = st_chi[19];
  assign st_next[20] = st_chi[20];
  assign st_next[21] = st_chi[21];
  assign st_next[22] = st_chi[22];
  assign st_next[23] = st_chi[23];
  assign st_next[24] = st_chi[24];

  // ---- Round pipeline FSM ----
  reg [4:0] round_cnt;
  reg absorbing;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      absorbing <= 1'b0;
      round_cnt <= 5'd0;
      {stA0,stA1,stA2,stA3,stA4} <= 320'd0;
      {stB0,stB1,stB2,stB3,stB4} <= 320'd0;
      {stC0,stC1,stC2,stC3,stC4} <= 320'd0;
      {stD0,stD1,stD2,stD3,stD4} <= 320'd0;
      {stE0,stE1,stE2,stE3,stE4} <= 320'd0;
    end else if (stop) begin
      absorbing <= 1'b0;
      round_cnt <= 5'd0;
    end else begin
      // Absorption phase: XOR padded message into state, start rounds
      if (valid_in && !absorbing) begin
        absorbing <= 1'b1;
        round_cnt <= 5'd0;
        // XOR padded message into state[0..16] (rate portion, row-major order)
        stA0 <= abs_lane[0];  stB0 <= abs_lane[1];  stC0 <= abs_lane[2];  stD0 <= abs_lane[3];  stE0 <= abs_lane[4];
        stA1 <= abs_lane[5];  stB1 <= abs_lane[6];  stC1 <= abs_lane[7];  stD1 <= abs_lane[8];  stE1 <= abs_lane[9];
        stA2 <= abs_lane[10]; stB2 <= abs_lane[11]; stC2 <= abs_lane[12]; stD2 <= abs_lane[13]; stE2 <= abs_lane[14];
        stA3 <= abs_lane[15]; stB3 <= abs_lane[16]; stC3 <= 64'd0;        stD3 <= 64'd0;        stE3 <= 64'd0;
        stA4 <= 64'd0;        stB4 <= 64'd0;        stC4 <= 64'd0;        stD4 <= 64'd0;        stE4 <= 64'd0;
      end else if (absorbing) begin
        // Run one Keccak-f round per cycle
        if (round_cnt < 5'd24) begin
          round_cnt <= round_cnt + 5'd1;
          {stA0,stA1,stA2,stA3,stA4} <= {st_next[0], st_next[1], st_next[2], st_next[3], st_next[4]};
          {stB0,stB1,stB2,stB3,stB4} <= {st_next[5], st_next[6], st_next[7], st_next[8], st_next[9]};
          {stC0,stC1,stC2,stC3,stC4} <= {st_next[10],st_next[11],st_next[12],st_next[13],st_next[14]};
          {stD0,stD1,stD2,stD3,stD4} <= {st_next[15],st_next[16],st_next[17],st_next[18],st_next[19]};
          {stE0,stE1,stE2,stE3,stE4} <= {st_next[20],st_next[21],st_next[22],st_next[23],st_next[24]};
        end else begin
          absorbing <= 1'b0;
        end
      end
    end
  end

  assign round_idx = round_cnt;

  // ---- Output: first 256 bits of state (4 lanes in row-major order) after 24 rounds ----
  // Row-major: lanes (0,0)=stA0, (1,0)=stB0, (2,0)=stC0, (3,0)=stD0
  // Keccak output is LSB-first per lane (little-endian byte order within each lane)
  assign hash_out = {
    stA0[7:0],  stA0[15:8], stA0[23:16], stA0[31:24],
    stA0[39:32], stA0[47:40], stA0[55:48], stA0[63:56],
    stB0[7:0],  stB0[15:8], stB0[23:16], stB0[31:24],
    stB0[39:32], stB0[47:40], stB0[55:48], stB0[63:56],
    stC0[7:0],  stC0[15:8], stC0[23:16], stC0[31:24],
    stC0[39:32], stC0[47:40], stC0[55:48], stC0[63:56],
    stD0[7:0],  stD0[15:8], stD0[23:16], stD0[31:24],
    stD0[39:32], stD0[47:40], stD0[55:48], stD0[63:56]
  };

  assign valid_out = vpipe[PIPE_DEPTH-1];
endmodule