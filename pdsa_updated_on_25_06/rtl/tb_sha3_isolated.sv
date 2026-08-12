`timescale 1ns/1ps
module tb_sha3_isolated;
  reg         clk, rst_n;
  reg  [639:0] msg;
  reg         valid_in, stop;
  wire [255:0] hash_out;
  wire         valid_out;

  sha3_256_pipe_engine_hp u_sha3 (
    .clk(clk), .rst_n(rst_n),
    .msg_80b(msg), .valid_in(valid_in), .stop(stop),
    .hash_out(hash_out), .valid_out(valid_out)
  );

  always #5 clk = ~clk;

    reg [255:0] exp_t3, exp_zero;

  initial begin
    $display("===== TB: sha3_256_pipe_engine_hp isolated =====");
    clk = 0; rst_n = 0; valid_in = 0; stop = 0;
    msg = 640'd0;

    exp_t3  = 256'hcf6ee3fde019beb9615c9d7d9d76aaef061e37a19724eb9fd4859eb6252ba7b7;
    exp_zero = 256'hc5fa98aca9ec66e1373a5a65d6d9d143b9b77465402fc4cf1bad038d0ca3f5fe;

    repeat (5) @(posedge clk);
    rst_n <= 1'b1;
    repeat (5) @(posedge clk);

    // Test 1: 80 zero bytes
    $display("--- Test 1: msg_80b = 0 (80 zero bytes) ---");
    msg <= 640'd0;
    valid_in <= 1'b1;
    @(posedge clk);
    valid_in <= 1'b0;

    repeat (30) begin
      @(posedge clk); #1;
      if (valid_out) begin
        if (hash_out == exp_zero)
          $display("PASS zero hash=%064h", hash_out);
        else
          $display("FAIL zero got=%064h exp=%064h", hash_out, exp_zero);
      end
    end

    // Test 2: reset and run T3 message
    $display("--- Test 2: Kaspa T3 message ---");
    stop <= 1'b1;
    @(posedge clk);
    stop <= 1'b0;
    repeat (5) @(posedge clk);

    msg <= 640'h01234567_89ABCDEF_FEDCBA98_76543210_11111111_22222222_33333333_44444444_55555555_66666666_77777777_88888888_99999999_AAAAAAAA_BBBBBBBB_CCCCCCCC_DDDDDDDD_EEEEEEEE_FFFFFFFF_00000000;
    valid_in <= 1'b1;
    @(posedge clk);
    valid_in <= 1'b0;

    repeat (30) begin
      @(posedge clk); #1;
      if (valid_out) begin
        if (hash_out == exp_t3)
          $display("PASS T3 hash=%064h", hash_out);
        else
          $display("FAIL T3 got=%064h exp=%064h", hash_out, exp_t3);
      end
    end

    $display("===== DONE =====");
    $finish;
  end
endmodule
