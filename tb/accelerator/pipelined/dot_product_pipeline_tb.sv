`timescale 1ns/1ps

module dot_product_pipeline_tb;

    localparam int ELEM_WIDTH       = 8;
    localparam int NUM_ELEMS        = 4;
    localparam int RESULT_WIDTH     = 32;
    localparam int VECTOR_WIDTH     = ELEM_WIDTH * NUM_ELEMS;
    localparam int CLK_PERIOD_NS    = 10;
    localparam int MAX_WAIT_CYCLES  = 20;

    logic                    clk;
    logic                    rst_n;
    logic                    in_valid;
    logic                    in_ready;
    logic [VECTOR_WIDTH-1:0] vec_a;
    logic [VECTOR_WIDTH-1:0] vec_b;
    logic                    out_valid;
    logic                    out_ready;
    logic [RESULT_WIDTH-1:0] result;

    int unsigned tests_run;
    int unsigned failures;
    int unsigned protocol_failures;
    int unsigned cycle_count;
    int unsigned input_handshakes;
    int unsigned output_handshakes;
    int unsigned last_input_edge;
    int unsigned last_output_edge;

    int unsigned timing_accept_edge;
    int unsigned timing_available_edge;
    int unsigned timing_consume_edge;
    int unsigned back_to_back_available_edges [0:2];

    logic                    stall_active;
    logic [RESULT_WIDTH-1:0] stalled_result;

    dot_product_pipeline #(
        .ELEM_WIDTH   (ELEM_WIDTH),
        .NUM_ELEMS    (NUM_ELEMS),
        .RESULT_WIDTH (RESULT_WIDTH)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_ready  (in_ready),
        .vec_a     (vec_a),
        .vec_b     (vec_b),
        .out_valid (out_valid),
        .out_ready (out_ready),
        .result    (result)
    );

    initial begin
        clk = 1'b0;
    end

    always #(CLK_PERIOD_NS/2) clk <= ~clk;

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;

        if (in_valid && in_ready) begin
            input_handshakes <= input_handshakes + 1;
            last_input_edge  <= cycle_count + 1;
        end

        if (out_valid && out_ready) begin
            output_handshakes <= output_handshakes + 1;
            last_output_edge  <= cycle_count + 1;
        end
    end

    // Protocol invariant: an offered transaction cannot change while stalled.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_active   <= 1'b0;
            stalled_result <= '0;
        end else begin
            if (stall_active) begin
                if ((out_valid !== 1'b1) || (result !== stalled_result)) begin
                    protocol_failures <= protocol_failures + 1;
                    $error("Output valid/data changed while stalled at edge %0d",
                           cycle_count);
                end
            end

            stall_active <= out_valid && !out_ready;

            if (out_valid && !out_ready) begin
                stalled_result <= result;
            end
        end
    end

    function automatic logic [RESULT_WIDTH-1:0] golden_dot(
        input logic [VECTOR_WIDTH-1:0] a,
        input logic [VECTOR_WIDTH-1:0] b
    );
        int unsigned i;
        logic [RESULT_WIDTH-1:0] acc;
        logic [ELEM_WIDTH-1:0] a_elem;
        logic [ELEM_WIDTH-1:0] b_elem;

        begin
            acc = '0;

            for (i = 0; i < NUM_ELEMS; i = i + 1) begin
                a_elem = a[i*ELEM_WIDTH +: ELEM_WIDTH];
                b_elem = b[i*ELEM_WIDTH +: ELEM_WIDTH];
                acc = acc + (RESULT_WIDTH'(a_elem) * RESULT_WIDTH'(b_elem));
            end

            golden_dot = acc;
        end
    endfunction

    task automatic report_test(
        input string test_name,
        input bit test_failed
    );
        begin
            tests_run = tests_run + 1;

            if (test_failed) begin
                failures = failures + 1;
                $display("[FAIL] %-40s", test_name);
            end else begin
                $display("[PASS] %-40s", test_name);
            end
        end
    endtask

    task automatic reset_dut;
        begin
            @(negedge clk);
            rst_n     = 1'b0;
            in_valid  = 1'b0;
            vec_a     = '0;
            vec_b     = '0;
            out_ready = 1'b0;

            repeat (2) @(posedge clk);

            @(negedge clk);
            rst_n     = 1'b1;
            out_ready = 1'b1;

            @(posedge clk);
            #1;
        end
    endtask

    task automatic send_one(
        input logic [VECTOR_WIDTH-1:0] a,
        input logic [VECTOR_WIDTH-1:0] b,
        output int unsigned accept_edge,
        output bit send_failed
    );
        int unsigned handshakes_before;
        int unsigned wait_cycles;

        begin
            send_failed      = 1'b0;
            handshakes_before = input_handshakes;
            wait_cycles       = 0;

            @(negedge clk);
            vec_a    = a;
            vec_b    = b;
            in_valid = 1'b1;

            while ((in_ready !== 1'b1) && (wait_cycles < MAX_WAIT_CYCLES)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end

            if (in_ready !== 1'b1) begin
                send_failed = 1'b1;
                $display("       Timed out waiting for in_ready.");
            end else begin
                @(posedge clk);
                #1;

                if (input_handshakes != (handshakes_before + 1)) begin
                    send_failed = 1'b1;
                    $display("       Input was not counted on its handshake edge.");
                end
            end

            accept_edge = last_input_edge;

            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;
        end
    endtask

    task automatic expect_one(
        input logic [RESULT_WIDTH-1:0] expected,
        output int unsigned available_edge,
        output int unsigned consume_edge,
        output bit receive_failed
    );
        int unsigned handshakes_before;
        int unsigned wait_cycles;

        begin
            receive_failed   = 1'b0;
            wait_cycles      = 0;
            handshakes_before = output_handshakes;

            while ((out_valid !== 1'b1) && (wait_cycles < MAX_WAIT_CYCLES)) begin
                @(negedge clk);
                wait_cycles = wait_cycles + 1;
            end

            available_edge = cycle_count;

            if (out_valid !== 1'b1) begin
                receive_failed = 1'b1;
                $display("       Timed out waiting for out_valid.");
            end else begin
                if (result !== expected) begin
                    receive_failed = 1'b1;
                    $display("       Expected result %0d, got %0d.", expected, result);
                end

                @(posedge clk);
                #1;

                if (output_handshakes != (handshakes_before + 1)) begin
                    receive_failed = 1'b1;
                    $display("       Output was not consumed on its handshake edge.");
                end
            end

            consume_edge = last_output_edge;
        end
    endtask

    task automatic test_single_vector(
        input string test_name,
        input logic [VECTOR_WIDTH-1:0] a,
        input logic [VECTOR_WIDTH-1:0] b,
        input logic [RESULT_WIDTH-1:0] expected,
        input bit record_timing
    );
        bit test_failed;
        bit send_failed;
        bit receive_failed;
        int unsigned accept_edge;
        int unsigned available_edge;
        int unsigned consume_edge;

        begin
            test_failed = 1'b0;
            reset_dut();

            send_one(a, b, accept_edge, send_failed);
            expect_one(expected, available_edge, consume_edge, receive_failed);

            test_failed = send_failed || receive_failed;

            if (golden_dot(a, b) !== expected) begin
                test_failed = 1'b1;
                $display("       Testbench expected value is inconsistent.");
            end

            if (record_timing) begin
                timing_accept_edge    = accept_edge;
                timing_available_edge = available_edge;
                timing_consume_edge   = consume_edge;

                if ((available_edge - accept_edge) != 2) begin
                    test_failed = 1'b1;
                    $display("       Expected output availability two rising edges later; got %0d.",
                             available_edge - accept_edge);
                end

                if ((consume_edge - accept_edge) != 3) begin
                    test_failed = 1'b1;
                    $display("       Expected ready output consumption three rising edges later; got %0d.",
                             consume_edge - accept_edge);
                end
            end

            report_test(test_name, test_failed);
        end
    endtask

    task automatic test_back_to_back;
        bit test_failed;
        int unsigned first_input_count;
        int unsigned first_output_count;
        int unsigned accept_edges [0:2];
        int unsigned i;
        logic [RESULT_WIDTH-1:0] expected;

        begin
            test_failed       = 1'b0;
            reset_dut();
            first_input_count = input_handshakes;
            first_output_count = output_handshakes;

            @(negedge clk);
            in_valid = 1'b1;

            for (i = 0; i < 3; i = i + 1) begin
                case (i)
                    0: begin vec_a = 32'h0403_0201; vec_b = 32'h0807_0605; end
                    1: begin vec_a = 32'h0101_0101; vec_b = 32'h0202_0202; end
                    default: begin vec_a = 32'h0400_0201; vec_b = 32'h0305_0007; end
                endcase

                if (in_ready !== 1'b1) begin
                    test_failed = 1'b1;
                    $display("       in_ready was low for back-to-back input %0d.", i);
                end

                @(posedge clk);
                #1;
                accept_edges[i] = last_input_edge;
                @(negedge clk);
            end

            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;

            if ((input_handshakes - first_input_count) != 3) begin
                test_failed = 1'b1;
                $display("       Did not accept exactly three back-to-back inputs.");
            end

            if (((accept_edges[1] - accept_edges[0]) != 1)
                || ((accept_edges[2] - accept_edges[1]) != 1)) begin
                test_failed = 1'b1;
                $display("       Input handshakes were not on consecutive edges.");
            end

            for (i = 0; i < 3; i = i + 1) begin
                while (out_valid !== 1'b1) @(negedge clk);

                case (i)
                    0: expected = 32'd70;
                    1: expected = 32'd8;
                    default: expected = 32'd19;
                endcase

                back_to_back_available_edges[i] = cycle_count;

                if (result !== expected) begin
                    test_failed = 1'b1;
                    $display("       Back-to-back output %0d: expected %0d, got %0d.",
                             i, expected, result);
                end

                @(posedge clk);
                #1;
                @(negedge clk);
            end

            if ((output_handshakes - first_output_count) != 3) begin
                test_failed = 1'b1;
                $display("       Did not consume exactly three back-to-back outputs.");
            end

            if (((back_to_back_available_edges[1] - back_to_back_available_edges[0]) != 1)
                || ((back_to_back_available_edges[2] - back_to_back_available_edges[1]) != 1)) begin
                test_failed = 1'b1;
                $display("       Back-to-back outputs were not available on consecutive edges.");
            end

            if (out_valid !== 1'b0) begin
                test_failed = 1'b1;
                $display("       Unexpected extra output followed the three transactions.");
            end

            report_test("back-to-back ordering and II=1", test_failed);
        end
    endtask

    task automatic test_input_bubble;
        bit test_failed;
        int unsigned first_input_count;
        int unsigned first_output_count;

        begin
            test_failed       = 1'b0;
            reset_dut();
            first_input_count  = input_handshakes;
            first_output_count = output_handshakes;

            @(negedge clk);
            vec_a    = 32'h0403_0201;
            vec_b    = 32'h0807_0605;
            in_valid = 1'b1;
            @(posedge clk);
            #1;

            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;
            @(posedge clk);
            #1;

            @(negedge clk);
            vec_a    = 32'h0101_0101;
            vec_b    = 32'h0202_0202;
            in_valid = 1'b1;
            @(posedge clk);
            #1;

            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;

            if ((out_valid !== 1'b1) || (result !== 32'd70)) begin
                test_failed = 1'b1;
                $display("       First transaction did not emerge before the bubble.");
            end

            @(posedge clk);
            #1;
            @(negedge clk);

            if (out_valid !== 1'b0) begin
                test_failed = 1'b1;
                $display("       Input bubble generated a fake output transaction.");
            end

            @(posedge clk);
            #1;
            @(negedge clk);

            if ((out_valid !== 1'b1) || (result !== 32'd8)) begin
                test_failed = 1'b1;
                $display("       Second transaction did not follow the output bubble.");
            end

            @(posedge clk);
            #1;
            @(negedge clk);

            if (((input_handshakes - first_input_count) != 2)
                || ((output_handshakes - first_output_count) != 2)
                || (out_valid !== 1'b0)) begin
                test_failed = 1'b1;
                $display("       Bubble test handshake totals or final state were incorrect.");
            end

            report_test("input bubble propagation", test_failed);
        end
    endtask

    task automatic test_output_stall;
        bit test_failed;
        int unsigned first_input_count;
        int unsigned first_output_count;
        int unsigned i;
        logic [RESULT_WIDTH-1:0] held_result;
        logic [RESULT_WIDTH-1:0] expected;

        begin
            test_failed        = 1'b0;
            reset_dut();
            out_ready          = 1'b0;
            first_input_count  = input_handshakes;
            first_output_count = output_handshakes;

            @(negedge clk);
            in_valid = 1'b1;

            for (i = 0; i < 3; i = i + 1) begin
                case (i)
                    0: begin vec_a = 32'h0403_0201; vec_b = 32'h0807_0605; end
                    1: begin vec_a = 32'h0101_0101; vec_b = 32'h0202_0202; end
                    default: begin vec_a = 32'h0400_0201; vec_b = 32'h0305_0007; end
                endcase

                @(posedge clk);
                #1;
                @(negedge clk);
            end

            // A fourth request is held until the full pipeline can move again.
            vec_a    = 32'h0202_0202;
            vec_b    = 32'h0303_0303;
            in_valid = 1'b1;
            held_result = result;

            if ((out_valid !== 1'b1) || (held_result !== 32'd70)) begin
                test_failed = 1'b1;
                $display("       Expected the first real result to be stalled.");
            end

            for (i = 0; i < 3; i = i + 1) begin
                if ((out_valid !== 1'b1) || (result !== held_result)) begin
                    test_failed = 1'b1;
                    $display("       Output changed during explicit stall cycle %0d.", i);
                end

                if (in_ready !== 1'b0) begin
                    test_failed = 1'b1;
                    $display("       Full pipeline did not backpressure input on stall cycle %0d.", i);
                end

                @(posedge clk);
                #1;
                @(negedge clk);
            end

            if ((input_handshakes - first_input_count) != 3) begin
                test_failed = 1'b1;
                $display("       Blocked fourth request was accepted too early.");
            end

            out_ready = 1'b1;
            @(posedge clk);
            #1;

            if (((input_handshakes - first_input_count) != 4)
                || ((output_handshakes - first_output_count) != 1)) begin
                test_failed = 1'b1;
                $display("       Release edge did not consume output and accept replacement input.");
            end

            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;

            for (i = 0; i < 3; i = i + 1) begin
                case (i)
                    0: expected = 32'd8;
                    1: expected = 32'd19;
                    default: expected = 32'd24;
                endcase

                if ((out_valid !== 1'b1) || (result !== expected)) begin
                    test_failed = 1'b1;
                    $display("       Post-stall output %0d: expected %0d, got %0d.",
                             i, expected, result);
                end

                @(posedge clk);
                #1;
                @(negedge clk);
            end

            if (((output_handshakes - first_output_count) != 4)
                || (out_valid !== 1'b0)) begin
                test_failed = 1'b1;
                $display("       Post-stall transaction count or final state was incorrect.");
            end

            report_test("valid output stall and backpressure", test_failed);
        end
    endtask

    task automatic test_reset_and_recovery;
        bit test_failed;
        bit send_failed;
        bit receive_failed;
        int unsigned unused_accept_edge;
        int unsigned unused_available_edge;
        int unsigned unused_consume_edge;
        int unsigned first_output_count;

        begin
            test_failed = 1'b0;
            reset_dut();

            if ((out_valid !== 1'b0) || (in_ready !== 1'b1)
                || (dut.stage1_valid_q !== 1'b0)
                || (dut.stage2_valid_q !== 1'b0)
                || (dut.stage3_valid_q !== 1'b0)) begin
                test_failed = 1'b1;
                $display("       Pipeline was not logically empty after reset.");
            end

            send_one(32'hFFFF_FFFF, 32'hFFFF_FFFF,
                     unused_accept_edge, send_failed);
            test_failed = test_failed || send_failed;

            if (dut.stage1_valid_q !== 1'b1) begin
                test_failed = 1'b1;
                $display("       No transaction was in flight before active reset.");
            end

            @(negedge clk);
            rst_n = 1'b0;
            #1;

            if ((out_valid !== 1'b0)
                || (dut.stage1_valid_q !== 1'b0)
                || (dut.stage2_valid_q !== 1'b0)
                || (dut.stage3_valid_q !== 1'b0)) begin
                test_failed = 1'b1;
                $display("       Active-low reset did not discard in-flight state.");
            end

            repeat (2) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
            first_output_count = output_handshakes;

            send_one(32'h0403_0201, 32'h0807_0605,
                     unused_accept_edge, send_failed);
            expect_one(32'd70, unused_available_edge, unused_consume_edge,
                       receive_failed);
            test_failed = test_failed || send_failed || receive_failed;

            repeat (3) begin
                @(posedge clk);
                #1;
            end

            if (((output_handshakes - first_output_count) != 1)
                || (out_valid !== 1'b0)) begin
                test_failed = 1'b1;
                $display("       A stale pre-reset transaction appeared after recovery.");
            end

            report_test("reset empty, in-flight discard, recovery", test_failed);
        end
    endtask

    initial begin
        $dumpfile("sim/waveforms/dot_product_pipeline_tb.vcd");
        $dumpvars(0, dot_product_pipeline_tb);

        rst_n              = 1'b0;
        in_valid           = 1'b0;
        vec_a              = '0;
        vec_b              = '0;
        out_ready          = 1'b0;
        tests_run          = 0;
        failures           = 0;
        protocol_failures  = 0;
        cycle_count        = 0;
        input_handshakes   = 0;
        output_handshakes  = 0;
        last_input_edge    = 0;
        last_output_edge   = 0;
        timing_accept_edge = 0;
        timing_available_edge = 0;
        timing_consume_edge = 0;

        test_single_vector("simple dot product", 32'h0403_0201,
                           32'h0807_0605, 32'd70, 1'b1);
        test_single_vector("zero vector", 32'h0000_0000,
                           32'h0807_0605, 32'd0, 1'b0);
        test_single_vector("maximum unsigned values", 32'hFFFF_FFFF,
                           32'hFFFF_FFFF, 32'd260100, 1'b0);
        test_back_to_back();
        test_input_bubble();
        test_output_stall();
        test_reset_and_recovery();

        $display("");
        $display("============================================");
        $display("Pipelined Dot Product Day 1 Test Summary");
        $display("============================================");
        $display("Tests run          : %0d", tests_run);
        $display("Test failures      : %0d", failures);
        $display("Protocol failures  : %0d", protocol_failures);
        $display("Simple input edge  : %0d", timing_accept_edge);
        $display("Output valid edge  : %0d", timing_available_edge);
        $display("Output consume edge: %0d", timing_consume_edge);
        $display("Back-to-back output availability edges: %0d, %0d, %0d",
                 back_to_back_available_edges[0],
                 back_to_back_available_edges[1],
                 back_to_back_available_edges[2]);
        $display("============================================");

        if ((failures == 0) && (protocol_failures == 0)) begin
            $display("ALL PIPELINED ACCELERATOR TESTS PASSED");
            $finish;
        end else begin
            $display("PIPELINED ACCELERATOR TESTS FAILED");
            $fatal(1);
        end
    end

endmodule
