`timescale 1ns/1ps
`default_nettype none

module dot_product_accel_mmio_tb;

    localparam int CLK_PERIOD_NS   = 10;
    localparam int MAX_WAIT_CYCLES = 30;
    localparam int RANDOM_TESTS    = 32;

    localparam logic [31:0] CONTROL_OFFSET = 32'h0000_0000;
    localparam logic [31:0] STATUS_OFFSET  = 32'h0000_0004;
    localparam logic [31:0] VEC_A_OFFSET   = 32'h0000_0008;
    localparam logic [31:0] VEC_B_OFFSET   = 32'h0000_000c;
    localparam logic [31:0] RESULT_OFFSET  = 32'h0000_0010;

    localparam logic [31:0] STATUS_READY        = 32'h0000_0001;
    localparam logic [31:0] STATUS_BUSY         = 32'h0000_0002;
    localparam logic [31:0] STATUS_RESULT_VALID = 32'h0000_0004;

    logic clk;
    logic rst_n;
    logic [31:0] mmio_addr;
    logic mmio_read;
    logic mmio_write;
    logic [31:0] mmio_wdata;
    logic [31:0] mmio_rdata;

    int unsigned tests_run;
    int unsigned failures;
    int unsigned protocol_failures;
    int unsigned accepted_start_count;
    int unsigned input_handshake_count;
    int unsigned completion_count;
    int unsigned intentional_reset_discard_count;
    int unsigned random_seed;

    logic previous_result_valid;
    logic [31:0] previous_result;
    logic previous_pending;
    logic [31:0] previous_command_a;
    logic [31:0] previous_command_b;

    dot_product_accel_mmio dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .mmio_addr  (mmio_addr),
        .mmio_read  (mmio_read),
        .mmio_write (mmio_write),
        .mmio_wdata (mmio_wdata),
        .mmio_rdata (mmio_rdata)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2) clk <= ~clk;

    function automatic logic [31:0] golden_dot(
        input logic [31:0] a,
        input logic [31:0] b
    );
        int element;
        logic [31:0] accumulator;
        begin
            accumulator = 32'h0000_0000;
            for (element = 0; element < 4; element = element + 1) begin
                accumulator = accumulator
                    + (a[element*8 +: 8] * b[element*8 +: 8]);
            end
            golden_dot = accumulator;
        end
    endfunction

    task automatic report_test(input string name, input bit failed);
        begin
            tests_run = tests_run + 1;
            if (failed) begin
                failures = failures + 1;
                $display("[FAIL] %s", name);
            end else begin
                $display("[PASS] %s", name);
            end
        end
    endtask

    task automatic check_equal(
        input string label,
        input logic [31:0] actual,
        input logic [31:0] expected,
        inout bit failed
    );
        begin
            if (actual !== expected) begin
                failed = 1'b1;
                $display("       %s: expected 0x%08h, got 0x%08h",
                         label, expected, actual);
            end
        end
    endtask

    task automatic mmio_write_word(
        input logic [31:0] address,
        input logic [31:0] data
    );
        begin
            @(negedge clk);
            mmio_addr  = address;
            mmio_wdata = data;
            mmio_write = 1'b1;
            mmio_read  = 1'b0;
            @(posedge clk);
            #1;
            @(negedge clk);
            mmio_write = 1'b0;
            mmio_addr  = 32'h0000_0000;
            mmio_wdata = 32'h0000_0000;
        end
    endtask

    task automatic mmio_read_word(
        input  logic [31:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge clk);
            mmio_addr  = address;
            mmio_read  = 1'b1;
            mmio_write = 1'b0;
            #1;
            data = mmio_rdata;
            @(posedge clk);
            #1;
            @(negedge clk);
            mmio_read = 1'b0;
            mmio_addr = 32'h0000_0000;
        end
    endtask

    task automatic write_operands_and_start_consecutive(
        input logic [31:0] a,
        input logic [31:0] b
    );
        begin
            // Keep write asserted while presenting VEC_A, VEC_B, and START
            // on three consecutive rising edges with no idle edge between.
            @(negedge clk);
            mmio_read  = 1'b0;
            mmio_write = 1'b1;
            mmio_addr  = VEC_A_OFFSET;
            mmio_wdata = a;

            @(posedge clk);
            #1;
            @(negedge clk);
            mmio_addr  = VEC_B_OFFSET;
            mmio_wdata = b;

            @(posedge clk);
            #1;
            @(negedge clk);
            mmio_addr  = CONTROL_OFFSET;
            mmio_wdata = 32'h0000_0001;

            @(posedge clk);
            #1;
            @(negedge clk);
            mmio_write = 1'b0;
            mmio_addr  = 32'h0000_0000;
            mmio_wdata = 32'h0000_0000;
        end
    endtask

    task automatic peek_word(
        input  logic [31:0] address,
        output logic [31:0] data
    );
        begin
            @(negedge clk);
            mmio_addr  = address;
            mmio_read  = 1'b1;
            mmio_write = 1'b0;
            #1;
            data = mmio_rdata;
            mmio_read = 1'b0;
            mmio_addr = 32'h0000_0000;
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n      = 1'b0;
            mmio_addr  = 32'h0000_0000;
            mmio_read  = 1'b0;
            mmio_write = 1'b0;
            mmio_wdata = 32'h0000_0000;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic wait_for_result_valid(output bit seen);
        int cycles;
        logic [31:0] status;
        begin
            seen = 1'b0;
            status = 32'h0000_0000;
            for (cycles = 0; cycles < MAX_WAIT_CYCLES; cycles = cycles + 1) begin
                peek_word(STATUS_OFFSET, status);
                if (status == STATUS_RESULT_VALID) begin
                    seen = 1'b1;
                    cycles = MAX_WAIT_CYCLES;
                end
            end
            if (!seen) begin
                $display("       Timeout waiting for RESULT_VALID: pending=%b inflight=%b pipe_out_valid=%b",
                         dut.command_pending_q, dut.inflight_q,
                         dut.pipe_out_valid);
            end
        end
    endtask

    task automatic start_operation(
        input logic [31:0] a,
        input logic [31:0] b
    );
        begin
            mmio_write_word(VEC_A_OFFSET, a);
            mmio_write_word(VEC_B_OFFSET, b);
            mmio_write_word(CONTROL_OFFSET, 32'h0000_0001);
        end
    endtask

    task automatic collect_result(
        input  logic [31:0] expected,
        output bit failed
    );
        bit seen;
        logic [31:0] status;
        logic [31:0] value;
        begin
            failed = 1'b0;
            wait_for_result_valid(seen);
            if (!seen) begin
                failed = 1'b1;
            end else begin
                peek_word(STATUS_OFFSET, status);
                check_equal("completed status", status,
                            STATUS_RESULT_VALID, failed);
                mmio_read_word(RESULT_OFFSET, value);
                check_equal("dot-product result", value, expected, failed);
                peek_word(STATUS_OFFSET, status);
                check_equal("status after RESULT read", status,
                            STATUS_READY, failed);
            end
        end
    endtask

    task automatic run_operation(
        input logic [31:0] a,
        input logic [31:0] b,
        output bit failed
    );
        begin
            start_operation(a, b);
            collect_result(golden_dot(a, b), failed);
        end
    endtask

    // Protocol monitor uses the wrapper's internal ready/valid boundary to
    // check the behavior that software cannot directly observe.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            previous_result_valid <= 1'b0;
            previous_result       <= 32'h0000_0000;
            previous_pending      <= 1'b0;
            previous_command_a    <= 32'h0000_0000;
            previous_command_b    <= 32'h0000_0000;
        end else begin
            if (mmio_write && (mmio_addr == CONTROL_OFFSET)
                && mmio_wdata[0] && dut.ready) begin
                accepted_start_count <= accepted_start_count + 1;
            end

            if (dut.input_handshake) begin
                input_handshake_count <= input_handshake_count + 1;
            end

            if (dut.output_handshake) begin
                completion_count <= completion_count + 1;
            end

            if (dut.ready !== !(dut.command_pending_q
                                || dut.inflight_q
                                || dut.result_valid_q)) begin
                protocol_failures <= protocol_failures + 1;
                $error("READY state equation violated");
            end

            if (dut.busy !== (dut.command_pending_q || dut.inflight_q)) begin
                protocol_failures <= protocol_failures + 1;
                $error("BUSY state equation violated");
            end

            if (dut.pipe_in_valid !== dut.command_pending_q) begin
                protocol_failures <= protocol_failures + 1;
                $error("in_valid does not track pending command");
            end

            if (dut.pipe_out_ready !== !dut.result_valid_q) begin
                protocol_failures <= protocol_failures + 1;
                $error("out_ready does not protect the result slot");
            end

            if (previous_result_valid && dut.result_valid_q
                && (dut.result_q !== previous_result)) begin
                protocol_failures <= protocol_failures + 1;
                $error("Unread RESULT changed");
            end

            if (previous_pending && dut.command_pending_q
                && ((dut.command_vec_a_q !== previous_command_a)
                    || (dut.command_vec_b_q !== previous_command_b))) begin
                protocol_failures <= protocol_failures + 1;
                $error("Pending command operands changed before handshake");
            end

            previous_result_valid <= dut.result_valid_q;
            previous_result       <= dut.result_q;
            previous_pending      <= dut.command_pending_q;
            previous_command_a    <= dut.command_vec_a_q;
            previous_command_b    <= dut.command_vec_b_q;
        end
    end

    initial begin : run_tests
        bit failed;
        bit operation_failed;
        bit seen;
        int index;
        int unsigned starts_before;
        int unsigned completions_before;
        logic [31:0] value;
        logic [31:0] status;
        logic [31:0] saved_a;
        logic [31:0] saved_b;
        logic [31:0] retained_result;
        logic [31:0] random_a;
        logic [31:0] random_b;

        $dumpfile("sim/waveforms/dot_product_accel_mmio_tb.vcd");
        $dumpvars(0, dot_product_accel_mmio_tb);

        rst_n                  = 1'b0;
        mmio_addr              = 32'h0000_0000;
        mmio_read              = 1'b0;
        mmio_write             = 1'b0;
        mmio_wdata             = 32'h0000_0000;
        tests_run              = 0;
        failures               = 0;
        protocol_failures      = 0;
        accepted_start_count   = 0;
        input_handshake_count  = 0;
        completion_count       = 0;
        intentional_reset_discard_count = 0;
        random_seed            = 32'hD400_0001;
        void'($urandom(random_seed));

        reset_dut();

        failed = 1'b0;
        peek_word(STATUS_OFFSET, status);
        check_equal("reset STATUS", status, STATUS_READY, failed);
        peek_word(VEC_A_OFFSET, value);
        check_equal("reset VEC_A", value, 32'h0000_0000, failed);
        peek_word(VEC_B_OFFSET, value);
        check_equal("reset VEC_B", value, 32'h0000_0000, failed);
        peek_word(RESULT_OFFSET, value);
        check_equal("reset RESULT", value, 32'h0000_0000, failed);
        report_test("reset/default register state", failed);

        failed = 1'b0;
        mmio_read_word(RESULT_OFFSET, value);
        check_equal("RESULT before first completion", value,
                    32'h0000_0000, failed);
        peek_word(STATUS_OFFSET, status);
        check_equal("early RESULT read status", status, STATUS_READY, failed);
        report_test("RESULT read before valid", failed);

        failed = 1'b0;
        mmio_write_word(VEC_A_OFFSET, 32'h0403_0201);
        mmio_write_word(VEC_B_OFFSET, 32'h0807_0605);
        peek_word(VEC_A_OFFSET, value);
        check_equal("VEC_A readback", value, 32'h0403_0201, failed);
        peek_word(VEC_B_OFFSET, value);
        check_equal("VEC_B readback", value, 32'h0807_0605, failed);
        report_test("operand register readback", failed);

        failed = 1'b0;
        saved_a = 32'h0806_0402;
        saved_b = 32'h0705_0301;
        write_operands_and_start_consecutive(saved_a, saved_b);
        collect_result(golden_dot(saved_a, saved_b), operation_failed);
        failed = failed || operation_failed;
        report_test("consecutive-cycle VEC_A/VEC_B/START writes", failed);

        run_operation(32'h0403_0201, 32'h0807_0605, failed);
        report_test("basic 1*5 + 2*6 + 3*7 + 4*8 = 70", failed);

        run_operation(32'h0000_0000, 32'h0807_0605, failed);
        report_test("zero vector", failed);

        run_operation(32'hffff_ffff, 32'hffff_ffff, failed);
        report_test("maximum unsigned values = 260100", failed);

        failed = 1'b0;
        for (index = 0; index < RANDOM_TESTS; index = index + 1) begin
            random_a = $urandom();
            random_b = $urandom();
            run_operation(random_a, random_b, operation_failed);
            failed = failed || operation_failed;
        end
        report_test("32 reproducible sequential MMIO operations", failed);

        failed = 1'b0;
        saved_a = 32'h0403_0201;
        saved_b = 32'h0807_0605;
        start_operation(saved_a, saved_b);
        peek_word(STATUS_OFFSET, status);
        check_equal("active-operation status", status, STATUS_BUSY, failed);
        starts_before = accepted_start_count;
        mmio_write_word(CONTROL_OFFSET, 32'h0000_0001);
        mmio_write_word(VEC_A_OFFSET, 32'hffff_ffff);
        mmio_write_word(VEC_B_OFFSET, 32'hffff_ffff);
        wait_for_result_valid(seen);
        if (!seen || (accepted_start_count !== starts_before)) begin
            failed = 1'b1;
            $display("       START while BUSY was accepted or completion timed out");
        end
        peek_word(VEC_A_OFFSET, value);
        check_equal("VEC_A after BUSY write", value, saved_a, failed);
        peek_word(VEC_B_OFFSET, value);
        check_equal("VEC_B after BUSY write", value, saved_b, failed);
        mmio_read_word(RESULT_OFFSET, value);
        check_equal("result after BUSY interference", value,
                    golden_dot(saved_a, saved_b), failed);
        report_test("START and operand writes while BUSY ignored", failed);

        failed = 1'b0;
        saved_a = 32'h0101_0101;
        saved_b = 32'h0202_0202;
        start_operation(saved_a, saved_b);
        wait_for_result_valid(seen);
        starts_before = accepted_start_count;
        completions_before = completion_count;
        mmio_write_word(CONTROL_OFFSET, 32'h0000_0001);
        mmio_write_word(VEC_A_OFFSET, 32'haaaa_aaaa);
        mmio_write_word(VEC_B_OFFSET, 32'h5555_5555);
        peek_word(STATUS_OFFSET, status);
        check_equal("occupied-result status", status,
                    STATUS_RESULT_VALID, failed);
        if ((accepted_start_count !== starts_before)
            || (completion_count !== completions_before)) begin
            failed = 1'b1;
            $display("       Work was accepted while RESULT_VALID was set");
        end
        peek_word(VEC_A_OFFSET, value);
        check_equal("VEC_A while RESULT_VALID", value, saved_a, failed);
        peek_word(VEC_B_OFFSET, value);
        check_equal("VEC_B while RESULT_VALID", value, saved_b, failed);
        mmio_read_word(RESULT_OFFSET, value);
        check_equal("held result", value, golden_dot(saved_a, saved_b), failed);
        report_test("START and operand writes while RESULT_VALID ignored", failed);

        failed = 1'b0;
        start_operation(32'h0400_0201, 32'h0305_0007);
        wait_for_result_valid(seen);
        peek_word(STATUS_OFFSET, status);
        peek_word(STATUS_OFFSET, status);
        peek_word(STATUS_OFFSET, status);
        if (!status[2]) begin
            failed = 1'b1;
            $display("       STATUS polling cleared RESULT_VALID");
        end
        mmio_read_word(RESULT_OFFSET, retained_result);
        check_equal("read-to-clear result", retained_result,
                    golden_dot(32'h0400_0201, 32'h0305_0007), failed);
        peek_word(STATUS_OFFSET, status);
        check_equal("ready after consume", status, STATUS_READY, failed);
        peek_word(RESULT_OFFSET, value);
        check_equal("retained RESULT data", value, retained_result, failed);
        report_test("RESULT_VALID read-to-clear and data retention", failed);

        failed = 1'b0;
        saved_a = 32'h1122_3344;
        saved_b = 32'h5566_7788;
        mmio_write_word(VEC_A_OFFSET, saved_a);
        mmio_write_word(VEC_B_OFFSET, saved_b);
        mmio_write_word(32'h0000_0001, 32'hffff_ffff);
        mmio_write_word(32'h0000_0002, 32'hffff_ffff);
        mmio_write_word(32'h0000_0006, 32'hffff_ffff);
        mmio_write_word(32'h0000_0014, 32'hffff_ffff);
        peek_word(32'h0000_0001, value);
        check_equal("unaligned read 0x01", value, 32'h0000_0000, failed);
        peek_word(32'h0000_0006, value);
        check_equal("unaligned read 0x06", value, 32'h0000_0000, failed);
        peek_word(32'h0000_0014, value);
        check_equal("unknown read 0x14", value, 32'h0000_0000, failed);
        peek_word(VEC_A_OFFSET, value);
        check_equal("VEC_A after invalid writes", value, saved_a, failed);
        peek_word(VEC_B_OFFSET, value);
        check_equal("VEC_B after invalid writes", value, saved_b, failed);
        report_test("invalid and unaligned offsets", failed);

        failed = 1'b0;
        peek_word(STATUS_OFFSET, status);
        peek_word(RESULT_OFFSET, retained_result);
        mmio_write_word(STATUS_OFFSET, 32'hffff_ffff);
        mmio_write_word(RESULT_OFFSET, 32'hdead_beef);
        peek_word(STATUS_OFFSET, value);
        check_equal("STATUS after write", value, status, failed);
        peek_word(RESULT_OFFSET, value);
        check_equal("RESULT after write", value, retained_result, failed);
        report_test("writes to read-only registers ignored", failed);

        failed = 1'b0;
        mmio_read_word(CONTROL_OFFSET, value);
        check_equal("CONTROL read", value, 32'h0000_0000, failed);
        mmio_write_word(CONTROL_OFFSET, 32'hffff_fffe);
        peek_word(STATUS_OFFSET, status);
        check_equal("reserved CONTROL bits", status, STATUS_READY, failed);
        report_test("CONTROL read and zero/reserved writes", failed);

        failed = 1'b0;
        start_operation(32'h0a09_0807, 32'h0605_0403);
        completions_before = completion_count;
        repeat (3) begin
            mmio_write_word(CONTROL_OFFSET, 32'h0000_0001);
        end
        wait_for_result_valid(seen);
        if (!seen || ((completion_count - completions_before) !== 1)) begin
            failed = 1'b1;
            $display("       Repeated invalid START writes changed completion count");
        end
        mmio_read_word(RESULT_OFFSET, value);
        check_equal("single result after repeated START", value,
                    golden_dot(32'h0a09_0807, 32'h0605_0403), failed);
        repeat (5) @(posedge clk);
        if (completion_count !== (completions_before + 1)) begin
            failed = 1'b1;
            $display("       Duplicate result appeared after repeated START writes");
        end
        report_test("repeated invalid START writes do not queue", failed);

        failed = 1'b0;
        start_operation(32'hffff_ffff, 32'hffff_ffff);
        @(posedge clk);
        #1;
        if (!dut.inflight_q) begin
            failed = 1'b1;
            $display("       Operation was not in flight before reset");
        end else begin
            intentional_reset_discard_count =
                intentional_reset_discard_count + 1;
        end
        @(negedge clk);
        rst_n = 1'b0;
        #1;
        if (dut.command_pending_q || dut.inflight_q || dut.result_valid_q) begin
            failed = 1'b1;
            $display("       Reset did not discard wrapper state");
        end
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (6) @(posedge clk);
        peek_word(STATUS_OFFSET, status);
        check_equal("post-reset status", status, STATUS_READY, failed);
        if (dut.pipe_out_valid) begin
            failed = 1'b1;
            $display("       Stale pipeline output appeared after reset");
        end
        report_test("reset discards active operation", failed);

        run_operation(32'h0403_0201, 32'h0807_0605, failed);
        report_test("post-reset recovery", failed);

        if (accepted_start_count !== input_handshake_count) begin
            protocol_failures = protocol_failures + 1;
            $error("Transaction accounting mismatch: accepted STARTs=%0d input handshakes=%0d",
                   accepted_start_count, input_handshake_count);
        end

        if (input_handshake_count
            !== (completion_count + intentional_reset_discard_count)) begin
            protocol_failures = protocol_failures + 1;
            $error("Transaction accounting mismatch: input handshakes=%0d completions=%0d reset discards=%0d",
                   input_handshake_count, completion_count,
                   intentional_reset_discard_count);
        end

        $display("");
        $display("============================================");
        $display("Day 4 MMIO Accelerator Test Summary");
        $display("============================================");
        $display("Tests run             : %0d", tests_run);
        $display("Test failures         : %0d", failures);
        $display("Protocol failures     : %0d", protocol_failures);
        $display("Accepted START writes : %0d", accepted_start_count);
        $display("Pipeline input accepts: %0d", input_handshake_count);
        $display("Captured completions  : %0d", completion_count);
        $display("Intentional reset discards: %0d",
                 intentional_reset_discard_count);
        $display("============================================");

        if ((failures == 0) && (protocol_failures == 0)) begin
            $display("ALL MMIO ACCELERATOR TESTS PASSED");
            $finish;
        end else begin
            $display("MMIO ACCELERATOR TESTS FAILED");
            $fatal(1);
        end
    end

    initial begin : watchdog
        repeat (10000) @(posedge clk);
        $fatal(1, "MMIO testbench watchdog expired");
    end

endmodule

`default_nettype wire
