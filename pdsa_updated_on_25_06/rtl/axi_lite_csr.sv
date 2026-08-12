`timescale 1ns/1ps
module axi_lite_csr (
  input  wire         clk,
  input  wire         rst_n,
  input  wire [11:0]  s_axi_awaddr,
  input  wire         s_axi_awvalid,
  output reg          s_axi_awready,
  input  wire [31:0]  s_axi_wdata,
  input  wire [3:0]   s_axi_wstrb,
  input  wire         s_axi_wvalid,
  output reg          s_axi_wready,
  output wire [1:0]   s_axi_bresp,
  output reg          s_axi_bvalid,
  input  wire         s_axi_bready,
  input  wire [11:0]  s_axi_araddr,
  input  wire         s_axi_arvalid,
  output reg          s_axi_arready,
  output reg  [31:0]  s_axi_rdata,
  output wire [1:0]   s_axi_rresp,
  output reg          s_axi_rvalid,
  input  wire         s_axi_rready,
  output reg          csr_start,
  output reg          csr_stop,
  output reg          csr_decouple,
  output reg          csr_trigger_dpr,
  output reg  [7:0]   csr_algo_sel,
  output reg  [31:0]  csr_start_nonce,
  output wire [255:0] csr_target,
  output wire [255:0] csr_midstate,
  output wire [639:0] csr_job_data,
  output reg  [31:0]  csr_pt_threshold,
  output reg  [31:0]  csr_pt_current,
  output reg  [31:0]  csr_bcv_status,
  input  wire         sts_busy,
  input  wire         sts_found,
  input  wire         sts_decoupled,
  input  wire         sts_dpr_active,
  input  wire [7:0]   sts_algo_id,
  input  wire [63:0]  sts_hash_count,
  input  wire [31:0]  sts_golden_nonce,
  input  wire [31:0]  sts_dpr_latency,
  input  wire [31:0]  sts_hashrate,
  input  wire [7:0]   sts_pdsa_decision,
  input  wire [255:0] sts_result_hash
);
  assign s_axi_bresp = 2'b00;
  assign s_axi_rresp = 2'b00;

  reg [31:0] reg_target   [0:7];
  reg [31:0] reg_midstate [0:7];
  reg [31:0] reg_job_data [0:19];

  reg aw_done;
  reg [11:0] aw_addr_reg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_awready <= 1'b0; aw_done <= 1'b0; aw_addr_reg <= 12'd0;
    end else begin
      if (!aw_done && s_axi_awvalid && s_axi_wvalid) begin
        s_axi_awready <= 1'b1; aw_addr_reg <= s_axi_awaddr; aw_done <= 1'b1;
      end else begin
        s_axi_awready <= 1'b0;
        if (s_axi_bvalid && s_axi_bready) aw_done <= 1'b0;
      end
    end
  end

  reg w_done;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_wready <= 1'b0; w_done <= 1'b0;
    end else begin
      if (!w_done && s_axi_awvalid && s_axi_wvalid) begin
        s_axi_wready <= 1'b1; w_done <= 1'b1;
      end else begin
        s_axi_wready <= 1'b0;
        if (s_axi_bvalid && s_axi_bready) w_done <= 1'b0;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_bvalid <= 1'b0;
    else begin
      if (aw_done && w_done && !s_axi_bvalid) s_axi_bvalid <= 1'b1;
      else if (s_axi_bready) s_axi_bvalid <= 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    integer i;
    if (!rst_n) begin
      csr_start <= 1'b0; csr_stop <= 1'b0;
      csr_decouple <= 1'b0; csr_trigger_dpr <= 1'b0;
      csr_algo_sel <= 8'd0; csr_start_nonce <= 32'd0;
      csr_pt_threshold <= 32'd30; csr_pt_current <= 32'd100;
      csr_bcv_status <= 32'd0;
      for (i = 0; i < 8; i = i + 1) begin
        reg_target[i]   <= 32'hFFFFFFFF;
        reg_midstate[i] <= 32'd0;
      end
      for (i = 0; i < 20; i = i + 1)
        reg_job_data[i] <= 32'd0;
    end else begin
      csr_start <= 1'b0; csr_stop <= 1'b0; csr_trigger_dpr <= 1'b0;
      if (s_axi_awready && s_axi_wready) begin
        case (aw_addr_reg[11:2])
          10'd0: begin
            csr_start       <= s_axi_wdata[0];
            csr_stop        <= s_axi_wdata[1];
            csr_decouple    <= s_axi_wdata[2];
            csr_trigger_dpr <= s_axi_wdata[3];
          end
          10'd2:  csr_algo_sel     <= s_axi_wdata[7:0];
          10'd3:  csr_start_nonce  <= s_axi_wdata;
          10'd4:  reg_target[0]    <= s_axi_wdata;
          10'd5:  reg_target[1]    <= s_axi_wdata;
          10'd6:  reg_target[2]    <= s_axi_wdata;
          10'd7:  reg_target[3]    <= s_axi_wdata;
          10'd8:  reg_target[4]    <= s_axi_wdata;
          10'd9:  reg_target[5]    <= s_axi_wdata;
          10'd10: reg_target[6]    <= s_axi_wdata;
          10'd11: reg_target[7]    <= s_axi_wdata;
          10'd12: reg_midstate[0]  <= s_axi_wdata;
          10'd13: reg_midstate[1]  <= s_axi_wdata;
          10'd14: reg_midstate[2]  <= s_axi_wdata;
          10'd15: reg_midstate[3]  <= s_axi_wdata;
          10'd16: reg_midstate[4]  <= s_axi_wdata;
          10'd17: reg_midstate[5]  <= s_axi_wdata;
          10'd18: reg_midstate[6]  <= s_axi_wdata;
          10'd19: reg_midstate[7]  <= s_axi_wdata;
          10'd20: reg_job_data[0]  <= s_axi_wdata;
          10'd21: reg_job_data[1]  <= s_axi_wdata;
          10'd22: reg_job_data[2]  <= s_axi_wdata;
          10'd23: reg_job_data[3]  <= s_axi_wdata;
          10'd24: reg_job_data[4]  <= s_axi_wdata;
          10'd25: reg_job_data[5]  <= s_axi_wdata;
          10'd26: reg_job_data[6]  <= s_axi_wdata;
          10'd27: reg_job_data[7]  <= s_axi_wdata;
          10'd28: reg_job_data[8]  <= s_axi_wdata;
          10'd29: reg_job_data[9]  <= s_axi_wdata;
          10'd30: reg_job_data[10] <= s_axi_wdata;
          10'd31: reg_job_data[11] <= s_axi_wdata;
          10'd32: reg_job_data[12] <= s_axi_wdata;
          10'd33: reg_job_data[13] <= s_axi_wdata;
          10'd34: reg_job_data[14] <= s_axi_wdata;
          10'd35: reg_job_data[15] <= s_axi_wdata;
          10'd36: reg_job_data[16] <= s_axi_wdata;
          10'd37: reg_job_data[17] <= s_axi_wdata;
          10'd38: reg_job_data[18] <= s_axi_wdata;
          10'd39: reg_job_data[19] <= s_axi_wdata;
          10'd40: csr_pt_threshold <= s_axi_wdata;
          10'd41: csr_pt_current   <= s_axi_wdata;
          10'd42: csr_bcv_status   <= s_axi_wdata;
          default: ;
        endcase
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      s_axi_arready <= 1'b0; s_axi_rvalid <= 1'b0; s_axi_rdata <= 32'd0;
    end else begin
      if (s_axi_arvalid && !s_axi_rvalid) begin
        s_axi_arready <= 1'b1;
        s_axi_rvalid  <= 1'b1;
        case (s_axi_araddr[11:2])
          10'd0:  s_axi_rdata <= {28'd0, csr_trigger_dpr, csr_decouple, csr_stop, csr_start};
          10'd1:  s_axi_rdata <= {16'd0, sts_algo_id,
                                   4'd0, sts_dpr_active, sts_decoupled,
                                   sts_found, sts_busy};
          10'd2:  s_axi_rdata <= {24'd0, csr_algo_sel};
          10'd3:  s_axi_rdata <= csr_start_nonce;
          10'd44: s_axi_rdata <= sts_hash_count[31:0];
          10'd45: s_axi_rdata <= sts_hash_count[63:32];
          10'd46: s_axi_rdata <= sts_golden_nonce;
          10'd47: s_axi_rdata <= sts_dpr_latency;
          10'd48: s_axi_rdata <= sts_hashrate;
          10'd49: s_axi_rdata <= {24'd0, sts_pdsa_decision};
          10'd50: s_axi_rdata <= sts_result_hash[255:224];
          10'd51: s_axi_rdata <= sts_result_hash[223:192];
          10'd52: s_axi_rdata <= sts_result_hash[191:160];
          10'd53: s_axi_rdata <= sts_result_hash[159:128];
          10'd54: s_axi_rdata <= sts_result_hash[127:96];
          10'd55: s_axi_rdata <= sts_result_hash[95:64];
          10'd56: s_axi_rdata <= sts_result_hash[63:32];
          10'd57: s_axi_rdata <= sts_result_hash[31:0];
          default: s_axi_rdata <= 32'hDEADBEEF;
        endcase
      end else begin
        s_axi_arready <= 1'b0;
        if (s_axi_rready && s_axi_rvalid) s_axi_rvalid <= 1'b0;
      end
    end
  end

  assign csr_target[255:224] = reg_target[0]; assign csr_target[223:192] = reg_target[1];
  assign csr_target[191:160] = reg_target[2]; assign csr_target[159:128] = reg_target[3];
  assign csr_target[127:96]  = reg_target[4]; assign csr_target[95:64]  = reg_target[5];
  assign csr_target[63:32]   = reg_target[6]; assign csr_target[31:0]   = reg_target[7];

  assign csr_midstate[255:224] = reg_midstate[0]; assign csr_midstate[223:192] = reg_midstate[1];
  assign csr_midstate[191:160] = reg_midstate[2]; assign csr_midstate[159:128] = reg_midstate[3];
  assign csr_midstate[127:96]  = reg_midstate[4]; assign csr_midstate[95:64]  = reg_midstate[5];
  assign csr_midstate[63:32]   = reg_midstate[6]; assign csr_midstate[31:0]   = reg_midstate[7];

  assign csr_job_data[639:608] = reg_job_data[0];  assign csr_job_data[607:576] = reg_job_data[1];
  assign csr_job_data[575:544] = reg_job_data[2];  assign csr_job_data[543:512] = reg_job_data[3];
  assign csr_job_data[511:480] = reg_job_data[4];  assign csr_job_data[479:448] = reg_job_data[5];
  assign csr_job_data[447:416] = reg_job_data[6];  assign csr_job_data[415:384] = reg_job_data[7];
  assign csr_job_data[383:352] = reg_job_data[8];  assign csr_job_data[351:320] = reg_job_data[9];
  assign csr_job_data[319:288] = reg_job_data[10]; assign csr_job_data[287:256] = reg_job_data[11];
  assign csr_job_data[255:224] = reg_job_data[12]; assign csr_job_data[223:192] = reg_job_data[13];
  assign csr_job_data[191:160] = reg_job_data[14]; assign csr_job_data[159:128] = reg_job_data[15];
  assign csr_job_data[127:96]  = reg_job_data[16]; assign csr_job_data[95:64]  = reg_job_data[17];
  assign csr_job_data[63:32]   = reg_job_data[18]; assign csr_job_data[31:0]   = reg_job_data[19];
endmodule
