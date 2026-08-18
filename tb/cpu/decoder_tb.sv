`timescale 1ns/1ps

module decoder_tb;

  logic [31:0]        instr;

  logic [4:0]         rs1;
  logic [4:0]         rs2;
  logic [4:0]         rd;

  cpu_pkg::alu_op_e   alu_op;
  cpu_pkg::imm_type_e imm_type;
  cpu_pkg::wb_sel_e   wb_sel;

  logic               reg_we;
  logic               mem_re;
  logic               mem_we;
  logic               alu_src_imm;
  logic               branch_eq;
  logic               illegal_instr;

  int unsigned num_tests;
  int unsigned num_fails;
  int unsigned random_seed;

  decoder dut (
    .instr         (instr),
    .rs1           (rs1),
    .rs2           (rs2),
    .rd            (rd),
    .alu_op        (alu_op),
    .imm_type      (imm_type),
    .wb_sel        (wb_sel),
    .reg_we        (reg_we),
    .mem_re        (mem_re),
    .mem_we        (mem_we),
    .alu_src_imm   (alu_src_imm),
    .branch_eq     (branch_eq),
    .illegal_instr (illegal_instr)
  );

  function automatic logic [31:0] make_r_instr(
    input logic [6:0] funct7,
    input logic [4:0] rs2_in,
    input logic [4:0] rs1_in,
    input logic [2:0] funct3,
    input logic [4:0] rd_in
  );
    make_r_instr = {
      funct7,
      rs2_in,
      rs1_in,
      funct3,
      rd_in,
      7'b0110011
    };
  endfunction

  function automatic logic [31:0] make_i_instr(
    input logic [11:0] imm12,
    input logic [4:0]  rs1_in,
    input logic [2:0]  funct3,
    input logic [4:0]  rd_in,
    input logic [6:0]  opcode
  );
    make_i_instr = {
      imm12,
      rs1_in,
      funct3,
      rd_in,
      opcode
    };
  endfunction

  function automatic logic [31:0] make_s_instr(
    input logic [11:0] imm12,
    input logic [4:0]  rs2_in,
    input logic [4:0]  rs1_in,
    input logic [2:0]  funct3
  );
    make_s_instr = {
      imm12[11:5],
      rs2_in,
      rs1_in,
      funct3,
      imm12[4:0],
      7'b0100011
    };
  endfunction

  function automatic logic [31:0] make_b_instr(
    input logic [12:1] imm_b,
    input logic [4:0]  rs2_in,
    input logic [4:0]  rs1_in,
    input logic [2:0]  funct3
  );
    logic [31:0] temp_instr;

    temp_instr = 32'h0000_0063;
    temp_instr[31]    = imm_b[12];
    temp_instr[7]     = imm_b[11];
    temp_instr[30:25] = imm_b[10:5];
    temp_instr[24:20] = rs2_in;
    temp_instr[19:15] = rs1_in;
    temp_instr[14:12] = funct3;
    temp_instr[11:8]  = imm_b[4:1];
    temp_instr[6:0]   = 7'b1100011;

    make_b_instr = temp_instr;
  endfunction

  task automatic check_decode(
    input logic [31:0]        test_instr,
    input cpu_pkg::alu_op_e   exp_alu_op,
    input cpu_pkg::imm_type_e exp_imm_type,
    input cpu_pkg::wb_sel_e   exp_wb_sel,
    input logic               exp_reg_we,
    input logic               exp_mem_re,
    input logic               exp_mem_we,
    input logic               exp_alu_src_imm,
    input logic               exp_branch_eq,
    input logic               exp_illegal_instr
  );
    instr = test_instr;

    #1;

    num_tests++;

    assert (rs1 === test_instr[19:15])
      else begin
        $error("rs1 mismatch: expected=%0d got=%0d", test_instr[19:15], rs1);
        num_fails++;
      end

    assert (rs2 === test_instr[24:20])
      else begin
        $error("rs2 mismatch: expected=%0d got=%0d", test_instr[24:20], rs2);
        num_fails++;
      end

    assert (rd === test_instr[11:7])
      else begin
        $error("rd mismatch: expected=%0d got=%0d", test_instr[11:7], rd);
        num_fails++;
      end

    assert (alu_op === exp_alu_op)
      else begin
        $error("alu_op mismatch: instr=%h expected=%0d got=%0d",
               test_instr, exp_alu_op, alu_op);
        num_fails++;
      end

    assert (imm_type === exp_imm_type)
      else begin
        $error("imm_type mismatch: instr=%h expected=%0d got=%0d",
               test_instr, exp_imm_type, imm_type);
        num_fails++;
      end

    assert (wb_sel === exp_wb_sel)
      else begin
        $error("wb_sel mismatch: instr=%h expected=%0d got=%0d",
               test_instr, exp_wb_sel, wb_sel);
        num_fails++;
      end

    assert (reg_we === exp_reg_we)
      else begin
        $error("reg_we mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_reg_we, reg_we);
        num_fails++;
      end

    assert (mem_re === exp_mem_re)
      else begin
        $error("mem_re mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_mem_re, mem_re);
        num_fails++;
      end

    assert (mem_we === exp_mem_we)
      else begin
        $error("mem_we mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_mem_we, mem_we);
        num_fails++;
      end

    assert (alu_src_imm === exp_alu_src_imm)
      else begin
        $error("alu_src_imm mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_alu_src_imm, alu_src_imm);
        num_fails++;
      end

    assert (branch_eq === exp_branch_eq)
      else begin
        $error("branch_eq mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_branch_eq, branch_eq);
        num_fails++;
      end

    assert (illegal_instr === exp_illegal_instr)
      else begin
        $error("illegal_instr mismatch: instr=%h expected=%b got=%b",
               test_instr, exp_illegal_instr, illegal_instr);
        num_fails++;
      end
  endtask

  initial begin
    logic [31:0] rand_instr;

    $dumpfile("decoder_tb.vcd");
    $dumpvars(0, decoder_tb);

    num_tests = 0;
    num_fails = 0;
    random_seed = 32'hA1A0_0004;
    if ($value$plusargs("SEED=%d", random_seed)) begin
      $display("DECODER random seed: %0d (0x%08h)", random_seed, random_seed);
    end else begin
      $display("DECODER random seed: %0d (0x%08h)", random_seed, random_seed);
    end
    void'($urandom(random_seed));

    $display("Starting decoder directed tests...");

    // R-type instructions
    check_decode(
      make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3),
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    );

    check_decode(
      make_r_instr(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3),
      cpu_pkg::ALU_SUB, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    );

    check_decode(
      make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3),
      cpu_pkg::ALU_AND, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    );

    check_decode(
      make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd3),
      cpu_pkg::ALU_OR, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    );

    check_decode(
      make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd3),
      cpu_pkg::ALU_XOR, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0
    );

    // I-type ALU instructions
    check_decode(
      make_i_instr(12'h123, 5'd1, 3'b000, 5'd3, 7'b0010011),
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0
    );

    check_decode(
      make_i_instr(12'h123, 5'd1, 3'b111, 5'd3, 7'b0010011),
      cpu_pkg::ALU_AND, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0
    );

    check_decode(
      make_i_instr(12'h123, 5'd1, 3'b110, 5'd3, 7'b0010011),
      cpu_pkg::ALU_OR, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0
    );

    check_decode(
      make_i_instr(12'h123, 5'd1, 3'b100, 5'd3, 7'b0010011),
      cpu_pkg::ALU_XOR, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0
    );

    // lw
    check_decode(
      make_i_instr(12'h020, 5'd1, 3'b010, 5'd3, 7'b0000011),
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_MEM,
      1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0
    );

    // sw
    check_decode(
      make_s_instr(12'h024, 5'd3, 5'd1, 3'b010),
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_S, cpu_pkg::WB_ALU,
      1'b0, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0
    );

    // beq
    check_decode(
      make_b_instr(12'h004, 5'd2, 5'd1, 3'b000),
      cpu_pkg::ALU_SUB, cpu_pkg::IMM_B, cpu_pkg::WB_ALU,
      1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0
    );

    // Unsupported I-type funct3
    check_decode(
      make_i_instr(12'h000, 5'd1, 3'b001, 5'd3, 7'b0010011),
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b1
    );

    // Invalid opcode
    check_decode(
      32'h0000_0000,
      cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
      1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1
    );

    $display("Starting decoder invalid-opcode random tests...");

    for (int i = 0; i < 100; i++) begin
      rand_instr = $urandom();
      rand_instr[6:0] = 7'b1111111;

      check_decode(
        rand_instr,
        cpu_pkg::ALU_ADD, cpu_pkg::IMM_I, cpu_pkg::WB_ALU,
        1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1
      );
    end

    if (num_fails == 0) begin
      $display("DECODER TEST PASSED: %0d tests run, %0d failures",
               num_tests, num_fails);
    end else begin
      $fatal(1, "DECODER TEST FAILED: %0d tests run, %0d failures",
             num_tests, num_fails);
    end

    $finish;
  end

endmodule
