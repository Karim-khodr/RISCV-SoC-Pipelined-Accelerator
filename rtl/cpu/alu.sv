`timescale 1ns/1ps

module alu
  import cpu_pkg::*;
(
  input  logic [31:0] a,
  input  logic [31:0] b,
  input  alu_op_e     op,
  output logic [31:0] y,
  output logic        zero
);

  always_comb begin
    unique case (op)
      ALU_ADD: y = a + b;
      ALU_SUB: y = a - b;
      ALU_AND: y = a & b;
      ALU_OR : y = a | b;
      ALU_XOR: y = a ^ b;
      default: y = 32'h0000_0000;
    endcase
  end

  assign zero = (y == 32'd0);

`ifndef SYNTHESIS
  always_comb begin
    assert (!$isunknown(a))
      else $error("ALU input a contains X/Z");

    assert (!$isunknown(b))
      else $error("ALU input b contains X/Z");

    assert (!$isunknown(op))
      else $error("ALU op contains X/Z");
  end
`endif

endmodule
