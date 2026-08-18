`timescale 1ns/1ps

module imm_gen (
  input  logic [31:0]        instr,
  input  cpu_pkg::imm_type_e imm_type,
  output logic [31:0]        imm
);

  always_comb begin
    unique case (imm_type)
      cpu_pkg::IMM_I: begin
        imm = {{20{instr[31]}}, instr[31:20]};
      end

      cpu_pkg::IMM_S: begin
        imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
      end

      cpu_pkg::IMM_B: begin
        imm = {{19{instr[31]}}, instr[31], instr[7],
               instr[30:25], instr[11:8], 1'b0};
      end

      default: begin
        imm = 32'd0;
      end
    endcase
  end

`ifndef SYNTHESIS
  always_comb begin
    assert (!$isunknown(instr))
      else $error("imm_gen instr contains X/Z");

    assert (!$isunknown(imm_type))
      else $error("imm_gen imm_type contains X/Z");
  end
`endif

endmodule
