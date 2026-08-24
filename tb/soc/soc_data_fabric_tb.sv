`timescale 1ns/1ps

module soc_data_fabric_tb;

    localparam logic [31:0] ACCEL_BASE = 32'h0000_0400;
    localparam logic [31:0] CONTROL_ADDR = ACCEL_BASE + 32'h00;
    localparam logic [31:0] STATUS_ADDR  = ACCEL_BASE + 32'h04;
    localparam logic [31:0] VEC_A_ADDR   = ACCEL_BASE + 32'h08;
    localparam logic [31:0] VEC_B_ADDR   = ACCEL_BASE + 32'h0c;
    localparam logic [31:0] RESULT_ADDR  = ACCEL_BASE + 32'h10;

    logic clk = 1'b0;
    logic rst_n = 1'b0;

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

    int unsigned tests_run;
    int unsigned failures;
    int unsigned accepted_starts;
    int unsigned pipeline_accepts;
    int unsigned completions;
    int unsigned intentional_reset_discards;

    soc_data_fabric #(
        .RAM_DEPTH          (256),
        .ACCEL_BASE         (ACCEL_BASE),
        .ACCEL_WINDOW_BYTES (32)
    ) dut (
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
        .DEPTH(256)
    ) u_dmem (
        .clk    (clk),
        .mem_re (ram_re),
        .mem_we (ram_we),
        .addr   (ram_addr),
        .wdata  (ram_wdata),
        .rdata  (ram_rdata)
    );

    dot_product_accel_mmio u_accel (
        .clk        (clk),
        .rst_n      (rst_n),
        .mmio_addr  (accel_mmio_addr),
        .mmio_read  (accel_mmio_read),
        .mmio_write (accel_mmio_write),
        .mmio_wdata (accel_mmio_wdata),
        .mmio_rdata (accel_mmio_rdata)
    );

    always #5 clk <= ~clk;

    always_ff @(posedge clk) begin
        assert (!((ram_re === 1'b1) && (accel_mmio_read === 1'b1)))
            else $fatal(1, "read reached both destinations");
        assert (!((ram_we === 1'b1) && (accel_mmio_write === 1'b1)))
            else $fatal(1, "write reached both destinations");

        if ((u_accel.start_write === 1'b1) && (u_accel.ready === 1'b1)) begin
            accepted_starts <= accepted_starts + 1;
        end

        if (u_accel.input_handshake === 1'b1) begin
            pipeline_accepts <= pipeline_accepts + 1;
        end

        if (u_accel.output_handshake === 1'b1) begin
            completions <= completions + 1;
        end
    end

    function automatic logic [31:0] golden_dot(
        input logic [31:0] vec_a,
        input logic [31:0] vec_b
    );
        logic [31:0] sum;
        logic [15:0] product;
        begin
            sum = 32'd0;
            for (int lane = 0; lane < 4; lane++) begin
                product = {8'd0, vec_a[lane*8 +: 8]}
                          * {8'd0, vec_b[lane*8 +: 8]};
                sum = sum + {16'd0, product};
            end
            golden_dot = sum;
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

    task automatic check_bit(
        input string name,
        input logic got,
        input logic expected
    );
        begin
            if (got !== expected) begin
                $error("%s: expected=%b got=%b", name, expected, got);
                failures++;
            end
        end
    endtask

    task automatic report_test(
        input string name,
        input int unsigned failures_before
    );
        begin
            tests_run++;
            if (failures == failures_before) begin
                $display("[PASS] %s", name);
            end else begin
                $display("[FAIL] %s", name);
            end
        end
    endtask

    task automatic drive_idle;
        begin
            cpu_dmem_re    = 1'b0;
            cpu_dmem_we    = 1'b0;
            cpu_dmem_addr  = 32'd0;
            cpu_dmem_wdata = 32'd0;
        end
    endtask

    task automatic reset_dut;
        begin
            drive_idle();
            rst_n = 1'b0;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic cpu_write_word(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            cpu_dmem_addr  = addr;
            cpu_dmem_wdata = data;
            cpu_dmem_re    = 1'b0;
            cpu_dmem_we    = 1'b1;
            @(posedge clk);
            @(negedge clk);
            drive_idle();
        end
    endtask

    task automatic cpu_read_word(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            @(negedge clk);
            cpu_dmem_addr = addr;
            cpu_dmem_re   = 1'b1;
            cpu_dmem_we   = 1'b0;
            #1 data = cpu_dmem_rdata;
            @(posedge clk);
            @(negedge clk);
            drive_idle();
        end
    endtask

    task automatic wait_for_result_valid(output bit seen);
        /* verilator lint_off UNUSEDSIGNAL */
        logic [31:0] status;
        /* verilator lint_on UNUSEDSIGNAL */
        begin
            seen = 1'b0;
            for (int cycle = 0; cycle < 20; cycle++) begin
                cpu_read_word(STATUS_ADDR, status);
                if (status[2]) begin
                    seen = 1'b1;
                    cycle = 20;
                end
            end
        end
    endtask

    task automatic write_vecs_and_start_consecutive(
        input logic [31:0] vec_a,
        input logic [31:0] vec_b
    );
        begin
            @(negedge clk);
            cpu_dmem_re    = 1'b0;
            cpu_dmem_we    = 1'b1;
            cpu_dmem_addr  = VEC_A_ADDR;
            cpu_dmem_wdata = vec_a;

            @(negedge clk);
            cpu_dmem_addr  = VEC_B_ADDR;
            cpu_dmem_wdata = vec_b;

            @(negedge clk);
            cpu_dmem_addr  = CONTROL_ADDR;
            cpu_dmem_wdata = 32'h0000_0001;

            @(negedge clk);
            drive_idle();
        end
    endtask

    initial begin
        logic [31:0] value;
        logic [31:0] value_b;
        logic [31:0] expected;
        int unsigned failures_before;
        int unsigned starts_before;
        int unsigned accepts_before;
        int unsigned completions_before;
        bit seen;
        bit discard_preconditions_met;

        $dumpfile("sim/waveforms/soc_data_fabric_tb.vcd");
        $dumpvars(0, soc_data_fabric_tb);

        tests_run                 = 0;
        failures                  = 0;
        accepted_starts           = 0;
        pipeline_accepts          = 0;
        completions               = 0;
        intentional_reset_discards = 0;
        drive_idle();

        failures_before = failures;
        check_equal(
            "golden maximum lanes",
            golden_dot(32'hffff_ffff, 32'hffff_ffff),
            32'd260100
        );
        if (failures == failures_before) begin
            $display("[PASS] golden maximum lanes");
        end else begin
            $display("[FAIL] golden maximum lanes");
        end

        reset_dut();
        failures_before = failures;
        cpu_read_word(STATUS_ADDR, value);
        check_equal("reset STATUS", value, 32'h0000_0001);
        cpu_read_word(VEC_A_ADDR, value);
        check_equal("reset VEC_A", value, 32'd0);
        cpu_read_word(VEC_B_ADDR, value);
        check_equal("reset VEC_B", value, 32'd0);
        cpu_read_word(RESULT_ADDR, value);
        check_equal("reset RESULT", value, 32'd0);
        report_test("integrated peripheral reset/default state", failures_before);

        failures_before = failures;
        cpu_dmem_addr = 32'h0000_0020;
        #1;
        check_bit("RAM selected", dut.ram_select, 1'b1);
        check_bit("accelerator not selected for RAM", dut.accel_select, 1'b0);
        report_test("RAM decode", failures_before);

        failures_before = failures;
        cpu_dmem_addr = VEC_A_ADDR;
        #1;
        check_bit("accelerator selected", dut.accel_select, 1'b1);
        check_bit("RAM not selected for accelerator", dut.ram_select, 1'b0);
        check_equal("local VEC_A offset", accel_mmio_addr, 32'h0000_0008);
        report_test("accelerator decode and byte-offset translation", failures_before);

        failures_before = failures;
        cpu_write_word(32'h0000_0020, 32'h1357_9bdf);
        cpu_read_word(32'h0000_0020, value);
        check_equal("RAM store/load", value, 32'h1357_9bdf);
        report_test("normal RAM store/load", failures_before);

        reset_dut();
        failures_before = failures;
        cpu_write_word(VEC_A_ADDR, 32'h2468_ace0);
        cpu_write_word(VEC_B_ADDR, 32'h1122_3344);
        cpu_read_word(VEC_A_ADDR, value);
        cpu_read_word(VEC_B_ADDR, value_b);
        check_equal("global VEC_A", value, 32'h2468_ace0);
        check_equal("global VEC_B", value_b, 32'h1122_3344);
        report_test("global VEC_A/VEC_B write and readback", failures_before);

        failures_before = failures;
        cpu_write_word(32'h0000_0024, 32'ha5a5_5a5a);
        cpu_read_word(32'h0000_0024, value);
        check_equal("RAM mux value", value, 32'ha5a5_5a5a);
        cpu_read_word(VEC_A_ADDR, value);
        check_equal("accelerator mux value", value, 32'h2468_ace0);
        report_test("combinational read-data mux isolation", failures_before);

        failures_before = failures;
        cpu_write_word(32'h0000_0028, 32'hcafe_babe);
        cpu_write_word(VEC_A_ADDR, 32'h0806_0402);
        cpu_write_word(VEC_B_ADDR, 32'h0705_0301);
        cpu_read_word(32'h0000_0028, value);
        check_equal("RAM sentinel after MMIO writes", value, 32'hcafe_babe);
        report_test("no accelerator-write leakage into RAM", failures_before);

        failures_before = failures;
        cpu_write_word(32'h0000_002c, 32'hdead_beef);
        cpu_read_word(VEC_A_ADDR, value);
        cpu_read_word(VEC_B_ADDR, value_b);
        check_equal("VEC_A after RAM write", value, 32'h0806_0402);
        check_equal("VEC_B after RAM write", value_b, 32'h0705_0301);
        report_test("no RAM-write leakage into accelerator", failures_before);

        failures_before = failures;
        starts_before = accepted_starts;
        cpu_write_word(CONTROL_ADDR, 32'h0000_0001);
        if (accepted_starts != (starts_before + 1)) begin
            $error("global START accepted %0d times, expected exactly once",
                   accepted_starts - starts_before);
            failures++;
        end
        report_test("START through global address", failures_before);

        failures_before = failures;
        cpu_read_word(STATUS_ADDR, value);
        check_bit("STATUS busy", value[1], 1'b1);
        check_bit("STATUS not ready while active", value[0], 1'b0);
        wait_for_result_valid(seen);
        if (!seen) begin
            $error("STATUS.RESULT_VALID was not observed");
            failures++;
        end
        report_test("STATUS through global address", failures_before);

        failures_before = failures;
        expected = golden_dot(32'h0806_0402, 32'h0705_0301);
        cpu_read_word(RESULT_ADDR, value);
        check_equal("global RESULT", value, expected);
        check_equal("independent expected result", expected, 32'd100);
        report_test("RESULT through global address", failures_before);

        reset_dut();
        failures_before = failures;
        cpu_dmem_addr = 32'h0000_0000;
        #1;
        check_bit("RAM first byte selected", dut.ram_select, 1'b1);
        cpu_dmem_addr = 32'h0000_03ff;
        #1;
        check_bit("byte below accelerator is RAM", dut.ram_select, 1'b1);
        check_bit("byte below accelerator not MMIO", dut.accel_select, 1'b0);
        cpu_dmem_addr = 32'h0000_0400;
        #1;
        check_bit("accelerator first byte selected", dut.accel_select, 1'b1);
        cpu_dmem_addr = 32'h0000_041f;
        #1;
        check_bit("accelerator last byte selected", dut.accel_select, 1'b1);
        check_equal("last local byte offset", accel_mmio_addr, 32'h0000_001f);
        cpu_dmem_addr = 32'h0000_0420;
        #1;
        check_bit("above accelerator not RAM", dut.ram_select, 1'b0);
        check_bit("above accelerator not MMIO", dut.accel_select, 1'b0);
        cpu_write_word(32'h0000_03fc, 32'hfeed_face);
        cpu_read_word(32'h0000_03fc, value);
        check_equal("highest aligned RAM word", value, 32'hfeed_face);
        report_test("RAM and accelerator address boundaries", failures_before);

        reset_dut();
        failures_before = failures;
        cpu_write_word(VEC_A_ADDR, 32'h0102_0304);
        cpu_write_word(ACCEL_BASE + 32'h14, 32'hffff_ffff);
        cpu_read_word(ACCEL_BASE + 32'h14, value);
        check_equal("invalid local offset read", value, 32'd0);
        cpu_read_word(VEC_A_ADDR, value);
        check_equal("invalid local write ignored", value, 32'h0102_0304);
        report_test("invalid accelerator local offset", failures_before);

        reset_dut();
        failures_before = failures;
        starts_before = accepted_starts;
        accepts_before = pipeline_accepts;
        write_vecs_and_start_consecutive(32'h0806_0402, 32'h0705_0301);
        wait_for_result_valid(seen);
        if (!seen) begin
            $error("consecutive access operation did not complete");
            failures++;
        end
        cpu_read_word(RESULT_ADDR, value);
        expected = golden_dot(32'h0806_0402, 32'h0705_0301);
        check_equal("consecutive access result", value, expected);
        if (accepted_starts != (starts_before + 1)) begin
            $error("consecutive sequence did not produce one accepted START");
            failures++;
        end
        if (pipeline_accepts != (accepts_before + 1)) begin
            $error("consecutive sequence did not produce one pipeline accept");
            failures++;
        end
        report_test("consecutive-cycle VEC_A/VEC_B/START writes", failures_before);

        failures_before = failures;
        cpu_read_word(32'h0000_0800, value);
        check_equal("unmapped read data", value, 32'd0);
        report_test("unmapped read returns zero", failures_before);

        reset_dut();
        failures_before = failures;
        cpu_write_word(32'h0000_0030, 32'h55aa_aa55);
        cpu_write_word(VEC_A_ADDR, 32'h89ab_cdef);
        cpu_write_word(32'h0000_0800, 32'hffff_ffff);
        cpu_read_word(32'h0000_0030, value);
        check_equal("RAM after unmapped write", value, 32'h55aa_aa55);
        cpu_read_word(VEC_A_ADDR, value);
        check_equal("VEC_A after unmapped write", value, 32'h89ab_cdef);
        report_test("unmapped write ignored", failures_before);

        reset_dut();
        failures_before = failures;
        starts_before = accepted_starts;
        accepts_before = pipeline_accepts;
        completions_before = completions;
        cpu_write_word(VEC_A_ADDR, 32'h0806_0402);
        cpu_write_word(VEC_B_ADDR, 32'h0705_0301);
        cpu_write_word(CONTROL_ADDR, 32'h0000_0001);

        // Wait for the accepted command to enter the pipeline, then prove it
        // is still outstanding before intentionally discarding it with reset.
        @(posedge clk);
        #1;
        discard_preconditions_met = 1'b1;
        if (accepted_starts != (starts_before + 1)) begin
            $error(
                "reset-discard START mismatch: before=%0d after=%0d",
                starts_before,
                accepted_starts
            );
            failures++;
            discard_preconditions_met = 1'b0;
        end
        if (pipeline_accepts != (accepts_before + 1)) begin
            $error(
                "reset-discard pipeline accept mismatch: before=%0d after=%0d",
                accepts_before,
                pipeline_accepts
            );
            failures++;
            discard_preconditions_met = 1'b0;
        end
        if (completions != completions_before) begin
            $error(
                "reset-discard operation completed too early: before=%0d after=%0d",
                completions_before,
                completions
            );
            failures++;
            discard_preconditions_met = 1'b0;
        end
        @(negedge clk);
        rst_n = 1'b0;
        if (discard_preconditions_met) begin
            intentional_reset_discards++;
        end
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (8) @(posedge clk);
        cpu_read_word(STATUS_ADDR, value);
        check_equal("post-reset STATUS", value, 32'h0000_0001);
        cpu_read_word(RESULT_ADDR, value);
        check_equal("post-reset no stale RESULT", value, 32'd0);
        cpu_read_word(VEC_A_ADDR, value);
        check_equal("post-reset VEC_A clear", value, 32'd0);
        report_test("reset discards active integrated operation", failures_before);

        if (accepted_starts != pipeline_accepts) begin
            $error(
                "START/accounting mismatch: accepted=%0d pipeline_accepts=%0d",
                accepted_starts,
                pipeline_accepts
            );
            failures++;
        end

        if (pipeline_accepts
            != (completions + intentional_reset_discards)) begin
            $error(
                "Completion accounting mismatch: accepts=%0d completions=%0d reset_discards=%0d",
                pipeline_accepts,
                completions,
                intentional_reset_discards
            );
            failures++;
        end

        $display("");
        $display("============================================");
        $display("SoC Data Fabric Test Summary");
        $display("============================================");
        $display("Tests run             : %0d", tests_run);
        $display("Test failures         : %0d", failures);
        $display("Accepted START writes : %0d", accepted_starts);
        $display("Pipeline input accepts: %0d", pipeline_accepts);
        $display("Captured completions  : %0d", completions);
        $display("Intentional reset discards: %0d", intentional_reset_discards);
        $display("============================================");

        if (failures == 0) begin
            $display("ALL SOC DATA FABRIC TESTS PASSED");
        end else begin
            $fatal(1, "SOC DATA FABRIC TESTS FAILED: %0d failures", failures);
        end

        $finish;
    end

endmodule
