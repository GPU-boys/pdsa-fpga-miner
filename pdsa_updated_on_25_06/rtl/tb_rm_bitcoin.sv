`timescale 1ns/1ps
module tb_rm_bitcoin;
  reg clk, rst_n;
  reg rp_start, rp_stop;
  reg [639:0] rp_job_data;
  reg [255:0] rp_midstate, rp_target;
  reg [31:0]  rp_start_nonce;
  wire [7:0]  rp_algo_id;
  wire [255:0] rp_hash_out;
  wire [31:0] rp_nonce_out;
  wire        rp_found;
  wire [63:0] rp_hash_count;
  wire        rp_busy;
  wire        rp_valid_out;

  rm_bitcoin #(.NUM_ENGINES(20)) u_dut (
    .clk(clk), .rst_n(rst_n),
    .rp_start(rp_start), .rp_stop(rp_stop),
    .rp_algo_id(rp_algo_id),
    .rp_job_data(rp_job_data), .rp_midstate(rp_midstate),
    .rp_target(rp_target), .rp_start_nonce(rp_start_nonce),
    .rp_hash_out(rp_hash_out), .rp_nonce_out(rp_nonce_out),
    .rp_found(rp_found), .rp_hash_count(rp_hash_count),
    .rp_busy(rp_busy), .rp_valid_out(rp_valid_out)
  );

  localparam CLK_PERIOD = 10;
  always #(CLK_PERIOD / 2) clk = ~clk;

  reg [255:0] ref_iv;
  reg [511:0] ref_blk1, ref_blk2;
  wire [255:0] ref_digest1, ref_digest2;
  wire ref_done1, ref_done2, ref_busy1, ref_busy2;
  reg ref_start1, ref_start2;
  reg [255:0] ref_first_hash, ref_double_hash;
  reg ref_hash_valid;
  reg ref_go;

  localparam [255:0] SHA256_IV = {
    32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
    32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
  };

  sha256_core_baseline u_ref1 (
    .clk(clk), .rst_n(rst_n),
    .start(ref_start1), .iv(ref_iv), .block_data(ref_blk1),
    .busy(ref_busy1), .done(ref_done1), .digest(ref_digest1)
  );
  sha256_core_baseline u_ref2 (
    .clk(clk), .rst_n(rst_n),
    .start(ref_start2), .iv(SHA256_IV), .block_data(ref_blk2),
    .busy(ref_busy2), .done(ref_done2), .digest(ref_digest2)
  );

  reg [255:0] midstate_ref, merkle_tail_ref, timestamp_ref, bits_ref;
  reg [31:0] ref_nonce_reg;
  reg ref_done1_d1;
  wire ref_done1_pe = ref_done1 && !ref_done1_d1;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ref_start1 <= 1'b0; ref_start2 <= 1'b0;
      ref_hash_valid <= 1'b0; ref_double_hash <= 256'd0;
      ref_nonce_reg <= 32'd0;
      ref_done1_d1 <= 1'b0;
    end else begin
      ref_start1 <= 1'b0; ref_start2 <= 1'b0;
      ref_hash_valid <= 1'b0;
      ref_done1_d1 <= ref_done1;
      if (rp_start) begin
        ref_iv <= rp_midstate;
        ref_nonce_reg <= rp_start_nonce;
      end
      if (rp_start || ref_go) begin
        ref_blk1 <= {rp_job_data[639:608], rp_job_data[607:576],
                     rp_job_data[575:544], ref_nonce_reg,
                     32'h80000000, 288'd0, 32'd0, 32'h00000280};
        ref_start1 <= 1'b1;
      end
      if (ref_done1_pe) begin
        ref_first_hash <= ref_digest1;
        ref_blk2 <= {ref_digest1, 32'h80000000, 192'd0, 32'h00000100};
        ref_start2 <= 1'b1;
      end
      if (ref_done2) begin
        ref_double_hash <= ref_digest2;
        ref_hash_valid <= 1'b1;
      end
    end
  end

  integer pass, fail;
  reg [255:0] captured_hash;
  reg [31:0] captured_nonce;
  reg [31:0] debug_cycle;

  task init;
    clk = 0; rst_n = 0;
    rp_start = 0; rp_stop = 0;
    rp_job_data = 0; rp_midstate = 0;
    rp_target = 0; rp_start_nonce = 0;
    pass = 0; fail = 0;
  endtask

  task reset;
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk);
  endtask

  task start_job(input [31:0] start_nonce);
    rp_start_nonce = start_nonce;
    @(posedge clk); #1;
    rp_start = 1;
    @(posedge clk); #1;
    rp_start = 0;
  endtask

  task stop_job;
    @(posedge clk); #1;
    rp_stop = 1;
    @(posedge clk); #1;
    rp_stop = 0;
  endtask

  initial begin
    $display("===== PDSA-FPGA TB: rm_bitcoin (real SHA-256d, ENGINES=20) =====");
    init; reset;

    rp_midstate = SHA256_IV;
    rp_job_data[639:608] = 32'hAABBCCDD;
    rp_job_data[607:576] = 32'hAABBCCDE;
    rp_job_data[575:544] = 32'hAABBCCDF;
    rp_target = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;

    // T1
    @(posedge clk); #1;
    if (rp_algo_id == 8'h01) begin
      $display("T1 rp_algo_id... PASS"); pass = pass + 1;
    end else begin
      $display("T1 rp_algo_id... FAIL"); fail = fail + 1;
    end

    // T2
    start_job(32'd0);
    @(posedge clk); #1;
    if (rp_busy) begin
      $display("T2 busy after start... PASS"); pass = pass + 1;
    end else begin
      $display("T2 busy after start... FAIL"); fail = fail + 1;
    end

    @(posedge clk); #1;
    @(posedge clk); #1;

    // T3
    start_job(32'd0);

    fork
      begin : timeout3
        repeat (500) @(posedge clk);
        $display("T3 valid_out timeout"); fail = fail + 1;
      end
      begin : wait_valid3
        while (!rp_valid_out) @(posedge clk);
        disable timeout3;
      end
    join
    #1;
    $display("T3 valid_out asserted... PASS"); pass = pass + 1;

    // T4
    #1;
    if (rp_hash_count > 64'd0) begin
      $display("T4 hash_count=%0d... PASS", rp_hash_count); pass = pass + 1;
    end else begin
      $display("T4 hash_count... FAIL"); fail = fail + 1;
    end
    stop_job;
    repeat (10) @(posedge clk); #1;

    // T5
    if (!rp_busy) begin
      $display("T5 stop de-asserts busy... PASS"); pass = pass + 1;
    end else begin
      $display("T5 stop de-asserts busy... FAIL"); fail = fail + 1;
    end

    // T6
    rp_target = 256'hFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF;
    start_job(32'd0);

    fork
      begin : timeout
        repeat (50000) @(posedge clk);
        $display("T6 timeout waiting for found");
        fail = fail + 1;
      end
      begin : wait_found
        while (!rp_found) @(posedge clk);
        disable timeout;
      end
    join
    #1;
    captured_hash = rp_hash_out;
    captured_nonce = rp_nonce_out;
    if (rp_found) begin
      $display("T6 found with hash<target... PASS nonce=0x%08x", captured_nonce);
      pass = pass + 1;
      $display("    hash=%08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x",
               captured_hash[255:224], captured_hash[223:192],
               captured_hash[191:160], captured_hash[159:128],
               captured_hash[127:96], captured_hash[95:64],
               captured_hash[63:32], captured_hash[31:0]);
      stop_job;
      // Verify hash: wait for any prior ref to finish, then restart
      if (ref_busy1 || ref_busy2) begin
        @(posedge ref_done2);
        #1;
      end
      ref_nonce_reg = captured_nonce;
      @(posedge clk); #1;
      ref_go = 1;
      @(posedge clk); #1;
      ref_go = 0;
      // Wait for ref computation to complete (max ~200 cycles)
      fork
        begin : ref_timeout
          repeat (1000) @(posedge clk);
          $display("T6 ref timeout"); fail = fail + 1;
        end
        begin : ref_wait
          @(posedge ref_done2);
          @(posedge clk); // wait one more cycle for ref model to capture digest
          disable ref_timeout;
        end
      join
      #1;
      if (ref_double_hash == captured_hash) begin
        $display("T6 hash matches golden reference... PASS");
        pass = pass + 1;
      end else begin
        $display("T6 hash MISMATCH (ref=%08x_%08x)... FAIL",
                 ref_double_hash[255:224], ref_double_hash[223:192]);
        fail = fail + 1;
      end
    end else begin
      $display("T6 found... FAIL"); fail = fail + 1;
      stop_job;
    end

    // T7 NIST KAT: SHA-256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
    // Two-block message (448 bits): step1 compresses block0, step2 chains result into block1
    $display("T7 NIST KAT multi-block (2-step)...");
    @(posedge clk); #1;
    rp_target = 256'd0;
    rp_midstate = SHA256_IV;

    rp_job_data[511:480] = 32'h61626364;
    rp_job_data[479:448] = 32'h62636465;
    rp_job_data[447:416] = 32'h63646566;
    rp_job_data[415:384] = 32'h64656667;
    rp_job_data[383:352] = 32'h65666768;
    rp_job_data[351:320] = 32'h66676869;
    rp_job_data[319:288] = 32'h6768696A;
    rp_job_data[287:256] = 32'h68696A6B;
    rp_job_data[255:224] = 32'h696A6B6C;
    rp_job_data[223:192] = 32'h6A6B6C6D;
    rp_job_data[191:160] = 32'h6B6C6D6E;
    rp_job_data[159:128] = 32'h6C6D6E6F;
    rp_job_data[127:96]  = 32'h6D6E6F70;
    rp_job_data[95:64]   = 32'h6E6F7071;
    rp_job_data[63:32]   = 32'h80000000;
    rp_job_data[31:0]    = 32'h00000000;  // block0: no length yet

    @(posedge clk); #1;
    rp_start = 1;
    @(posedge clk); #1;
    rp_start = 0;

    fork
      begin : kat_timeout7a
        repeat (500) @(posedge clk);
        $display("T7 step1 timeout"); fail = fail + 1;
      end
      begin : kat_wait7a
        while (!rp_found) @(posedge clk);
        disable kat_timeout7a;
      end
    join
    #1;
    if (!rp_found) begin
      $display("T7 step1 not found"); fail = fail + 1;
    end else begin
      rp_midstate = rp_hash_out;  // chain digest as IV for block1

      rp_job_data[511:480] = 32'h00000000;
      rp_job_data[479:448] = 32'h00000000;
      rp_job_data[447:416] = 32'h00000000;
      rp_job_data[415:384] = 32'h00000000;
      rp_job_data[383:352] = 32'h00000000;
      rp_job_data[351:320] = 32'h00000000;
      rp_job_data[319:288] = 32'h00000000;
      rp_job_data[287:256] = 32'h00000000;
      rp_job_data[255:224] = 32'h00000000;
      rp_job_data[223:192] = 32'h00000000;
      rp_job_data[191:160] = 32'h00000000;
      rp_job_data[159:128] = 32'h00000000;
      rp_job_data[127:96]  = 32'h00000000;
      rp_job_data[95:64]   = 32'h00000000;
      rp_job_data[63:32]   = 32'h00000000;
      rp_job_data[31:0]    = 32'h000001C0;

      @(posedge clk); #1;
      rp_start = 1;
      @(posedge clk); #1;
      rp_start = 0;

      fork
        begin : kat_timeout7b
          repeat (500) @(posedge clk);
          $display("T7 step2 timeout"); fail = fail + 1;
        end
        begin : kat_wait7b
          while (!rp_found) @(posedge clk);
          disable kat_timeout7b;
        end
      join
      #1;
      if (rp_found && rp_hash_out == 256'h248D6A61_D20638B8_E5C02693_0C3E6039_A33CE459_64FF2167_F6ECEDD4_19DB06C1) begin
        $display("T7 NIST SHA-256(multi-block)... PASS"); pass = pass + 1;
      end else if (!rp_found) begin
        $display("T7 step2 not found"); fail = fail + 1;
      end else begin
        $display("T7 NIST SHA-256(multi-block) MISMATCH");
        $display("    got:      %08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x",
                 rp_hash_out[255:224], rp_hash_out[223:192],
                 rp_hash_out[191:160], rp_hash_out[159:128],
                 rp_hash_out[127:96], rp_hash_out[95:64],
                 rp_hash_out[63:32], rp_hash_out[31:0]);
        $display("    expected: 248d6a61_d20638b8_e5c02693_0c3e6039_a33ce459_64ff2167_f6ecedd4_19db06c1");
        fail = fail + 1;
      end
    end

    // T8 NIST KAT: SHA-256("abc") = ba7816bf...
    $display("T8 NIST SHA-256(\"abc\")...");
    @(posedge clk); #1;
    rp_midstate = SHA256_IV;
    rp_job_data[511:480] = 32'h61626380;
    rp_job_data[479:448] = 32'h00000000;
    rp_job_data[447:416] = 32'h00000000;
    rp_job_data[415:384] = 32'h00000000;
    rp_job_data[383:352] = 32'h00000000;
    rp_job_data[351:320] = 32'h00000000;
    rp_job_data[319:288] = 32'h00000000;
    rp_job_data[287:256] = 32'h00000000;
    rp_job_data[255:224] = 32'h00000000;
    rp_job_data[223:192] = 32'h00000000;
    rp_job_data[191:160] = 32'h00000000;
    rp_job_data[159:128] = 32'h00000000;
    rp_job_data[127:96]  = 32'h00000000;
    rp_job_data[95:64]   = 32'h00000000;
    rp_job_data[63:32]   = 32'h00000000;
    rp_job_data[31:0]    = 32'h00000018;
    @(posedge clk); #1;
    rp_start = 1;
    @(posedge clk); #1;
    rp_start = 0;
    fork
      begin : kat_timeout8
        repeat (500) @(posedge clk);
        $display("T8 KAT timeout"); fail = fail + 1;
      end
      begin : kat_wait8
        while (!rp_found) @(posedge clk);
        disable kat_timeout8;
      end
    join
    #1;
    if (rp_found) begin
      if (rp_hash_out == 256'hBA7816BF_8F01CFEA_414140DE_5DAE2223_B00361A3_96177A9C_B410FF61_F20015AD) begin
        $display("T8 NIST SHA-256(\"abc\")... PASS"); pass = pass + 1;
      end else begin
        $display("T8 NIST SHA-256(\"abc\") MISMATCH");
        $display("    got:      %08x_%08x_%08x_%08x_%08x_%08x_%08x_%08x",
                 rp_hash_out[255:224], rp_hash_out[223:192],
                 rp_hash_out[191:160], rp_hash_out[159:128],
                 rp_hash_out[127:96], rp_hash_out[95:64],
                 rp_hash_out[63:32], rp_hash_out[31:0]);
        $display("    expected: ba7816bf_8f01cfea_414140de_5dae2223_b00361a3_96177a9c_b410ff61_f20015ad");
        fail = fail + 1;
      end
    end else begin
      $display("T8 NIST KAT not found"); fail = fail + 1;
    end

    $display("===== %0dP %0dF out of %0d =====", pass, fail, pass+fail);
    if (fail == 0) $display("ALL PASS");
    else           $display("SOME FAILED");
    $finish;
  end
endmodule
