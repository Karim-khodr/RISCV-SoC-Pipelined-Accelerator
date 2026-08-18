`timescale 1ns/1ps

module imm_gen_tb;

  logic [31:0]        instr;
  cpu_pkg::imm_type_e imm_type;
  logic [31:0]        imm;

  int unsigned num_tests;
  int unsigned num_fails;
  int unsigned random_seed;

  imm_gen dut (
    .instr    (instr),
    .imm_type (imm_type),
    .imm      (imm)
  );

  function automatic logic [31:0] make_i_instr(input logic [11:0] imm12);
    logic [31:0] temp_instr;
    temp_instr = 32'h0000_0013;
    temp_instr[31:20] = imm12;
    make_i_instr = temp_instr;
  endfunction

  function automatic logic [31:0] make_s_instr(input logic [11:0] imm12);
    logic [31:0] temp_instr;
    temp_instr = 32'h0000_0023;
    temp_instr[31:25] = imm12[11:5];
    temp_instr[11:7]  = imm12[4:0];
    make_s_instr = temp_instr;
  endfunction

  function automatic logic [31:0] make_b_instr(input logic [12:1] imm_b);
    logic [31:0] temp_instr;
    temp_instr = 32'h0000_0063;
    temp_instr[31]    = imm_b[12];
    temp_instr[7]     = imm_b[11];
    temp_instr[30:25] = imm_b[10:5];
    temp_instr[11:8]  = imm_b[4:1];
    make_b_instr = temp_instr;
  endfunction

  function automatic logic [31:0] ref_i(input logic [11:0] imm12);
    ref_i = {{20{imm12[11]}}, imm12};
  endfunction

  function automatic logic [31:0] ref_s(input logic [11:0] imm12);
    ref_s = {{20{imm12[11]}}, imm12};
  endfunction

  function automatic logic [31:0] ref_b(input logic [12:1] imm_b);
    ref_b = {{19{imm_b[12]}}, imm_b, 1'b0};
  endfunction

  task automatic check_imm (
    input logic [31:0]        test_instr,
    input cpu_pkg::imm_type_e test_type,
    input logic [31:0]        expected_imm
  );
    instr    = test_instr;
    imm_type = test_type;

    #1;

    num_tests++;

    assert (imm === expected_imm)
      else begin
        $error("IMM mismatch: type=%0d instr=%h expected=%h got=%h",
               test_type, test_instr, expected_imm, imm);
        num_fails++;
      end
  endtask

  initial begin
    logic [11:0] rand_imm12;
    logic [12:1] rand_imm_b;

    $dumpfile("imm_gen_tb.vcd");
    $dumpvars(0, imm_gen_tb);

    num_tests = 0;
    num_fails = 0;
    random_seed = 32'hA1A0_0003;
    if ($value$plusargs("SEED=%d", random_seed)) begin
      $display("IMM_GEN random seed: %0d (0x%08h)", random_seed, random_seed);
    end else begin
      $display("IMM_GEN random seed: %0d (0x%08h)", random_seed, random_seed);
    end
    void'($urandom(random_seed));

    $display("Starting immediate generator directed tests...");

    check_imm(make_i_instr(12'h000), cpu_pkg::IMM_I, ref_i(12'h000));
    check_imm(make_i_instr(12'h001), cpu_pkg::IMM_I, ref_i(12'h001));
    check_imm(make_i_instr(12'h7FF), cpu_pkg::IMM_I, ref_i(12'h7FF));
    check_imm(make_i_instr(12'h800), cpu_pkg::IMM_I, ref_i(12'h800));
    check_imm(make_i_instr(12'hFFF), cpu_pkg::IMM_I, ref_i(12'hFFF));

    check_imm(make_s_instr(12'h000), cpu_pkg::IMM_S, ref_s(12'h000));
    check_imm(make_s_instr(12'h004), cpu_pkg::IMM_S, ref_s(12'h004));
    check_imm(make_s_instr(12'h800), cpu_pkg::IMM_S, ref_s(12'h800));
    check_imm(make_s_instr(12'hFFF), cpu_pkg::IMM_S, ref_s(12'hFFF));

    check_imm(make_b_instr(12'h000), cpu_pkg::IMM_B, ref_b(12'h000));
    check_imm(make_b_instr(12'h002), cpu_pkg::IMM_B, ref_b(12'h002));
    check_imm(make_b_instr(12'h7FF), cpu_pkg::IMM_B, ref_b(12'h7FF));
    check_imm(make_b_instr(12'h800), cpu_pkg::IMM_B, ref_b(12'h800));
    check_imm(make_b_instr(12'hFFF), cpu_pkg::IMM_B, ref_b(12'hFFF));

    $display("Starting immediate generator random tests...");

    for (int i = 0; i < 500; i++) begin
      rand_imm12 = 12'($urandom());
      check_imm(make_i_instr(rand_imm12), cpu_pkg::IMM_I, ref_i(rand_imm12));

      rand_imm12 = 12'($urandom());
      check_imm(make_s_instr(rand_imm12), cpu_pkg::IMM_S, ref_s(rand_imm12));

      rand_imm_b = 12'($urandom());
      check_imm(make_b_instr(rand_imm_b), cpu_pkg::IMM_B, ref_b(rand_imm_b));
    end

    if (num_fails == 0) begin
      $display("IMM_GEN TEST PASSED: %0d tests run, %0d failures",
               num_tests, num_fails);
    end else begin
      $fatal(1, "IMM_GEN TEST FAILED: %0d tests run, %0d failures",
             num_tests, num_fails);
    end

    $finish;
  end

endmodule
