`timescale 1ns/1ps

// Compatibility wrapper for the original self-contained CPU interface.
// The integrated SoC instantiates rv32i_core directly and places address
// decoding between its data-memory interface and system peripherals.
module cpu_core #(
  parameter int IMEM_DEPTH = 256,
  parameter int DMEM_DEPTH = 256
) (
  input  logic        clk,
  input  logic        rst_n,

  output logic [31:0] pc_dbg,
  output logic [31:0] instr_dbg,
  output logic        illegal_instr_dbg
);

  logic [31:0] imem_addr;
  logic [31:0] imem_rdata;

  logic        dmem_re;
  logic        dmem_we;
  logic [31:0] dmem_addr;
  logic [31:0] dmem_wdata;
  logic [31:0] dmem_rdata;

  rv32i_core u_core (
    .clk               (clk),
    .rst_n             (rst_n),
    .imem_addr         (imem_addr),
    .imem_rdata        (imem_rdata),
    .dmem_re           (dmem_re),
    .dmem_we           (dmem_we),
    .dmem_addr         (dmem_addr),
    .dmem_wdata        (dmem_wdata),
    .dmem_rdata        (dmem_rdata),
    .pc_dbg            (pc_dbg),
    .instr_dbg         (instr_dbg),
    .illegal_instr_dbg (illegal_instr_dbg)
  );

  instr_mem #(
    .DEPTH(IMEM_DEPTH)
  ) u_imem (
    .addr  (imem_addr),
    .instr (imem_rdata)
  );

  data_mem #(
    .DEPTH(DMEM_DEPTH)
  ) u_dmem (
    .clk    (clk),
    .mem_re (dmem_re),
    .mem_we (dmem_we),
    .addr   (dmem_addr),
    .wdata  (dmem_wdata),
    .rdata  (dmem_rdata)
  );

endmodule
