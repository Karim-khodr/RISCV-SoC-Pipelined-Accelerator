`timescale 1ns/1ps

module rv32i_core (
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] imem_addr,
  input  logic [31:0] imem_rdata,

  output logic        dmem_re,
  output logic        dmem_we,
  output logic [31:0] dmem_addr,
  output logic [31:0] dmem_wdata,
  input  logic [31:0] dmem_rdata,

  output logic [31:0] pc_dbg,
  output logic [31:0] instr_dbg,
  output logic        illegal_instr_dbg
);

  logic [31:0] pc;
  logic [31:0] pc_next;
  logic [31:0] instr;

  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [4:0] rd;

  cpu_pkg::alu_op_e   alu_op;
  cpu_pkg::imm_type_e imm_type;
  cpu_pkg::wb_sel_e   wb_sel;

  logic reg_we;
  logic mem_re;
  logic mem_we;
  logic alu_src_imm;
  logic branch_eq;
  logic illegal_instr;

  logic [31:0] imm;
  logic [31:0] rdata1;
  logic [31:0] rdata2;
  logic [31:0] alu_b;
  logic [31:0] alu_y;
  logic        alu_zero;
  logic [31:0] wb_data;
  logic        branch_taken;

  assign imem_addr = pc;
  assign instr     = imem_rdata;

  decoder u_decoder (
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

  imm_gen u_imm_gen (
    .instr    (instr),
    .imm_type (imm_type),
    .imm      (imm)
  );

  regfile u_regfile (
    .clk    (clk),
    .rst_n  (rst_n),
    .we     (reg_we && !illegal_instr),
    .waddr  (rd),
    .wdata  (wb_data),
    .raddr1 (rs1),
    .raddr2 (rs2),
    .rdata1 (rdata1),
    .rdata2 (rdata2)
  );

  assign alu_b = alu_src_imm ? imm : rdata2;

  alu u_alu (
    .a    (rdata1),
    .b    (alu_b),
    .op   (alu_op),
    .y    (alu_y),
    .zero (alu_zero)
  );

  assign dmem_re    = mem_re && !illegal_instr;
  assign dmem_we    = mem_we && !illegal_instr;
  assign dmem_addr  = alu_y;
  assign dmem_wdata = rdata2;

  assign wb_data = (wb_sel == cpu_pkg::WB_MEM) ? dmem_rdata : alu_y;

  assign branch_taken = branch_eq && alu_zero;
  assign pc_next      = branch_taken ? (pc + imm) : (pc + 32'd4);

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      pc <= 32'd0;
    end else if (!illegal_instr) begin
      pc <= pc_next;
    end
  end

  assign pc_dbg            = pc;
  assign instr_dbg         = instr;
  assign illegal_instr_dbg = illegal_instr;

`ifndef SYNTHESIS
  always_comb begin
    assert (!$isunknown(pc))
      else $error("rv32i_core pc contains X/Z");

    assert (!$isunknown(instr))
      else $error("rv32i_core instruction contains X/Z");
  end
`endif

endmodule
