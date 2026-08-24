`timescale 1ns/1ps
`default_nettype none

module riscv_accel_software_tb;

    localparam int unsigned IMEM_DEPTH = 256;
    localparam int unsigned DMEM_DEPTH = 256;
    localparam int unsigned ACCEL_TIMEOUT_CYCLES = 64;
    localparam int unsigned SOFTWARE_TIMEOUT_CYCLES = 160;

    localparam logic [31:0] PACKED_A_ADDR = 32'h0000_0000;
    localparam logic [31:0] PACKED_B_ADDR = 32'h0000_0004;
    localparam logic [31:0] SCALAR_A0_ADDR = 32'h0000_0010;
    localparam logic [31:0] SCALAR_A1_ADDR = 32'h0000_0014;
    localparam logic [31:0] SCALAR_A2_ADDR = 32'h0000_0018;
    localparam logic [31:0] SCALAR_A3_ADDR = 32'h0000_001c;
    localparam logic [31:0] SCALAR_B0_ADDR = 32'h0000_0020;
    localparam logic [31:0] SCALAR_B1_ADDR = 32'h0000_0024;
    localparam logic [31:0] SCALAR_B2_ADDR = 32'h0000_0028;
    localparam logic [31:0] SCALAR_B3_ADDR = 32'h0000_002c;
    localparam logic [31:0] ACCEL_RESULT_ADDR = 32'h0000_0030;
    localparam logic [31:0] SOFTWARE_RESULT_ADDR = 32'h0000_0034;

    localparam logic [31:0] CONTROL_ADDR = 32'h0000_0400;
    localparam logic [31:0] STATUS_ADDR = 32'h0000_0404;
    localparam logic [31:0] VEC_A_ADDR = 32'h0000_0408;
    localparam logic [31:0] VEC_B_ADDR = 32'h0000_040c;
    localparam logic [31:0] RESULT_ADDR = 32'h0000_0410;

    localparam logic [31:0] PACKED_A = 32'h0806_0402;
    localparam logic [31:0] PACKED_B = 32'h0705_0301;
    localparam logic [31:0] EXPECTED_RESULT = 32'd100;
    localparam logic [31:0] STATUS_RESULT_VALID_MASK = 32'h0000_0004;

    localparam logic [31:0] ACCEL_HALT_PC = 32'h0000_002c;
    localparam logic [31:0] SOFTWARE_HALT_PC = 32'h0000_008c;
    localparam logic [31:0] HALT_WORD = 32'h0000_0000;

    typedef enum logic [1:0] {
        BENCH_IDLE = 2'd0,
        BENCH_ACCEL = 2'd1,
        BENCH_SOFTWARE = 2'd2
    } benchmark_e;

    logic clk = 1'b0;
    // CPU reset is synchronous; accelerator reset is asynchronous.
    /* verilator lint_off SYNCASYNCNET */
    logic rst_n = 1'b0;
    /* verilator lint_on SYNCASYNCNET */

    logic [31:0] pc_dbg;
    logic [31:0] instr_dbg;
    logic illegal_instr_dbg;
    benchmark_e benchmark_mode = BENCH_IDLE;

    int unsigned program_cycles;
    int unsigned cycles_to_result_store;
    int unsigned final_result_stores;
    int unsigned vec_a_writes;
    int unsigned vec_b_writes;
    int unsigned control_writes;
    int unsigned status_reads;
    int unsigned status_reads_with_result_valid;
    int unsigned result_reads;
    int unsigned other_mmio_reads;
    int unsigned other_mmio_writes;
    int unsigned accepted_starts;
    int unsigned pipeline_accepts;
    int unsigned completions;
    int unsigned reset_discards = 0;

    int unsigned measured_accel_cycles;
    int unsigned measured_software_cycles;
    int unsigned measured_status_reads;

    riscv_accel_soc #(
        .IMEM_DEPTH(IMEM_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH)
    ) dut (
        .clk               (clk),
        .rst_n             (rst_n),
        .pc_dbg            (pc_dbg),
        .instr_dbg         (instr_dbg),
        .illegal_instr_dbg (illegal_instr_dbg)
    );

    always #5 clk <= ~clk;

    function automatic logic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        encode_r = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
    endfunction

    function automatic logic [31:0] encode_i(
        input integer signed immediate,
        input logic [4:0] rs1,
        input logic [2:0] funct3,
        input logic [4:0] rd,
        input logic [6:0] opcode
    );
        logic [11:0] imm12;
        begin
            if ((immediate < -2048) || (immediate > 2047)) begin
                $fatal(1, "I-type immediate out of range: %0d", immediate);
            end
            imm12 = immediate[11:0];
            encode_i = {imm12, rs1, funct3, rd, opcode};
        end
    endfunction

    function automatic logic [31:0] encode_s(
        input integer signed immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [2:0] funct3
    );
        logic [11:0] imm12;
        begin
            if ((immediate < -2048) || (immediate > 2047)) begin
                $fatal(1, "S-type immediate out of range: %0d", immediate);
            end
            imm12 = immediate[11:0];
            encode_s = {
                imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011
            };
        end
    endfunction

    function automatic logic [31:0] encode_b(
        input integer signed offset_bytes,
        input logic [4:0] rs2,
        input logic [4:0] rs1
    );
        logic [12:1] imm13;
        begin
            if (offset_bytes[0] != 1'b0) begin
                $fatal(1, "B-type offset is not even: %0d", offset_bytes);
            end
            if ((offset_bytes < -4096) || (offset_bytes > 4094)) begin
                $fatal(1, "B-type offset out of range: %0d", offset_bytes);
            end
            imm13 = offset_bytes[12:1];
            encode_b = {
                imm13[12], imm13[10:5], rs2, rs1, 3'b000,
                imm13[4:1], imm13[11], 7'b1100011
            };
        end
    endfunction

    /* verilator lint_off UNUSEDSIGNAL */
    function automatic logic signed [31:0] decode_i_immediate(
        input logic [31:0] instruction
    );
        decode_i_immediate = $signed({{20{instruction[31]}}, instruction[31:20]});
    endfunction

    function automatic logic signed [31:0] decode_s_immediate(
        input logic [31:0] instruction
    );
        decode_s_immediate = $signed({
            {20{instruction[31]}}, instruction[31:25], instruction[11:7]
        });
    endfunction

    function automatic logic signed [31:0] decode_b_immediate(
        input logic [31:0] instruction
    );
        decode_b_immediate = $signed({
            {19{instruction[31]}}, instruction[31], instruction[7],
            instruction[30:25], instruction[11:8], 1'b0
        });
    endfunction
    /* verilator lint_on UNUSEDSIGNAL */

    function automatic logic [31:0] golden_dot(
        input logic [31:0] packed_a,
        input logic [31:0] packed_b
    );
        logic [31:0] sum;
        begin
            sum = 32'd0;
            for (int lane = 0; lane < 4; lane++) begin
                sum = sum + (packed_a[lane*8 +: 8] * packed_b[lane*8 +: 8]);
            end
            golden_dot = sum;
        end
    endfunction

    task automatic audit_word(
        input int unsigned word_index,
        input logic [31:0] expected,
        input string assembly
    );
        begin
            if (dut.u_imem.mem[word_index] !== expected) begin
                $fatal(1,
                    "Machine-code audit failed at PC=0x%08h for %s: expected=%08h got=%08h",
                    word_index * 4, assembly, expected,
                    dut.u_imem.mem[word_index]);
            end
        end
    endtask

    task automatic clear_memories;
        begin
            for (int index = 0; index < IMEM_DEPTH; index++) begin
                dut.u_imem.mem[index] = 32'd0;
            end
            for (int index = 0; index < DMEM_DEPTH; index++) begin
                dut.u_dmem.mem[index] = 32'd0;
            end
        end
    endtask

    task automatic load_common_data;
        begin
            dut.u_dmem.mem[PACKED_A_ADDR >> 2] = PACKED_A;
            dut.u_dmem.mem[PACKED_B_ADDR >> 2] = PACKED_B;
            dut.u_dmem.mem[SCALAR_A0_ADDR >> 2] = 32'd2;
            dut.u_dmem.mem[SCALAR_A1_ADDR >> 2] = 32'd4;
            dut.u_dmem.mem[SCALAR_A2_ADDR >> 2] = 32'd6;
            dut.u_dmem.mem[SCALAR_A3_ADDR >> 2] = 32'd8;
            dut.u_dmem.mem[SCALAR_B0_ADDR >> 2] = 32'd1;
            dut.u_dmem.mem[SCALAR_B1_ADDR >> 2] = 32'd3;
            dut.u_dmem.mem[SCALAR_B2_ADDR >> 2] = 32'd5;
            dut.u_dmem.mem[SCALAR_B3_ADDR >> 2] = 32'd7;
            dut.u_dmem.mem[ACCEL_RESULT_ADDR >> 2] = 32'd0;
            dut.u_dmem.mem[SOFTWARE_RESULT_ADDR >> 2] = 32'd0;
        end
    endtask

    task automatic load_accelerator_program;
        logic [31:0] encoded_words [0:11];
        begin
            dut.u_imem.mem[0] = encode_i(0, 5'd0, 3'b010, 5'd1, 7'b0000011);
            dut.u_imem.mem[1] = encode_i(4, 5'd0, 3'b010, 5'd2, 7'b0000011);
            dut.u_imem.mem[2] = encode_s(1032, 5'd1, 5'd0, 3'b010);
            dut.u_imem.mem[3] = encode_s(1036, 5'd2, 5'd0, 3'b010);
            dut.u_imem.mem[4] = encode_i(1, 5'd0, 3'b000, 5'd3, 7'b0010011);
            dut.u_imem.mem[5] = encode_s(1024, 5'd3, 5'd0, 3'b010);
            dut.u_imem.mem[6] = encode_i(1028, 5'd0, 3'b010, 5'd4, 7'b0000011);
            dut.u_imem.mem[7] = encode_i(4, 5'd4, 3'b111, 5'd4, 7'b0010011);
            dut.u_imem.mem[8] = encode_b(-8, 5'd0, 5'd4);
            dut.u_imem.mem[9] = encode_i(1040, 5'd0, 3'b010, 5'd5, 7'b0000011);
            dut.u_imem.mem[10] = encode_s(48, 5'd5, 5'd0, 3'b010);
            dut.u_imem.mem[11] = HALT_WORD;

            for (int index = 0; index < 12; index++) begin
                encoded_words[index] = dut.u_imem.mem[index];
            end

            // A timed readmem update gives all supported simulators a defined
            // instruction-memory change event after the module's time-zero
            // clearing block. The following checks prove that this executable
            // image exactly matches the encoder-generated words above.
            $readmemh("../../software/programs/accelerator_dot_product.hex",
                      dut.u_imem.mem, 0, 11);
            for (int index = 0; index < 12; index++) begin
                if (dut.u_imem.mem[index] !== encoded_words[index]) begin
                    $fatal(1,
                        "Accelerator hex/encoder mismatch at PC=0x%08h: hex=%08h encoder=%08h",
                        index * 4, dut.u_imem.mem[index], encoded_words[index]);
                end
            end

            audit_word(0, 32'h0000_2083, "lw x1, 0(x0)");
            audit_word(1, 32'h0040_2103, "lw x2, 4(x0)");
            audit_word(2, 32'h4010_2423, "sw x1, 0x408(x0)");
            audit_word(3, 32'h4020_2623, "sw x2, 0x40c(x0)");
            audit_word(4, 32'h0010_0193, "addi x3, x0, 1");
            audit_word(5, 32'h4030_2023, "sw x3, 0x400(x0)");
            audit_word(6, 32'h4040_2203, "lw x4, 0x404(x0)");
            audit_word(7, 32'h0042_7213, "andi x4, x4, 4");
            audit_word(8, 32'hfe02_0ce3, "beq x4, x0, -8");
            audit_word(9, 32'h4100_2283, "lw x5, 0x410(x0)");
            audit_word(10, 32'h0250_2823, "sw x5, 0x30(x0)");
            audit_word(11, HALT_WORD, "intentional illegal halt");

            if (decode_s_immediate(dut.u_imem.mem[2]) != 32'sh0000_0408
                || decode_s_immediate(dut.u_imem.mem[3]) != 32'sh0000_040c
                || decode_s_immediate(dut.u_imem.mem[5]) != 32'sh0000_0400
                || decode_i_immediate(dut.u_imem.mem[6]) != 32'sh0000_0404
                || decode_i_immediate(dut.u_imem.mem[9]) != 32'sh0000_0410) begin
                $fatal(1, "Accelerator program MMIO immediate audit failed");
            end
            if (decode_b_immediate(dut.u_imem.mem[8]) != -32'sd8) begin
                $fatal(1, "Accelerator polling branch decode audit failed");
            end
        end
    endtask

    task automatic load_software_program;
        logic [31:0] encoded_words [0:35];
        begin
            dut.u_imem.mem[0] = encode_i(1, 5'd0, 3'b000, 5'd1, 7'b0010011);
            dut.u_imem.mem[1] = encode_i(0, 5'd0, 3'b000, 5'd2, 7'b0010011);

            dut.u_imem.mem[2] = encode_i(16, 5'd0, 3'b010, 5'd3, 7'b0000011);
            dut.u_imem.mem[3] = encode_i(32, 5'd0, 3'b010, 5'd4, 7'b0000011);
            dut.u_imem.mem[4] = encode_i(0, 5'd0, 3'b000, 5'd5, 7'b0010011);
            dut.u_imem.mem[5] = encode_b(16, 5'd0, 5'd4);
            dut.u_imem.mem[6] = encode_r(7'b0000000, 5'd3, 5'd5, 3'b000, 5'd5);
            dut.u_imem.mem[7] = encode_r(7'b0100000, 5'd1, 5'd4, 3'b000, 5'd4);
            dut.u_imem.mem[8] = encode_b(-12, 5'd0, 5'd0);
            dut.u_imem.mem[9] = encode_r(7'b0000000, 5'd5, 5'd2, 3'b000, 5'd2);

            dut.u_imem.mem[10] = encode_i(20, 5'd0, 3'b010, 5'd3, 7'b0000011);
            dut.u_imem.mem[11] = encode_i(36, 5'd0, 3'b010, 5'd4, 7'b0000011);
            dut.u_imem.mem[12] = encode_i(0, 5'd0, 3'b000, 5'd6, 7'b0010011);
            dut.u_imem.mem[13] = encode_b(16, 5'd0, 5'd4);
            dut.u_imem.mem[14] = encode_r(7'b0000000, 5'd3, 5'd6, 3'b000, 5'd6);
            dut.u_imem.mem[15] = encode_r(7'b0100000, 5'd1, 5'd4, 3'b000, 5'd4);
            dut.u_imem.mem[16] = encode_b(-12, 5'd0, 5'd0);
            dut.u_imem.mem[17] = encode_r(7'b0000000, 5'd6, 5'd2, 3'b000, 5'd2);

            dut.u_imem.mem[18] = encode_i(24, 5'd0, 3'b010, 5'd3, 7'b0000011);
            dut.u_imem.mem[19] = encode_i(40, 5'd0, 3'b010, 5'd4, 7'b0000011);
            dut.u_imem.mem[20] = encode_i(0, 5'd0, 3'b000, 5'd7, 7'b0010011);
            dut.u_imem.mem[21] = encode_b(16, 5'd0, 5'd4);
            dut.u_imem.mem[22] = encode_r(7'b0000000, 5'd3, 5'd7, 3'b000, 5'd7);
            dut.u_imem.mem[23] = encode_r(7'b0100000, 5'd1, 5'd4, 3'b000, 5'd4);
            dut.u_imem.mem[24] = encode_b(-12, 5'd0, 5'd0);
            dut.u_imem.mem[25] = encode_r(7'b0000000, 5'd7, 5'd2, 3'b000, 5'd2);

            dut.u_imem.mem[26] = encode_i(28, 5'd0, 3'b010, 5'd3, 7'b0000011);
            dut.u_imem.mem[27] = encode_i(44, 5'd0, 3'b010, 5'd4, 7'b0000011);
            dut.u_imem.mem[28] = encode_i(0, 5'd0, 3'b000, 5'd8, 7'b0010011);
            dut.u_imem.mem[29] = encode_b(16, 5'd0, 5'd4);
            dut.u_imem.mem[30] = encode_r(7'b0000000, 5'd3, 5'd8, 3'b000, 5'd8);
            dut.u_imem.mem[31] = encode_r(7'b0100000, 5'd1, 5'd4, 3'b000, 5'd4);
            dut.u_imem.mem[32] = encode_b(-12, 5'd0, 5'd0);
            dut.u_imem.mem[33] = encode_r(7'b0000000, 5'd8, 5'd2, 3'b000, 5'd2);

            dut.u_imem.mem[34] = encode_s(52, 5'd2, 5'd0, 3'b010);
            dut.u_imem.mem[35] = HALT_WORD;

            for (int index = 0; index < 36; index++) begin
                encoded_words[index] = dut.u_imem.mem[index];
            end

            $readmemh("../../software/programs/software_dot_product.hex",
                      dut.u_imem.mem, 0, 35);
            for (int index = 0; index < 36; index++) begin
                if (dut.u_imem.mem[index] !== encoded_words[index]) begin
                    $fatal(1,
                        "Software hex/encoder mismatch at PC=0x%08h: hex=%08h encoder=%08h",
                        index * 4, dut.u_imem.mem[index], encoded_words[index]);
                end
            end

            audit_word(0, 32'h0010_0093, "addi x1, x0, 1");
            audit_word(1, 32'h0000_0113, "addi x2, x0, 0");
            audit_word(2, 32'h0100_2183, "lw x3, 0x10(x0)");
            audit_word(3, 32'h0200_2203, "lw x4, 0x20(x0)");
            audit_word(4, 32'h0000_0293, "addi x5, x0, 0");
            audit_word(5, 32'h0002_0863, "beq x4, x0, 16");
            audit_word(6, 32'h0032_82b3, "add x5, x5, x3");
            audit_word(7, 32'h4012_0233, "sub x4, x4, x1");
            audit_word(8, 32'hfe00_0ae3, "beq x0, x0, -12");
            audit_word(9, 32'h0051_0133, "add x2, x2, x5");
            audit_word(10, 32'h0140_2183, "lw x3, 0x14(x0)");
            audit_word(11, 32'h0240_2203, "lw x4, 0x24(x0)");
            audit_word(12, 32'h0000_0313, "addi x6, x0, 0");
            audit_word(13, 32'h0002_0863, "beq x4, x0, 16");
            audit_word(14, 32'h0033_0333, "add x6, x6, x3");
            audit_word(15, 32'h4012_0233, "sub x4, x4, x1");
            audit_word(16, 32'hfe00_0ae3, "beq x0, x0, -12");
            audit_word(17, 32'h0061_0133, "add x2, x2, x6");
            audit_word(18, 32'h0180_2183, "lw x3, 0x18(x0)");
            audit_word(19, 32'h0280_2203, "lw x4, 0x28(x0)");
            audit_word(20, 32'h0000_0393, "addi x7, x0, 0");
            audit_word(21, 32'h0002_0863, "beq x4, x0, 16");
            audit_word(22, 32'h0033_83b3, "add x7, x7, x3");
            audit_word(23, 32'h4012_0233, "sub x4, x4, x1");
            audit_word(24, 32'hfe00_0ae3, "beq x0, x0, -12");
            audit_word(25, 32'h0071_0133, "add x2, x2, x7");
            audit_word(26, 32'h01c0_2183, "lw x3, 0x1c(x0)");
            audit_word(27, 32'h02c0_2203, "lw x4, 0x2c(x0)");
            audit_word(28, 32'h0000_0413, "addi x8, x0, 0");
            audit_word(29, 32'h0002_0863, "beq x4, x0, 16");
            audit_word(30, 32'h0034_0433, "add x8, x8, x3");
            audit_word(31, 32'h4012_0233, "sub x4, x4, x1");
            audit_word(32, 32'hfe00_0ae3, "beq x0, x0, -12");
            audit_word(33, 32'h0081_0133, "add x2, x2, x8");
            audit_word(34, 32'h0220_2a23, "sw x2, 0x34(x0)");
            audit_word(35, HALT_WORD, "intentional illegal halt");

            for (int branch_index = 5; branch_index <= 29; branch_index += 8) begin
                if (decode_b_immediate(dut.u_imem.mem[branch_index]) != 32'sd16
                    || decode_b_immediate(dut.u_imem.mem[branch_index + 3]) != -32'sd12) begin
                    $fatal(1, "Software branch decode audit failed at lane %0d",
                        (branch_index - 5) / 8);
                end
            end
        end
    endtask

    task automatic prepare_benchmark(input benchmark_e next_benchmark);
        begin
            benchmark_mode = BENCH_IDLE;
            if (rst_n) begin
                @(negedge clk);
                rst_n = 1'b0;
            end
            repeat (2) @(posedge clk);
            #1;
            clear_memories();
            load_common_data();
            if (next_benchmark == BENCH_ACCEL) begin
                load_accelerator_program();
            end else begin
                load_software_program();
            end

            if (dut.u_imem.mem[0] === 32'd0
                || dut.u_dmem.mem[PACKED_A_ADDR >> 2] !== PACKED_A
                || dut.u_dmem.mem[SCALAR_A0_ADDR >> 2] !== 32'd2
                || dut.u_dmem.mem[ACCEL_RESULT_ADDR >> 2] !== 32'd0
                || dut.u_dmem.mem[SOFTWARE_RESULT_ADDR >> 2] !== 32'd0) begin
                $fatal(1, "Deterministic memory initialization readback failed");
            end

            @(negedge clk);
            benchmark_mode = next_benchmark;
            rst_n = 1'b1;
            #1;
            $display("INIT CHECK mode=%0d mem0=%08h pc=%08h imem_addr=%08h imem_rdata=%08h instr=%08h illegal=%0b",
                next_benchmark, dut.u_imem.mem[0], pc_dbg, dut.imem_addr,
                dut.imem_rdata, instr_dbg, illegal_instr_dbg);
        end
    endtask

    task automatic run_until_halt(
        input benchmark_e active_benchmark,
        input logic [31:0] expected_halt_pc,
        input int unsigned timeout_cycles
    );
        int unsigned elapsed_cycles;
        begin
            elapsed_cycles = 0;
            while ((illegal_instr_dbg !== 1'b1)
                   && (elapsed_cycles < timeout_cycles)) begin
                @(negedge clk);
                elapsed_cycles++;
            end

            if (illegal_instr_dbg !== 1'b1) begin
                $fatal(1,
                    "Benchmark timeout: mode=%0d pc=%08h instr=%08h cycles=%0d status_reads=%0d",
                    active_benchmark, pc_dbg, instr_dbg, program_cycles,
                    status_reads);
            end
            if ((pc_dbg !== expected_halt_pc) || (instr_dbg !== HALT_WORD)) begin
                $fatal(1,
                    "Premature illegal instruction: mode=%0d expected_pc=%08h pc=%08h instr=%08h",
                    active_benchmark, expected_halt_pc, pc_dbg, instr_dbg);
            end
            if (cycles_to_result_store == 0) begin
                $fatal(1, "Benchmark reached halt without final result store");
            end

            benchmark_mode = BENCH_IDLE;
            @(posedge clk);
            #1;
        end
    endtask

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            program_cycles <= 0;
            cycles_to_result_store <= 0;
            final_result_stores <= 0;
            vec_a_writes <= 0;
            vec_b_writes <= 0;
            control_writes <= 0;
            status_reads <= 0;
            status_reads_with_result_valid <= 0;
            result_reads <= 0;
            other_mmio_reads <= 0;
            other_mmio_writes <= 0;
            accepted_starts <= 0;
            pipeline_accepts <= 0;
            completions <= 0;
        end else if (benchmark_mode != BENCH_IDLE) begin
            program_cycles <= program_cycles + 1;

            if (dut.cpu_dmem_we && (dut.cpu_dmem_addr == ACCEL_RESULT_ADDR
                                    || dut.cpu_dmem_addr == SOFTWARE_RESULT_ADDR)) begin
                final_result_stores <= final_result_stores + 1;
                if (cycles_to_result_store == 0) begin
                    cycles_to_result_store <= program_cycles + 1;
                end
                if (dut.cpu_dmem_wdata !== EXPECTED_RESULT) begin
                    $fatal(1, "Wrong final RAM store data: %08h", dut.cpu_dmem_wdata);
                end
                if ((benchmark_mode == BENCH_ACCEL
                     && dut.cpu_dmem_addr != ACCEL_RESULT_ADDR)
                    || (benchmark_mode == BENCH_SOFTWARE
                        && dut.cpu_dmem_addr != SOFTWARE_RESULT_ADDR)) begin
                    $fatal(1, "Benchmark wrote the wrong result RAM address: %08h",
                        dut.cpu_dmem_addr);
                end
            end

            if (dut.accel_mmio_write) begin
                if (benchmark_mode == BENCH_SOFTWARE) begin
                    $fatal(1, "Software-only benchmark performed MMIO write at %08h",
                        dut.cpu_dmem_addr);
                end
                case (dut.cpu_dmem_addr)
                    VEC_A_ADDR: begin
                        vec_a_writes <= vec_a_writes + 1;
                        if (dut.cpu_dmem_wdata !== PACKED_A) begin
                            $fatal(1, "Wrong VEC_A write data: %08h", dut.cpu_dmem_wdata);
                        end
                    end
                    VEC_B_ADDR: begin
                        vec_b_writes <= vec_b_writes + 1;
                        if (dut.cpu_dmem_wdata !== PACKED_B) begin
                            $fatal(1, "Wrong VEC_B write data: %08h", dut.cpu_dmem_wdata);
                        end
                    end
                    CONTROL_ADDR: begin
                        control_writes <= control_writes + 1;
                        if (dut.cpu_dmem_wdata !== 32'd1) begin
                            $fatal(1, "Wrong CONTROL.START write data: %08h",
                                dut.cpu_dmem_wdata);
                        end
                    end
                    default: other_mmio_writes <= other_mmio_writes + 1;
                endcase
            end

            if (dut.accel_mmio_read) begin
                if (benchmark_mode == BENCH_SOFTWARE) begin
                    $fatal(1, "Software-only benchmark performed MMIO read at %08h",
                        dut.cpu_dmem_addr);
                end
                case (dut.cpu_dmem_addr)
                    STATUS_ADDR: begin
                        status_reads <= status_reads + 1;
                        if ((dut.cpu_dmem_rdata & STATUS_RESULT_VALID_MASK) != 0) begin
                            status_reads_with_result_valid <=
                                status_reads_with_result_valid + 1;
                        end
                    end
                    RESULT_ADDR: begin
                        result_reads <= result_reads + 1;
                        if (dut.cpu_dmem_rdata !== EXPECTED_RESULT) begin
                            $fatal(1, "Wrong accelerator RESULT read: %08h",
                                dut.cpu_dmem_rdata);
                        end
                    end
                    default: other_mmio_reads <= other_mmio_reads + 1;
                endcase
            end

            if (dut.u_accel_mmio.start_write && dut.u_accel_mmio.ready) begin
                accepted_starts <= accepted_starts + 1;
            end
            if (dut.u_accel_mmio.input_handshake) begin
                pipeline_accepts <= pipeline_accepts + 1;
            end
            if (dut.u_accel_mmio.output_handshake) begin
                completions <= completions + 1;
            end
        end
    end

    always @(negedge rst_n) begin
        if (dut.u_accel_mmio.command_pending_q
            || dut.u_accel_mmio.inflight_q
            || dut.u_accel_mmio.result_valid_q
            || dut.u_accel_mmio.u_pipeline.stage1_valid_q
            || dut.u_accel_mmio.u_pipeline.stage2_valid_q
            || dut.u_accel_mmio.u_pipeline.stage3_valid_q) begin
            reset_discards <= reset_discards + 1;
        end
    end

    initial begin
        $dumpfile("riscv_accel_software_tb.vcd");
        $dumpvars(0, riscv_accel_software_tb);

        if (golden_dot(PACKED_A, PACKED_B) !== EXPECTED_RESULT) begin
            $fatal(1, "Independent packed-vector golden calculation failed");
        end
        if ((32'd2 * 32'd1) + (32'd4 * 32'd3)
            + (32'd6 * 32'd5) + (32'd8 * 32'd7) != EXPECTED_RESULT) begin
            $fatal(1, "Independent explicit golden arithmetic failed");
        end

        // Delay while reset remains asserted so memory-module time-zero
        // initial blocks finish before hierarchical program/data loading.
        #1;

        $display("[DAY 6] Running CPU-controlled accelerator program");
        prepare_benchmark(BENCH_ACCEL);
        run_until_halt(BENCH_ACCEL, ACCEL_HALT_PC, ACCEL_TIMEOUT_CYCLES);

        if (cycles_to_result_store == 0
            || final_result_stores != 1
            || vec_a_writes != 1
            || vec_b_writes != 1
            || control_writes != 1
            || status_reads < 1
            || status_reads_with_result_valid < 1
            || result_reads != 1
            || other_mmio_reads != 0
            || other_mmio_writes != 0
            || accepted_starts != 1
            || pipeline_accepts != 1
            || completions != 1) begin
            $fatal(1,
                "Accelerator accounting failed: cycles=%0d stores=%0d VA=%0d VB=%0d CTRL=%0d STATUS=%0d STATUS_VALID=%0d RESULT=%0d otherR=%0d otherW=%0d starts=%0d accepts=%0d completions=%0d",
                cycles_to_result_store, final_result_stores, vec_a_writes,
                vec_b_writes, control_writes, status_reads,
                status_reads_with_result_valid, result_reads,
                other_mmio_reads, other_mmio_writes, accepted_starts,
                pipeline_accepts, completions);
        end
        if (dut.u_core.u_regfile.regs[1] !== PACKED_A
            || dut.u_core.u_regfile.regs[2] !== PACKED_B
            || dut.u_core.u_regfile.regs[5] !== EXPECTED_RESULT
            || dut.u_accel_mmio.result_q !== EXPECTED_RESULT
            || dut.u_dmem.mem[ACCEL_RESULT_ADDR >> 2] !== EXPECTED_RESULT) begin
            $fatal(1, "Accelerator data-path result verification failed");
        end
        if (dut.u_accel_mmio.result_valid_q !== 1'b0
            || dut.u_accel_mmio.ready !== 1'b1
            || dut.u_accel_mmio.busy !== 1'b0) begin
            $fatal(1, "RESULT read did not clear RESULT_VALID and restore READY");
        end

        measured_accel_cycles = cycles_to_result_store;
        measured_status_reads = status_reads;
        $display("ACCELERATOR PROGRAM PASSED: result=%0d cycles=%0d status_reads=%0d",
            dut.u_dmem.mem[ACCEL_RESULT_ADDR >> 2], measured_accel_cycles,
            measured_status_reads);
        $display("ACCELERATOR PROTOCOL: starts=%0d accepts=%0d completions=%0d reset_discards=%0d",
            accepted_starts, pipeline_accepts, completions, reset_discards);

        $display("[DAY 6] Running CPU-only repeated-add dot product");
        prepare_benchmark(BENCH_SOFTWARE);
        run_until_halt(BENCH_SOFTWARE, SOFTWARE_HALT_PC,
                       SOFTWARE_TIMEOUT_CYCLES);

        if (cycles_to_result_store == 0
            || final_result_stores != 1
            || vec_a_writes != 0
            || vec_b_writes != 0
            || control_writes != 0
            || status_reads != 0
            || result_reads != 0
            || other_mmio_reads != 0
            || other_mmio_writes != 0
            || accepted_starts != 0
            || pipeline_accepts != 0
            || completions != 0) begin
            $fatal(1,
                "Software accounting failed: cycles=%0d stores=%0d MMIO_R=%0d MMIO_W=%0d starts=%0d accepts=%0d completions=%0d",
                cycles_to_result_store, final_result_stores,
                status_reads + result_reads + other_mmio_reads,
                vec_a_writes + vec_b_writes + control_writes
                    + other_mmio_writes,
                accepted_starts, pipeline_accepts, completions);
        end
        if (dut.u_core.u_regfile.regs[5] !== 32'd2
            || dut.u_core.u_regfile.regs[6] !== 32'd12
            || dut.u_core.u_regfile.regs[7] !== 32'd30
            || dut.u_core.u_regfile.regs[8] !== 32'd56
            || dut.u_core.u_regfile.regs[2] !== EXPECTED_RESULT
            || dut.u_dmem.mem[SOFTWARE_RESULT_ADDR >> 2] !== EXPECTED_RESULT) begin
            $fatal(1, "Software repeated-add product/result verification failed");
        end

        measured_software_cycles = cycles_to_result_store;
        $display("SOFTWARE PROGRAM PASSED: products=2,12,30,56 result=%0d cycles=%0d",
            dut.u_dmem.mem[SOFTWARE_RESULT_ADDR >> 2],
            measured_software_cycles);
        $display("SOFTWARE ACCELERATOR ACTIVITY: reads=0 writes=0 starts=%0d accepts=%0d completions=%0d",
            accepted_starts, pipeline_accepts, completions);

        if (reset_discards != 0) begin
            $fatal(1, "Unexpected reset discard count: %0d", reset_discards);
        end

        $display("DAY6_METRIC accelerator_cycles=%0d software_cycles=%0d status_reads=%0d speedup=%0.6f cycle_reduction_pct=%0.6f",
            measured_accel_cycles, measured_software_cycles,
            measured_status_reads,
            real'(measured_software_cycles) / real'(measured_accel_cycles),
            100.0 * (1.0 - (real'(measured_accel_cycles)
                             / real'(measured_software_cycles))));
        $display("DAY 6 SOC SOFTWARE TEST PASSED");
        $finish;
    end

endmodule

`default_nettype wire
