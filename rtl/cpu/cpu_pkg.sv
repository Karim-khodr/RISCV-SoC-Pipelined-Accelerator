`timescale 1ns/1ps

package cpu_pkg;

  typedef enum logic [3:0] {
    ALU_ADD = 4'd0,
    ALU_SUB = 4'd1,
    ALU_AND = 4'd2,
    ALU_OR  = 4'd3,
    ALU_XOR = 4'd4
  } alu_op_e;

  typedef enum logic [1:0] {
    IMM_I = 2'd0,
    IMM_S = 2'd1,
    IMM_B = 2'd2
  } imm_type_e;

  typedef enum logic {
    WB_ALU = 1'b0,
    WB_MEM = 1'b1
  } wb_sel_e;

endpackage
