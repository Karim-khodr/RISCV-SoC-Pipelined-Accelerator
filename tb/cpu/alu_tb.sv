`timescale 1ns/1ps

module alu_tb;

  import cpu_pkg::*;

  logic [31:0] a;
  logic [31:0] b;
  alu_op_e     op;
  logic [31:0] y;
  logic        zero;

  int unsigned num_tests;
  int unsigned num_fails;
  int unsigned random_seed;

  alu dut (
    .a    (a),
    .b    (b),
    .op   (op),
    .y    (y),
    .zero (zero)
  );

  function automatic logic [31:0] alu_ref (
    input logic [31:0] ref_a,
    input logic [31:0] ref_b,
    input alu_op_e     ref_op
  );
    unique case (ref_op)
      ALU_ADD: alu_ref = ref_a + ref_b;
      ALU_SUB: alu_ref = ref_a - ref_b;
      ALU_AND: alu_ref = ref_a & ref_b;
      ALU_OR : alu_ref = ref_a | ref_b;
      ALU_XOR: alu_ref = ref_a ^ ref_b;
      default: alu_ref = 32'h0000_0000;
    endcase
  endfunction

  function automatic alu_op_e random_op();
    case ($urandom_range(0, 4))
      0: random_op = ALU_ADD;
      1: random_op = ALU_SUB;
      2: random_op = ALU_AND;
      3: random_op = ALU_OR;
      4: random_op = ALU_XOR;
      default: random_op = ALU_ADD;
    endcase
  endfunction

  task automatic check_alu (
    input logic [31:0] test_a,
    input logic [31:0] test_b,
    input alu_op_e     test_op
  );
    logic [31:0] expected_y;
    logic        expected_zero;

    a  = test_a;
    b  = test_b;
    op = test_op;

    #1;

    expected_y    = alu_ref(test_a, test_b, test_op);
    expected_zero = (expected_y == 32'd0);

    num_tests++;

    assert (y === expected_y)
      else begin
        $error("ALU mismatch: a=%h b=%h op=%0d expected=%h got=%h",
               test_a, test_b, test_op, expected_y, y);
        num_fails++;
      end

    assert (zero === expected_zero)
      else begin
        $error("ZERO mismatch: y=%h expected_zero=%b got_zero=%b",
               y, expected_zero, zero);
        num_fails++;
      end
  endtask

  initial begin
    $dumpfile("alu_tb.vcd");
    $dumpvars(0, alu_tb);

    num_tests = 0;
    num_fails = 0;
    random_seed = 32'hA1A0_0001;
    if ($value$plusargs("SEED=%d", random_seed)) begin
      $display("ALU random seed: %0d (0x%08h)", random_seed, random_seed);
    end else begin
      $display("ALU random seed: %0d (0x%08h)", random_seed, random_seed);
    end
    void'($urandom(random_seed));

    $display("Starting ALU directed tests...");

    check_alu(32'd1,        32'd1,        ALU_ADD);
    check_alu(32'd10,       32'd3,        ALU_SUB);
    check_alu(32'hFFFF0000, 32'h00FFFF00, ALU_AND);
    check_alu(32'hFFFF0000, 32'h00FFFF00, ALU_OR);
    check_alu(32'hAAAA5555, 32'hFFFF0000, ALU_XOR);

    check_alu(32'd0,        32'd0,        ALU_ADD);
    check_alu(32'd5,        32'd5,        ALU_SUB);
    check_alu(32'hFFFF_FFFF, 32'd1,       ALU_ADD);
    check_alu(32'd0,        32'd1,        ALU_SUB);

    $display("Starting ALU random tests...");

    for (int i = 0; i < 1000; i++) begin
      check_alu($urandom(), $urandom(), random_op());
    end

    if (num_fails == 0) begin
      $display("ALU TEST PASSED: %0d tests run, %0d failures",
               num_tests, num_fails);
    end else begin
      $fatal(1, "ALU TEST FAILED: %0d tests run, %0d failures",
             num_tests, num_fails);
    end

    $finish;
  end

endmodule
