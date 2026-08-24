`timescale 1ns/1ps

module riscv_accel_soc_tb;

    logic clk = 1'b0;
    // The verified CPU uses synchronous active-low reset while the verified
    // accelerator uses asynchronous active-low reset on this shared net.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 1'b0;
    /* verilator lint_on SYNCASYNCNET */

    logic [31:0] pc_dbg;
    logic [31:0] instr_dbg;
    logic        illegal_instr_dbg;

    int unsigned failures;
    int unsigned accelerator_accesses;

    riscv_accel_soc dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .pc_dbg            (pc_dbg),
        .instr_dbg         (instr_dbg),
        .illegal_instr_dbg (illegal_instr_dbg)
    );

    always #5 clk <= ~clk;

    always_ff @(posedge clk) begin
        if ((dut.accel_mmio_read === 1'b1)
            || (dut.accel_mmio_write === 1'b1)) begin
            accelerator_accesses <= accelerator_accesses + 1;
        end
    end

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
            imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011
        };
    endfunction

    function automatic logic [31:0] make_b_instr(
        input logic [12:1] imm_b,
        input logic [4:0]  rs2,
        input logic [4:0]  rs1,
        input logic [2:0]  funct3
    );
        logic [31:0] temp_instr;
        begin
            temp_instr = 32'h0000_0063;
            temp_instr[31]    = imm_b[12];
            temp_instr[7]     = imm_b[11];
            temp_instr[30:25] = imm_b[10:5];
            temp_instr[24:20] = rs2;
            temp_instr[19:15] = rs1;
            temp_instr[14:12] = funct3;
            temp_instr[11:8]  = imm_b[4:1];
            make_b_instr = temp_instr;
        end
    endfunction

    task automatic check_equal(
        input string name,
        input logic [31:0] got,
        input logic [31:0] expected
    );
        begin
            if (got !== expected) begin
                $error("%s: expected=%h got=%h", name, expected, got);
                failures++;
            end
        end
    endtask

    initial begin
        int unsigned cycles;

        $dumpfile("sim/waveforms/riscv_accel_soc_tb.vcd");
        $dumpvars(0, riscv_accel_soc_tb);

        failures = 0;
        accelerator_accesses = 0;

        for (int i = 0; i < 256; i++) begin
            dut.u_imem.mem[i] = 32'd0;
            dut.u_dmem.mem[i] = 32'd0;
        end

        // Reuse the existing CPU regression's first RAM-only program.
        dut.u_imem.mem[0] = make_i_instr(12'd5, 5'd0, 3'b000, 5'd1,
                                         7'b0010011);
        dut.u_imem.mem[1] = make_i_instr(12'd7, 5'd0, 3'b000, 5'd2,
                                         7'b0010011);
        dut.u_imem.mem[2] = make_r_instr(7'b0000000, 5'd2, 5'd1,
                                         3'b000, 5'd3);
        dut.u_imem.mem[3] = make_s_instr(12'd0, 5'd3, 5'd0, 3'b010);
        dut.u_imem.mem[4] = make_i_instr(12'd0, 5'd0, 3'b010, 5'd4,
                                         7'b0000011);
        dut.u_imem.mem[5] = make_b_instr(12'h004, 5'd4, 5'd3, 3'b000);
        dut.u_imem.mem[6] = make_i_instr(12'd1, 5'd0, 3'b000, 5'd5,
                                         7'b0010011);
        dut.u_imem.mem[7] = make_r_instr(7'b0000000, 5'd4, 5'd3,
                                         3'b100, 5'd6);
        dut.u_imem.mem[8] = 32'h0000_0000;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        cycles = 0;
        while (!illegal_instr_dbg && (cycles < 25)) begin
            @(posedge clk);
            cycles++;
        end

        if (!illegal_instr_dbg) begin
            $error("RAM-only SoC program did not halt within 25 cycles");
            failures++;
        end

        check_equal("x1", dut.u_core.u_regfile.regs[1], 32'd5);
        check_equal("x2", dut.u_core.u_regfile.regs[2], 32'd7);
        check_equal("x3", dut.u_core.u_regfile.regs[3], 32'd12);
        check_equal("RAM word zero", dut.u_dmem.mem[0], 32'd12);
        check_equal("x4 load result", dut.u_core.u_regfile.regs[4], 32'd12);
        check_equal("x5 branch skip", dut.u_core.u_regfile.regs[5], 32'd0);
        check_equal("x6 xor", dut.u_core.u_regfile.regs[6], 32'd0);
        check_equal("accelerator access count", accelerator_accesses, 32'd0);
        check_equal("halt PC", pc_dbg, 32'h0000_0020);
        check_equal("halt instruction", instr_dbg, 32'h0000_0000);

        if (failures == 0) begin
            $display("[PASS] RAM-only CPU program through integrated SoC");
            $display("SOC TOP TEST PASSED");
        end else begin
            $fatal(1, "SOC TOP TEST FAILED: %0d failures", failures);
        end

        $finish;
    end

endmodule
