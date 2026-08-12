`timescale 1ns/1ps
module pdsa_static_shell (
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
  output wire          rp_start,
  output wire          rp_stop,
  output wire [639:0]  rp_job_data,
  output wire [255:0]  rp_midstate,
  output wire [255:0]  rp_target,
  output wire [31:0]   rp_start_nonce,
  input  wire [7:0]    rp_algo_id,
  input  wire [255:0]  rp_hash_out,
  input  wire [31:0]   rp_nonce_out,
  input  wire          rp_found,
  input  wire [63:0]   rp_hash_count,
  input  wire          rp_busy,
  input  wire          rp_valid_out,
  output wire          irq_found,
  output wire          irq_dpr_done
);
  wire        csr_start, csr_stop, csr_decouple, csr_trigger_dpr;
  wire [7:0]  csr_algo_sel;
  wire [31:0] csr_start_nonce;
  wire [31:0] csr_pt_threshold, csr_pt_current, csr_bcv_status;
  wire [255:0] csr_target, csr_midstate;
  wire [639:0] csr_job_data;

  reg         result_found;
  reg [31:0]  result_nonce;
  reg [255:0] result_hash;

  reg [31:0] hr_counter, hr_snapshot, hr_window;
  localparam [31:0] HR_WINDOW = 32'd100_000_000;

  reg [31:0] dpr_timer, dpr_latency;
  reg        dpr_was_active;

  reg [7:0] pdsa_decision;
  localparam [7:0] PDSA_CONTINUE   = 8'h00;
  localparam [7:0] PDSA_SWITCH_PT  = 8'h01;
  localparam [7:0] PDSA_SWITCH_BCV = 8'h02;

  wire decoupled = csr_decouple;

  // dpr_in_progress driven internally by the decouple signal.
  // On KV260, DPR is managed by Linux FPGA Manager via PCAP (not PL ICAP),
  // so there is no dedicated PL signal. The decouple signal is asserted
  // by software before DPR and cleared after, giving accurate timing.
  wire dpr_in_progress = csr_decouple;

  assign rp_start       = decoupled ? 1'b0 : csr_start;
  assign rp_stop        = decoupled ? 1'b1 : csr_stop;
  assign rp_job_data    = decoupled ? 640'd0 : csr_job_data;
  assign rp_midstate    = decoupled ? 256'd0 : csr_midstate;
  assign rp_target      = decoupled ? 256'd0 : csr_target;
  assign rp_start_nonce = decoupled ? 32'd0 : csr_start_nonce;

  axi_lite_csr u_csr (
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
    .csr_start(csr_start), .csr_stop(csr_stop),
    .csr_decouple(csr_decouple), .csr_trigger_dpr(csr_trigger_dpr),
    .csr_algo_sel(csr_algo_sel), .csr_start_nonce(csr_start_nonce),
    .csr_target(csr_target), .csr_midstate(csr_midstate),
    .csr_job_data(csr_job_data),
    .csr_pt_threshold(csr_pt_threshold),
    .csr_pt_current(csr_pt_current),
    .csr_bcv_status(csr_bcv_status),
    .sts_result_hash(result_hash),
    .sts_busy(rp_busy), .sts_found(result_found),
    .sts_decoupled(decoupled), .sts_dpr_active(dpr_in_progress),
    .sts_algo_id(rp_algo_id),
    .sts_hash_count(rp_hash_count),
    .sts_golden_nonce(result_nonce),
    .sts_dpr_latency(dpr_latency),
    .sts_hashrate(hr_snapshot),
    .sts_pdsa_decision(pdsa_decision)
  );

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result_found <= 1'b0; result_nonce <= 32'd0; result_hash <= 256'd0;
    end else begin
      if (csr_start) result_found <= 1'b0;
      else if (rp_found && !decoupled) begin
        result_found <= 1'b1;
        result_nonce <= rp_nonce_out;
        result_hash  <= rp_hash_out;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      hr_counter <= 32'd0; hr_snapshot <= 32'd0; hr_window <= 32'd0;
    end else begin
      if (hr_window >= HR_WINDOW) begin
        hr_snapshot <= hr_counter; hr_counter <= 32'd0; hr_window <= 32'd0;
      end else begin
        hr_window <= hr_window + 32'd1;
        if (rp_valid_out && !decoupled) hr_counter <= hr_counter + 32'd1;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dpr_timer <= 32'd0; dpr_latency <= 32'd0; dpr_was_active <= 1'b0;
    end else begin
      dpr_was_active <= dpr_in_progress;
      if (dpr_in_progress) dpr_timer <= dpr_timer + 32'd1;
      else if (dpr_was_active && !dpr_in_progress) begin
        dpr_latency <= dpr_timer; dpr_timer <= 32'd0;
      end
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) pdsa_decision <= PDSA_CONTINUE;
    else begin
      if (csr_bcv_status == 32'd2)
        pdsa_decision <= PDSA_SWITCH_BCV;
      else if (csr_pt_current < csr_pt_threshold)
        pdsa_decision <= PDSA_SWITCH_PT;
      else
        pdsa_decision <= PDSA_CONTINUE;
    end
  end

  assign irq_found    = result_found;
  assign irq_dpr_done = dpr_was_active && !dpr_in_progress;
endmodule
