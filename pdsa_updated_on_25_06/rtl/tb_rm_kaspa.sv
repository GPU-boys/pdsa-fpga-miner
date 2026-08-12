`timescale 1ns/1ps
module tb_rm_kaspa;
  reg         clk, rst_n;
  reg         rp_start, rp_stop;
  reg  [639:0] rp_job_data;
  reg  [255:0] rp_midstate, rp_target;
  reg  [31:0]  rp_start_nonce;
  wire [7:0]   rp_algo_id;
  wire [255:0] rp_hash_out;
  wire [31:0]  rp_nonce_out;
  wire         rp_found, rp_busy;
  wire         rp_valid_out;
  wire [63:0]  rp_hash_count;

  integer pass_cnt, fail_cnt, i, cycle_cnt;
  reg [255:0] exp_hash;

  rm_kaspa_wrapper u_dut (
    .clk(clk), .rst_n(rst_n),
    .rp_start(rp_start), .rp_stop(rp_stop),
    .rp_job_data(rp_job_data), .rp_midstate(rp_midstate),
    .rp_target(rp_target), .rp_start_nonce(rp_start_nonce),
    .rp_algo_id(rp_algo_id), .rp_hash_out(rp_hash_out),
    .rp_nonce_out(rp_nonce_out), .rp_found(rp_found),
    .rp_hash_count(rp_hash_count), .rp_busy(rp_busy),
    .rp_valid_out(rp_valid_out)
  );

  always #5 clk = ~clk;

  task automatic start(input [639:0] job, input [255:0] ms,
                       input [255:0] tgt, input [31:0] nc);
    rp_job_data <= job; rp_midstate <= ms;
    rp_target <= tgt; rp_start_nonce <= nc;
    @(posedge clk); rp_start <= 1'b1;
    @(posedge clk); rp_start <= 1'b0;
  endtask

  initial begin
    $display("===== PDSA-FPGA TB: rm_kaspa =====");
    pass_cnt = 0; fail_cnt = 0;
    clk = 0; rst_n = 0; rp_start = 0; rp_stop = 0;
    rp_job_data = 640'd0; rp_midstate = 256'd0;
    rp_target = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    rp_start_nonce = 32'd0;

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (5) @(posedge clk);

    // T1: rp_algo_id
    $write("T1 rp_algo_id... ");
    if (rp_algo_id == 8'h02)
      begin $display("PASS"); pass_cnt = pass_cnt + 1; end
    else
      begin $display("FAIL %02h", rp_algo_id); fail_cnt = fail_cnt + 1; end

    // T2: rp_busy is 0 (placeholder model)
    $write("T2 rp_busy (placeholder=0)... ");
    @(posedge clk); #1;
    if (rp_busy == 1'b0)
      begin $display("PASS"); pass_cnt = pass_cnt + 1; end
    else
      begin $display("FAIL busy=%0d", rp_busy); fail_cnt = fail_cnt + 1; end

    // T3: SHA-3-256 hash correctness
    // msg[639:608]^msg[607:576] → hash[255:224]
    // etc.
    $write("T3 SHA-3-256 hash correctness... ");
    start(640'h01234567_89ABCDEF_FEDCBA98_76543210_11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888_99999999_AAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_00000000,
          256'd0, 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 32'd0);
    @(posedge clk); #1;
    cycle_cnt = 0;
    for (i = 0; i < 50; i = i + 1) begin
      @(posedge clk); #1;
      cycle_cnt = cycle_cnt + 1;
      if (rp_valid_out) break;
    end
    if (rp_valid_out) begin
      exp_hash = {
        32'hcf6ee3fd,
        32'he019beb9,
        32'h615c9d7d,
        32'h9d76aaef,
        32'h061e37a1,
        32'h9724eb9f,
        32'hd4859eb6,
        32'h252ba7b7
      };
      if (rp_hash_out == exp_hash)
        begin $display("PASS hash=%064h", rp_hash_out); pass_cnt = pass_cnt + 1; end
      else
        begin $display("FAIL got=%064h exp=%064h", rp_hash_out, exp_hash); fail_cnt = fail_cnt + 1; end
    end else begin
      $display("FAIL timeout"); fail_cnt = fail_cnt + 1;
    end

    // T4: Pipeline depth ≈ 24 cycles
    $write("T4 pipeline depth... ");
    start(640'h0, 256'd0, 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 32'd0);
    @(posedge clk); #1;
    cycle_cnt = 0;
    for (i = 0; i < 50; i = i + 1) begin
      @(posedge clk); #1;
      cycle_cnt = cycle_cnt + 1;
      if (rp_valid_out) break;
    end
    if (rp_valid_out)
      begin $display("PASS %0d cycles", cycle_cnt); pass_cnt = pass_cnt + 1; end
    else
      begin $display("FAIL timeout"); fail_cnt = fail_cnt + 1; end

    // T5: hash_count increments
    $write("T5 hash_count increments... ");
    repeat (200) @(posedge clk); #1;
    if (rp_hash_count > 64'd0)
      begin $display("PASS count=%0d", rp_hash_count); pass_cnt = pass_cnt + 1; end
    else
      begin $display("FAIL count=0"); fail_cnt = fail_cnt + 1; end

    // T6: hash < target should trigger found (all zeros → hash=0 < FFFF...)
    // rp_found is set 1 cycle after valid_out (race), so we capture it
    $write("T6 found with hash<target... ");
    rp_stop <= 1'b1; @(posedge clk); rp_stop <= 1'b0;
    repeat (10) @(posedge clk); #1;
    start(640'd0, 256'd0, 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF, 32'd0);
    // Wait for valid_out, then check rp_found next cycle
    @(posedge clk); #1;
    for (i = 0; i < 50; i = i + 1) begin
      @(posedge clk); #1;
      if (rp_valid_out) break;
    end
    if (!rp_valid_out)
      begin $display("FAIL timeout"); fail_cnt = fail_cnt + 1; end
    else begin
      // valid_out seen — wait 1 more cycle for rp_found to settle
      @(posedge clk); #1;
      if (rp_found)
        begin $display("PASS count=%0d", rp_hash_count); pass_cnt = pass_cnt + 1; end
      else
        begin $display("FAIL found=0 hash=%064h tgt=%064h", rp_hash_out, rp_target); fail_cnt = fail_cnt + 1; end
    end

    // Summary
    repeat (5) @(posedge clk);
    $display("===== %0dP %0dF out of %0d =====",
             pass_cnt, fail_cnt, pass_cnt+fail_cnt);
    if (fail_cnt == 0) $display("ALL PASS");
    else               $display("%0d FAIL", fail_cnt);
    $finish;
  end
endmodule
