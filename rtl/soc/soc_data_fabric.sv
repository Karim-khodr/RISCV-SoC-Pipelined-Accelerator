`timescale 1ns/1ps
`default_nettype none

module soc_data_fabric #(
    parameter int unsigned RAM_DEPTH = 256,
    parameter logic [31:0] ACCEL_BASE = 32'h0000_0400,
    parameter int unsigned ACCEL_WINDOW_BYTES = 32
) (
    input  logic        cpu_dmem_re,
    input  logic        cpu_dmem_we,
    input  logic [31:0] cpu_dmem_addr,
    input  logic [31:0] cpu_dmem_wdata,
    output logic [31:0] cpu_dmem_rdata,

    output logic        ram_re,
    output logic        ram_we,
    output logic [31:0] ram_addr,
    output logic [31:0] ram_wdata,
    input  logic [31:0] ram_rdata,

    output logic        accel_mmio_read,
    output logic        accel_mmio_write,
    output logic [31:0] accel_mmio_addr,
    output logic [31:0] accel_mmio_wdata,
    input  logic [31:0] accel_mmio_rdata
);

    localparam logic [31:0] RAM_END_EXCLUSIVE = 32'(RAM_DEPTH * 4);
    localparam logic [31:0] ACCEL_END_EXCLUSIVE =
        ACCEL_BASE + 32'(ACCEL_WINDOW_BYTES);

    logic ram_select;
    logic accel_select;

    assign ram_select = cpu_dmem_addr < RAM_END_EXCLUSIVE;
    assign accel_select = (cpu_dmem_addr >= ACCEL_BASE)
                          && (cpu_dmem_addr < ACCEL_END_EXCLUSIVE);

    assign ram_re    = cpu_dmem_re && ram_select;
    assign ram_we    = cpu_dmem_we && ram_select;
    assign ram_addr  = cpu_dmem_addr;
    assign ram_wdata = cpu_dmem_wdata;

    assign accel_mmio_read  = cpu_dmem_re && accel_select;
    assign accel_mmio_write = cpu_dmem_we && accel_select;
    assign accel_mmio_addr  = cpu_dmem_addr - ACCEL_BASE;
    assign accel_mmio_wdata = cpu_dmem_wdata;

    always_comb begin
        cpu_dmem_rdata = 32'h0000_0000;

        if (cpu_dmem_re) begin
            if (accel_select) begin
                cpu_dmem_rdata = accel_mmio_rdata;
            end else if (ram_select) begin
                cpu_dmem_rdata = ram_rdata;
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (RAM_DEPTH == 0) begin
            $fatal(1, "soc_data_fabric requires RAM_DEPTH > 0");
        end

        if (ACCEL_WINDOW_BYTES == 0) begin
            $fatal(1, "soc_data_fabric requires a non-empty accelerator window");
        end

        if (RAM_END_EXCLUSIVE > ACCEL_BASE) begin
            $fatal(1, "RAM and accelerator address regions overlap");
        end

        if (ACCEL_END_EXCLUSIVE <= ACCEL_BASE) begin
            $fatal(1, "accelerator address window wraps around");
        end
    end

    always_comb begin
        if (!$isunknown(cpu_dmem_addr)) begin
            assert (!(ram_select && accel_select))
                else $error("RAM and accelerator selected simultaneously");
        end

        assert (!(ram_we && accel_mmio_write))
            else $error("RAM and accelerator writes active simultaneously");
    end
`endif

endmodule

`default_nettype wire
