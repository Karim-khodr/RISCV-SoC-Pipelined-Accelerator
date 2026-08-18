`timescale 1ns/1ps

module cpu_core_tb;

  logic clk   = 1'b0;
  logic rst_n = 1'b0;

  logic [31:0] pc_dbg;
  logic [31:0] instr_dbg;
  logic        illegal_instr_dbg;

  int unsigned num_fails;
  int unsigned fails_before;

  logic        trace_enable = 1'b0;
  int unsigned cycle_count;

  cpu_core dut (
    .clk               (clk),
    .rst_n             (rst_n),
    .pc_dbg            (pc_dbg),
    .instr_dbg         (instr_dbg),
    .illegal_instr_dbg (illegal_instr_dbg)
  );

  always_ff @(posedge clk) begin
    if (rst_n && trace_enable) begin
      $display("TRACE cycle=%0d pc=%h instr=%h illegal=%b",
              cycle_count, pc_dbg, instr_dbg, illegal_instr_dbg);
      cycle_count <= cycle_count + 1;
    end
  end

  always #5 clk <= ~clk;

  function automatic logic [31:0] make_r_instr(
    input logic [6:0] funct7,
    input logic [4:0] rs2,
    input logic [4:0] rs1,
    input logic [2:0] funct3,
    input logic [4:0] rd
  );
    make_r_instr = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
  endfunction

  function automatic logic [31:0] make_i_instr(
    input logic [11:0] imm12,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3,
    input logic [4:0]  rd,
    input logic [6:0]  opcode
  );
    make_i_instr = {imm12, rs1, funct3, rd, opcode};
  endfunction

  function automatic logic [31:0] make_s_instr(
    input logic [11:0] imm12,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3
  );
    make_s_instr = {
      imm12[11:5],
      rs2,
      rs1,
      funct3,
      imm12[4:0],
      7'b0100011
    };
  endfunction

  function automatic logic [31:0] make_b_instr(
    input logic [12:1] imm_b,
    input logic [4:0]  rs2,
    input logic [4:0]  rs1,
    input logic [2:0]  funct3
  );
    logic [31:0] temp_instr;

    temp_instr = 32'h0000_0063;
    temp_instr[31]    = imm_b[12];
    temp_instr[7]     = imm_b[11];
    temp_instr[30:25] = imm_b[10:5];
    temp_instr[24:20] = rs2;
    temp_instr[19:15] = rs1;
    temp_instr[14:12] = funct3;
    temp_instr[11:8]  = imm_b[4:1];
    temp_instr[6:0]   = 7'b1100011;

    make_b_instr = temp_instr;
  endfunction

  task automatic check_value(
    input string       name,
    input logic [31:0] got,
    input logic [31:0] expected
  );
    if (got !== expected) begin
      $error("%s mismatch: expected=%h got=%h", name, expected, got);
      num_fails++;
    end
  endtask

  task automatic clear_memories();
    begin
      for (int i = 0; i < 256; i++) begin
        dut.u_imem.mem[i] = 32'd0;
        dut.u_dmem.mem[i] = 32'd0;
      end
    end
  endtask

  task automatic reset_cpu();
    begin
      trace_enable = 1'b0;
      cycle_count  = 0;

      rst_n = 1'b0;
      repeat (2) @(posedge clk);
      rst_n = 1'b1;
    end
  endtask

  task automatic run_until_halt(input int unsigned max_cycles);
    int unsigned cycles;
    begin
      cycles = 0;
      trace_enable = 1'b1;

      while (!illegal_instr_dbg && (cycles < max_cycles)) begin
        @(posedge clk);
        cycles++;
      end

      trace_enable = 1'b0;

      $display("Final PC    = %h", pc_dbg);
      $display("Final instr = %h", instr_dbg);

      if (!illegal_instr_dbg) begin
        $error("CPU did not halt on invalid instruction within %0d cycles", max_cycles);
        num_fails++;
    end
  end
endtask

  task automatic load_program_1();
    begin
      // Program 1:
      // x1 = 5
      // x2 = 7
      // x3 = x1 + x2 = 12
      // mem[0] = x3
      // x4 = mem[0]
      // if x3 == x4, skip next instruction
      // x5 = 1       // should be skipped
      // x6 = x3 ^ x4 // should be 0
      // invalid instruction = halt

      dut.u_imem.mem[0] = make_i_instr(12'd5,  5'd0, 3'b000, 5'd1, 7'b0010011); // addi x1, x0, 5
      dut.u_imem.mem[1] = make_i_instr(12'd7,  5'd0, 3'b000, 5'd2, 7'b0010011); // addi x2, x0, 7
      dut.u_imem.mem[2] = make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);   // add x3, x1, x2
      dut.u_imem.mem[3] = make_s_instr(12'd0,  5'd3, 5'd0, 3'b010);             // sw x3, 0(x0)
      dut.u_imem.mem[4] = make_i_instr(12'd0,  5'd0, 3'b010, 5'd4, 7'b0000011); // lw x4, 0(x0)
      dut.u_imem.mem[5] = make_b_instr(12'h004, 5'd4, 5'd3, 3'b000);            // beq x3, x4, +8
      dut.u_imem.mem[6] = make_i_instr(12'd1,  5'd0, 3'b000, 5'd5, 7'b0010011); // addi x5, x0, 1
      dut.u_imem.mem[7] = make_r_instr(7'b0000000, 5'd4, 5'd3, 3'b100, 5'd6);   // xor x6, x3, x4
      dut.u_imem.mem[8] = 32'h0000_0000;                                        // invalid = halt
    end
  endtask

  task automatic check_program_1();
    begin
      check_value("program1 x1",      dut.u_core.u_regfile.regs[1], 32'd5);
      check_value("program1 x2",      dut.u_core.u_regfile.regs[2], 32'd7);
      check_value("program1 x3",      dut.u_core.u_regfile.regs[3], 32'd12);
      check_value("program1 dmem[0]", dut.u_dmem.mem[0],     32'd12);
      check_value("program1 x4",      dut.u_core.u_regfile.regs[4], 32'd12);
      check_value("program1 x5",      dut.u_core.u_regfile.regs[5], 32'd0);
      check_value("program1 x6",      dut.u_core.u_regfile.regs[6], 32'd0);
    end
  endtask

  task automatic load_program_2();
    begin
      // Program 2:
      // Tests sub, and, or, xori, andi, ori, beq not taken,
      // x0 protection, and memory access at nonzero address.

      dut.u_imem.mem[0]  = make_i_instr(12'd123, 5'd0, 3'b000, 5'd0,  7'b0010011); // addi x0, x0, 123 ignored
      dut.u_imem.mem[1]  = make_i_instr(12'd15,  5'd0, 3'b000, 5'd1,  7'b0010011); // addi x1, x0, 15
      dut.u_imem.mem[2]  = make_i_instr(12'd5,   5'd0, 3'b000, 5'd2,  7'b0010011); // addi x2, x0, 5
      dut.u_imem.mem[3]  = make_r_instr(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3);     // sub x3, x1, x2 = 10
      dut.u_imem.mem[4]  = make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd4);     // and x4, x1, x2 = 5
      dut.u_imem.mem[5]  = make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd5);     // or x5, x1, x2 = 15
      dut.u_imem.mem[6]  = make_i_instr(12'd10,  5'd1, 3'b100, 5'd6,  7'b0010011); // xori x6, x1, 10 = 5
      dut.u_imem.mem[7]  = make_i_instr(12'd6,   5'd1, 3'b111, 5'd7,  7'b0010011); // andi x7, x1, 6 = 6
      dut.u_imem.mem[8]  = make_i_instr(12'd8,   5'd2, 3'b110, 5'd8,  7'b0010011); // ori x8, x2, 8 = 13
      dut.u_imem.mem[9]  = make_b_instr(12'h004, 5'd2, 5'd1, 3'b000);              // beq x1, x2, +8 not taken
      dut.u_imem.mem[10] = make_i_instr(12'd99,  5'd0, 3'b000, 5'd9,  7'b0010011); // addi x9, x0, 99 executes
      dut.u_imem.mem[11] = make_s_instr(12'd16,  5'd9, 5'd0, 3'b010);              // sw x9, 16(x0)
      dut.u_imem.mem[12] = make_i_instr(12'd16,  5'd0, 3'b010, 5'd10, 7'b0000011); // lw x10, 16(x0)
      dut.u_imem.mem[13] = 32'h0000_0000;                                          // invalid = halt
    end
  endtask

  task automatic load_program_3();
    begin
      // Program 3:
      // Tests negative immediate sign extension and taken branch.
      //
      // x1 = -1
      // x2 = 1
      // x3 = x1 + x2 = 0
      // beq x3, x0, skip
      // x4 = 99      // should be skipped
      // x5 = 42
      // invalid instruction = halt

      dut.u_imem.mem[0] = make_i_instr(12'hFFF, 5'd0, 3'b000, 5'd1, 7'b0010011); // addi x1, x0, -1
      dut.u_imem.mem[1] = make_i_instr(12'd1,   5'd0, 3'b000, 5'd2, 7'b0010011); // addi x2, x0, 1
      dut.u_imem.mem[2] = make_r_instr(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3);    // add x3, x1, x2
      dut.u_imem.mem[3] = make_b_instr(12'h004, 5'd0, 5'd3, 3'b000);             // beq x3, x0, +8
      dut.u_imem.mem[4] = make_i_instr(12'd99,  5'd0, 3'b000, 5'd4, 7'b0010011); // addi x4, x0, 99 skipped
      dut.u_imem.mem[5] = make_i_instr(12'd42,  5'd0, 3'b000, 5'd5, 7'b0010011); // addi x5, x0, 42
      dut.u_imem.mem[6] = 32'h0000_0000;                                         // invalid = halt
    end
endtask

task automatic check_program_3();
  begin
    check_value("program3 x1", dut.u_core.u_regfile.regs[1], 32'hFFFF_FFFF);
    check_value("program3 x2", dut.u_core.u_regfile.regs[2], 32'd1);
    check_value("program3 x3", dut.u_core.u_regfile.regs[3], 32'd0);
    check_value("program3 x4", dut.u_core.u_regfile.regs[4], 32'd0);
    check_value("program3 x5", dut.u_core.u_regfile.regs[5], 32'd42);
  end
endtask

  task automatic check_program_2();
    begin
      check_value("program2 x0",      dut.u_core.u_regfile.regs[0],  32'd0);
      check_value("program2 x1",      dut.u_core.u_regfile.regs[1],  32'd15);
      check_value("program2 x2",      dut.u_core.u_regfile.regs[2],  32'd5);
      check_value("program2 x3",      dut.u_core.u_regfile.regs[3],  32'd10);
      check_value("program2 x4",      dut.u_core.u_regfile.regs[4],  32'd5);
      check_value("program2 x5",      dut.u_core.u_regfile.regs[5],  32'd15);
      check_value("program2 x6",      dut.u_core.u_regfile.regs[6],  32'd5);
      check_value("program2 x7",      dut.u_core.u_regfile.regs[7],  32'd6);
      check_value("program2 x8",      dut.u_core.u_regfile.regs[8],  32'd13);
      check_value("program2 x9",      dut.u_core.u_regfile.regs[9],  32'd99);
      check_value("program2 dmem[4]", dut.u_dmem.mem[4],      32'd99);
      check_value("program2 x10",     dut.u_core.u_regfile.regs[10], 32'd99);
    end
  endtask

  initial begin
    $dumpfile("cpu_core_tb.vcd");
    $dumpvars(0, cpu_core_tb);

    num_fails = 0;

    $display("Starting CPU program 1...");
    fails_before = num_fails;
    clear_memories();
    load_program_1();
    reset_cpu();
    run_until_halt(25);
    check_program_1();

    if (num_fails == fails_before) begin
      $display("CPU PROGRAM 1 PASSED");
    end else begin
      $display("CPU PROGRAM 1 FAILED");
    end

    $display("Starting CPU program 2...");
    fails_before = num_fails;
    clear_memories();
    load_program_2();
    reset_cpu();
    run_until_halt(35);
    check_program_2();

    if (num_fails == fails_before) begin
      $display("CPU PROGRAM 2 PASSED");
    end else begin
      $display("CPU PROGRAM 2 FAILED");
    end

    $display("Starting CPU program 3...");
    fails_before = num_fails;
    clear_memories();
    load_program_3();
    reset_cpu();
    run_until_halt(25);
    check_program_3();

    if (num_fails == fails_before) begin
      $display("CPU PROGRAM 3 PASSED");
    end else begin
      $display("CPU PROGRAM 3 FAILED");
    end

    if (num_fails == 0) begin
      $display("CPU CORE TEST PASSED");
    end else begin
      $fatal(1, "CPU CORE TEST FAILED: %0d failures", num_fails);
    end

    $finish;
  end

endmodule
