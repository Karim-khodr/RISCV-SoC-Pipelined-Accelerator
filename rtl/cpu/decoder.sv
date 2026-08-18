`timescale 1ns/1ps

module decoder (
  input  logic [31:0]        instr,

  output logic [4:0]         rs1,
  output logic [4:0]         rs2,
  output logic [4:0]         rd,

  output cpu_pkg::alu_op_e   alu_op,
  output cpu_pkg::imm_type_e imm_type,
  output cpu_pkg::wb_sel_e   wb_sel,

  output logic               reg_we,
  output logic               mem_re,
  output logic               mem_we,
  output logic               alu_src_imm,
  output logic               branch_eq,
  output logic               illegal_instr
);

  logic [6:0] opcode;
  logic [2:0] funct3;
  logic [6:0] funct7;

  assign opcode = instr[6:0];
  assign rd     = instr[11:7];
  assign funct3 = instr[14:12];
  assign rs1    = instr[19:15];
  assign rs2    = instr[24:20];
  assign funct7 = instr[31:25];

  always_comb begin
    alu_op        = cpu_pkg::ALU_ADD;
    imm_type      = cpu_pkg::IMM_I;
    wb_sel        = cpu_pkg::WB_ALU;
    reg_we        = 1'b0;
    mem_re        = 1'b0;
    mem_we        = 1'b0;
    alu_src_imm   = 1'b0;
    branch_eq     = 1'b0;
    illegal_instr = 1'b0;

    unique case (opcode)

      // R-type: add, sub, and, or, xor
      7'b0110011: begin
        reg_we      = 1'b1;
        alu_src_imm = 1'b0;
        wb_sel      = cpu_pkg::WB_ALU;

        unique case ({funct7, funct3})
          {7'b0000000, 3'b000}: alu_op = cpu_pkg::ALU_ADD;
          {7'b0100000, 3'b000}: alu_op = cpu_pkg::ALU_SUB;
          {7'b0000000, 3'b111}: alu_op = cpu_pkg::ALU_AND;
          {7'b0000000, 3'b110}: alu_op = cpu_pkg::ALU_OR;
          {7'b0000000, 3'b100}: alu_op = cpu_pkg::ALU_XOR;
          default: begin
            reg_we        = 1'b0;
            illegal_instr = 1'b1;
          end
        endcase
      end

      // I-type ALU: addi, andi, ori, xori
      7'b0010011: begin
        reg_we      = 1'b1;
        alu_src_imm = 1'b1;
        imm_type    = cpu_pkg::IMM_I;
        wb_sel      = cpu_pkg::WB_ALU;

        unique case (funct3)
          3'b000: alu_op = cpu_pkg::ALU_ADD; // addi
          3'b111: alu_op = cpu_pkg::ALU_AND; // andi
          3'b110: alu_op = cpu_pkg::ALU_OR;  // ori
          3'b100: alu_op = cpu_pkg::ALU_XOR; // xori
          default: begin
            reg_we        = 1'b0;
            illegal_instr = 1'b1;
          end
        endcase
      end

      // lw
      7'b0000011: begin
        if (funct3 == 3'b010) begin
          reg_we      = 1'b1;
          mem_re      = 1'b1;
          alu_src_imm = 1'b1;
          imm_type    = cpu_pkg::IMM_I;
          alu_op      = cpu_pkg::ALU_ADD;
          wb_sel      = cpu_pkg::WB_MEM;
        end else begin
          illegal_instr = 1'b1;
        end
      end

      // sw
      7'b0100011: begin
        if (funct3 == 3'b010) begin
          mem_we      = 1'b1;
          alu_src_imm = 1'b1;
          imm_type    = cpu_pkg::IMM_S;
          alu_op      = cpu_pkg::ALU_ADD;
        end else begin
          illegal_instr = 1'b1;
        end
      end

      // beq
      7'b1100011: begin
        if (funct3 == 3'b000) begin
          branch_eq   = 1'b1;
          alu_src_imm = 1'b0;
          imm_type    = cpu_pkg::IMM_B;
          alu_op      = cpu_pkg::ALU_SUB;
        end else begin
          illegal_instr = 1'b1;
        end
      end

      default: begin
        illegal_instr = 1'b1;
      end

    endcase
  end

`ifndef SYNTHESIS
  always_comb begin
    assert (!$isunknown(instr))
      else $error("decoder instr contains X/Z");
  end
`endif

endmodule
