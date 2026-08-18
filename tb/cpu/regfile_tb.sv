`timescale 1ns/1ps

module regfile_tb;

  logic        clk    = 1'b0;
  logic        rst_n  = 1'b0;
  logic        we     = 1'b0;
  logic [4:0]  waddr  = 5'd0;
  logic [31:0] wdata  = 32'd0;
  logic [4:0]  raddr1 = 5'd0;
  logic [4:0]  raddr2 = 5'd0;
  logic [31:0] rdata1;
  logic [31:0] rdata2;

  logic [31:0] ref_regs [31:0];

  int unsigned num_tests;
  int unsigned num_fails;
  int unsigned random_seed;

  regfile dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .we     (we),
    .waddr  (waddr),
    .wdata  (wdata),
    .raddr1 (raddr1),
    .raddr2 (raddr2),
    .rdata1 (rdata1),
    .rdata2 (rdata2)
  );

  always #5 clk <= ~clk;

  function automatic logic [31:0] ref_read(input logic [4:0] addr);
    if (addr == 5'd0) begin
      ref_read = 32'd0;
    end else begin
      ref_read = ref_regs[addr];
    end
  endfunction

function automatic logic [4:0] rand_reg();
  rand_reg = 5'($urandom_range(0, 31));
endfunction

  task automatic check_read(
    input logic [4:0] test_raddr1,
    input logic [4:0] test_raddr2
  );
    logic [31:0] expected_rdata1;
    logic [31:0] expected_rdata2;

    raddr1 = test_raddr1;
    raddr2 = test_raddr2;

    #1;

    expected_rdata1 = ref_read(test_raddr1);
    expected_rdata2 = ref_read(test_raddr2);

    num_tests++;

    assert (rdata1 === expected_rdata1)
      else begin
        $error("rdata1 mismatch: raddr1=%0d expected=%h got=%h",
               test_raddr1, expected_rdata1, rdata1);
        num_fails++;
      end

    assert (rdata2 === expected_rdata2)
      else begin
        $error("rdata2 mismatch: raddr2=%0d expected=%h got=%h",
               test_raddr2, expected_rdata2, rdata2);
        num_fails++;
      end
  endtask

  task automatic do_write(
    input logic        test_we,
    input logic [4:0]  test_waddr,
    input logic [31:0] test_wdata
  );
    @(negedge clk);

    we    = test_we;
    waddr = test_waddr;
    wdata = test_wdata;

    @(posedge clk);
    #1;

    if (test_we && (test_waddr != 5'd0)) begin
      ref_regs[test_waddr] = test_wdata;
    end

    ref_regs[0] = 32'd0;

    @(negedge clk);
    we = 1'b0;
  endtask

  initial begin
    $dumpfile("regfile_tb.vcd");
    $dumpvars(0, regfile_tb);

    num_tests = 0;
    num_fails = 0;
    random_seed = 32'hA1A0_0002;
    if ($value$plusargs("SEED=%d", random_seed)) begin
      $display("REGFILE random seed: %0d (0x%08h)", random_seed, random_seed);
    end else begin
      $display("REGFILE random seed: %0d (0x%08h)", random_seed, random_seed);
    end
    void'($urandom(random_seed));

    for (int i = 0; i < 32; i++) begin
      ref_regs[i] = 32'd0;
    end

    $display("Starting register file tests...");

    rst_n = 1'b0;
    repeat (2) @(posedge clk);
    #1;
    rst_n = 1'b1;

    check_read(5'd0, 5'd1);

    do_write(1'b1, 5'd1, 32'hDEAD_BEEF);
    check_read(5'd1, 5'd0);

    do_write(1'b1, 5'd2, 32'hCAFE_BABE);
    check_read(5'd1, 5'd2);

    do_write(1'b1, 5'd0, 32'hFFFF_FFFF);
    check_read(5'd0, 5'd1);

    do_write(1'b0, 5'd3, 32'h1234_5678);
    check_read(5'd3, 5'd2);

    do_write(1'b1, 5'd1, 32'h1111_2222);
    check_read(5'd1, 5'd2);

    $display("Starting register file random tests...");

    for (int i = 0; i < 500; i++) begin
      do_write(
        1'($urandom_range(0, 1)),
        rand_reg(),
        $urandom()
    );

      check_read(rand_reg(), rand_reg());
    end

    if (num_fails == 0) begin
      $display("REGFILE TEST PASSED: %0d tests run, %0d failures",
               num_tests, num_fails);
    end else begin
      $fatal(1, "REGFILE TEST FAILED: %0d tests run, %0d failures",
             num_tests, num_fails);
    end

    $finish;
  end

endmodule
