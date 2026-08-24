`timescale 1ns/1ps
`default_nettype none

module riscv_accel_soc #(
    parameter int unsigned IMEM_DEPTH = 256,
    parameter int unsigned DMEM_DEPTH = 256,
    parameter logic [31:0] ACCEL_BASE = 32'h0000_0400,
    parameter int unsigned ACCEL_WINDOW_BYTES = 32
) (
    input  logic        clk,
    input  logic        rst_n,

    output logic [31:0] pc_dbg,
    output logic [31:0] instr_dbg,
    output logic        illegal_instr_dbg
);

    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;

    logic        cpu_dmem_re;
    logic        cpu_dmem_we;
    logic [31:0] cpu_dmem_addr;
    logic [31:0] cpu_dmem_wdata;
    logic [31:0] cpu_dmem_rdata;

    logic        ram_re;
    logic        ram_we;
    logic [31:0] ram_addr;
    logic [31:0] ram_wdata;
    logic [31:0] ram_rdata;

    logic        accel_mmio_read;
    logic        accel_mmio_write;
    logic [31:0] accel_mmio_addr;
    logic [31:0] accel_mmio_wdata;
    logic [31:0] accel_mmio_rdata;

    rv32i_core u_core (
        .clk               (clk),
        .rst_n             (rst_n),
        .imem_addr         (imem_addr),
        .imem_rdata        (imem_rdata),
        .dmem_re           (cpu_dmem_re),
        .dmem_we           (cpu_dmem_we),
        .dmem_addr         (cpu_dmem_addr),
        .dmem_wdata        (cpu_dmem_wdata),
        .dmem_rdata        (cpu_dmem_rdata),
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

    soc_data_fabric #(
        .RAM_DEPTH         (DMEM_DEPTH),
        .ACCEL_BASE        (ACCEL_BASE),
        .ACCEL_WINDOW_BYTES(ACCEL_WINDOW_BYTES)
    ) u_data_fabric (
        .cpu_dmem_re      (cpu_dmem_re),
        .cpu_dmem_we      (cpu_dmem_we),
        .cpu_dmem_addr    (cpu_dmem_addr),
        .cpu_dmem_wdata   (cpu_dmem_wdata),
        .cpu_dmem_rdata   (cpu_dmem_rdata),
        .ram_re           (ram_re),
        .ram_we           (ram_we),
        .ram_addr         (ram_addr),
        .ram_wdata        (ram_wdata),
        .ram_rdata        (ram_rdata),
        .accel_mmio_read  (accel_mmio_read),
        .accel_mmio_write (accel_mmio_write),
        .accel_mmio_addr  (accel_mmio_addr),
        .accel_mmio_wdata (accel_mmio_wdata),
        .accel_mmio_rdata (accel_mmio_rdata)
    );

    data_mem #(
        .DEPTH(DMEM_DEPTH)
    ) u_dmem (
        .clk    (clk),
        .mem_re (ram_re),
        .mem_we (ram_we),
        .addr   (ram_addr),
        .wdata  (ram_wdata),
        .rdata  (ram_rdata)
    );

    dot_product_accel_mmio u_accel_mmio (
        .clk        (clk),
        .rst_n      (rst_n),
        .mmio_addr  (accel_mmio_addr),
        .mmio_read  (accel_mmio_read),
        .mmio_write (accel_mmio_write),
        .mmio_wdata (accel_mmio_wdata),
        .mmio_rdata (accel_mmio_rdata)
    );

endmodule

`default_nettype wire
