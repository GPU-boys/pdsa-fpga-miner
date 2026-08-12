`timescale 1ns/1ps
module sha256_core_baseline (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [255:0] iv,
    input  wire [511:0] block_data,
    output reg          busy,
    output reg          done,
    output reg  [255:0] digest
);
  reg [1:0] state;
  localparam S_IDLE    = 2'd0;
  localparam S_COMPUTE = 2'd1;
  localparam S_FINAL   = 2'd2;

  reg [6:0]  round_cnt;
  reg [255:0] iv_reg;
  reg [31:0]  a,b,c,d,e,f,g,h;

  reg [31:0] w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,w15;

  function [31:0] sha256_K;
    input [5:0] idx;
    case (idx)
      6'd0:  sha256_K=32'h428a2f98; 6'd1:  sha256_K=32'h71374491;
      6'd2:  sha256_K=32'hb5c0fbcf; 6'd3:  sha256_K=32'he9b5dba5;
      6'd4:  sha256_K=32'h3956c25b; 6'd5:  sha256_K=32'h59f111f1;
      6'd6:  sha256_K=32'h923f82a4; 6'd7:  sha256_K=32'hab1c5ed5;
      6'd8:  sha256_K=32'hd807aa98; 6'd9:  sha256_K=32'h12835b01;
      6'd10: sha256_K=32'h243185be; 6'd11: sha256_K=32'h550c7dc3;
      6'd12: sha256_K=32'h72be5d74; 6'd13: sha256_K=32'h80deb1fe;
      6'd14: sha256_K=32'h9bdc06a7; 6'd15: sha256_K=32'hc19bf174;
      6'd16: sha256_K=32'he49b69c1; 6'd17: sha256_K=32'hefbe4786;
      6'd18: sha256_K=32'h0fc19dc6; 6'd19: sha256_K=32'h240ca1cc;
      6'd20: sha256_K=32'h2de92c6f; 6'd21: sha256_K=32'h4a7484aa;
      6'd22: sha256_K=32'h5cb0a9dc; 6'd23: sha256_K=32'h76f988da;
      6'd24: sha256_K=32'h983e5152; 6'd25: sha256_K=32'ha831c66d;
      6'd26: sha256_K=32'hb00327c8; 6'd27: sha256_K=32'hbf597fc7;
      6'd28: sha256_K=32'hc6e00bf3; 6'd29: sha256_K=32'hd5a79147;
      6'd30: sha256_K=32'h06ca6351; 6'd31: sha256_K=32'h14292967;
      6'd32: sha256_K=32'h27b70a85; 6'd33: sha256_K=32'h2e1b2138;
      6'd34: sha256_K=32'h4d2c6dfc; 6'd35: sha256_K=32'h53380d13;
      6'd36: sha256_K=32'h650a7354; 6'd37: sha256_K=32'h766a0abb;
      6'd38: sha256_K=32'h81c2c92e; 6'd39: sha256_K=32'h92722c85;
      6'd40: sha256_K=32'ha2bfe8a1; 6'd41: sha256_K=32'ha81a664b;
      6'd42: sha256_K=32'hc24b8b70; 6'd43: sha256_K=32'hc76c51a3;
      6'd44: sha256_K=32'hd192e819; 6'd45: sha256_K=32'hd6990624;
      6'd46: sha256_K=32'hf40e3585; 6'd47: sha256_K=32'h106aa070;
      6'd48: sha256_K=32'h19a4c116; 6'd49: sha256_K=32'h1e376c08;
      6'd50: sha256_K=32'h2748774c; 6'd51: sha256_K=32'h34b0bcb5;
      6'd52: sha256_K=32'h391c0cb3; 6'd53: sha256_K=32'h4ed8aa4a;
      6'd54: sha256_K=32'h5b9cca4f; 6'd55: sha256_K=32'h682e6ff3;
      6'd56: sha256_K=32'h748f82ee; 6'd57: sha256_K=32'h78a5636f;
      6'd58: sha256_K=32'h84c87814; 6'd59: sha256_K=32'h8cc70208;
      6'd60: sha256_K=32'h90befffa; 6'd61: sha256_K=32'ha4506ceb;
      6'd62: sha256_K=32'hbef9a3f7; 6'd63: sha256_K=32'hc67178f2;
      default: sha256_K=32'h0;
    endcase
  endfunction

  wire [31:0] cur_w = (round_cnt < 16) ? w0 :
    ({w14[16:0],w14[31:17]} ^ {w14[18:0],w14[31:19]} ^ (w14>>10))
    + w9
    + ({w1[6:0],w1[31:7]} ^ {w1[17:0],w1[31:18]} ^ (w1>>3))
    + w0;

  wire [31:0] bsig1 = {e[5:0],e[31:6]}^{e[10:0],e[31:11]}^{e[24:0],e[31:25]};
  wire [31:0] ch_   = (e&f)^(~e&g);
  wire [31:0] bsig0 = {a[1:0],a[31:2]}^{a[12:0],a[31:13]}^{a[21:0],a[31:22]};
  wire [31:0] maj_  = (a&b)^(a&c)^(b&c);
  wire [31:0] T1    = h + bsig1 + ch_ + sha256_K(round_cnt[5:0]) + cur_w;
  wire [31:0] T2    = bsig0 + maj_;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state     <= S_IDLE;
      round_cnt <= 7'd0;
      done      <= 1'b0;
      busy      <= 1'b0;
      digest    <= 256'd0;
      iv_reg    <= 256'd0;
      {a,b,c,d,e,f,g,h} <= 256'd0;
      {w0,w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,w11,w12,w13,w14,w15} <= 512'd0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          if (start) begin
            iv_reg    <= iv;
            a <= iv[255:224]; b <= iv[223:192];
            c <= iv[191:160]; d <= iv[159:128];
            e <= iv[127:96];  f <= iv[95:64];
            g <= iv[63:32];   h <= iv[31:0];
            w0  <= block_data[511:480]; w1  <= block_data[479:448];
            w2  <= block_data[447:416]; w3  <= block_data[415:384];
            w4  <= block_data[383:352]; w5  <= block_data[351:320];
            w6  <= block_data[319:288]; w7  <= block_data[287:256];
            w8  <= block_data[255:224]; w9  <= block_data[223:192];
            w10 <= block_data[191:160]; w11 <= block_data[159:128];
            w12 <= block_data[127:96];  w13 <= block_data[95:64];
            w14 <= block_data[63:32];   w15 <= block_data[31:0];
            round_cnt <= 7'd0;
            busy  <= 1'b1;
            state <= S_COMPUTE;
          end
        end
        S_COMPUTE: begin
          w0<=w1; w1<=w2; w2<=w3; w3<=w4; w4<=w5; w5<=w6; w6<=w7; w7<=w8;
          w8<=w9; w9<=w10; w10<=w11; w11<=w12; w12<=w13; w13<=w14;
          w14<=w15; w15<=cur_w;
          h<=g; g<=f; f<=e; e<=d+T1; d<=c; c<=b; b<=a; a<=T1+T2;
          round_cnt <= round_cnt + 7'd1;
          if (round_cnt == 7'd63) state <= S_FINAL;
        end
        S_FINAL: begin
          digest <= {iv_reg[255:224]+a, iv_reg[223:192]+b,
                     iv_reg[191:160]+c, iv_reg[159:128]+d,
                     iv_reg[127:96]+e,  iv_reg[95:64]+f,
                     iv_reg[63:32]+g,   iv_reg[31:0]+h};
          done  <= 1'b1;
          busy  <= 1'b0;
          state <= S_IDLE;
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
