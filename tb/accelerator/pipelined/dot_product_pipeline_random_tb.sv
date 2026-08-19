`timescale 1ns/1ps

module dot_product_pipeline_random_tb;

    localparam int ELEM_WIDTH        = 8;
    localparam int NUM_ELEMS         = 4;
    localparam int RESULT_WIDTH      = 32;
    localparam int VECTOR_WIDTH      = ELEM_WIDTH * NUM_ELEMS;
    localparam int PIPELINE_CAPACITY = 3;
    localparam int DEFAULT_SEED      = 12345;
    localparam int DEFAULT_TXNS      = 3000;

    localparam int PHASE_DIRECTED = 0;
    localparam int PHASE_RANDOM   = 1;
    localparam int PHASE_DRAIN    = 2;

    typedef struct packed {
        logic [63:0]             id;
        logic [VECTOR_WIDTH-1:0] vec_a;
        logic [VECTOR_WIDTH-1:0] vec_b;
        logic [RESULT_WIDTH-1:0] expected;
    } expected_txn_t;

    logic                    clk;
    logic                    rst_n;
    logic                    in_valid;
    logic                    in_ready;
    logic [VECTOR_WIDTH-1:0] vec_a;
    logic [VECTOR_WIDTH-1:0] vec_b;
    logic                    out_valid;
    logic                    out_ready;
    logic [RESULT_WIDTH-1:0] result;

    // Icarus cannot elaborate a queue of structs, so the scoreboard uses an
    // explicit three-entry FIFO ring. Its depth exactly matches the DUT.
    expected_txn_t expected_queue [0:PIPELINE_CAPACITY-1];
    expected_txn_t expected_item;
    int unsigned queue_head;
    int unsigned queue_tail;
    int unsigned queue_depth;

    int unsigned seed;
    int unsigned rng_state;
    longint unsigned transaction_target;
    longint unsigned watchdog_limit;
    int unsigned phase;

    longint unsigned cycle_count;
    longint unsigned next_transaction_id;
    longint unsigned accepted_inputs;
    longint unsigned random_accepted_inputs;
    longint unsigned consumed_outputs;
    longint unsigned results_checked;
    longint unsigned discarded_by_reset;
    longint unsigned input_bubble_cycles;
    longint unsigned input_backpressure_cycles;
    longint unsigned output_not_ready_cycles;
    longint unsigned output_stalled_valid_cycles;
    longint unsigned reset_events;
    longint unsigned post_reset_results_checked;
    longint unsigned simultaneous_handshakes;
    longint unsigned stall_bursts;
    longint unsigned long_stall_bursts;
    int unsigned     maximum_queue_depth;
    int unsigned     current_output_stall_run;
    int unsigned     maximum_output_stall_run;

    int unsigned protocol_failures;
    int unsigned unexpected_outputs;
    int unsigned data_mismatches;
    int unsigned timeout_failures;

    bit saw_input_bubble;
    bit saw_back_to_back_input;
    bit saw_output_stall;
    bit saw_long_output_stall;
    bit saw_full_pipeline_backpressure;
    bit saw_reset_depth_one;
    bit saw_reset_depth_two;
    bit saw_reset_depth_three;
    bit saw_reset_with_inflight;
    bit saw_post_reset_output;
    bit saw_simultaneous_handshake;
    bit reset_sampled_active;
    bit awaiting_post_reset_output;
    bit previous_input_handshake;
    bit previous_input_stalled;
    bit previous_output_stalled;
    bit test_done;

    logic [VECTOR_WIDTH-1:0] previous_vec_a;
    logic [VECTOR_WIDTH-1:0] previous_vec_b;
    logic [RESULT_WIDTH-1:0] previous_result;

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

    initial clk = 1'b0;
    always #5 clk <= ~clk;

    function automatic logic [RESULT_WIDTH-1:0] golden_dot(
        input logic [VECTOR_WIDTH-1:0] a,
        input logic [VECTOR_WIDTH-1:0] b
    );
        logic [RESULT_WIDTH-1:0] accumulator;
        logic [ELEM_WIDTH-1:0]   a_element;
        logic [ELEM_WIDTH-1:0]   b_element;
        int unsigned             index;
        begin
            accumulator = '0;
            for (index = 0; index < NUM_ELEMS; index = index + 1) begin
                a_element = a[index*ELEM_WIDTH +: ELEM_WIDTH];
                b_element = b[index*ELEM_WIDTH +: ELEM_WIDTH];
                accumulator = accumulator
                    + (RESULT_WIDTH'(a_element) * RESULT_WIDTH'(b_element));
            end
            golden_dot = accumulator;
        end
    endfunction

    // One explicitly owned PRNG stream makes a seed reproduce the same traffic.
    function automatic int unsigned next_random;
        int unsigned value;
        begin
            value = rng_state;
            value = value ^ (value << 13);
            value = value ^ (value >> 17);
            value = value ^ (value << 5);
            rng_state = value;
            next_random = value;
        end
    endfunction

    function automatic int unsigned random_below(input int unsigned limit);
        begin
            random_below = next_random() % limit;
        end
    endfunction

    function automatic logic [VECTOR_WIDTH-1:0] random_vector;
        begin
            random_vector = VECTOR_WIDTH'(next_random());
        end
    endfunction

    task automatic show_summary;
        begin
            $display("");
            $display("========================================================");
            $display("Pipelined Dot Product Day 2 Random Test Summary");
            $display("========================================================");
            $display("Seed                              : %0d", seed);
            $display("Cycles executed                   : %0d", cycle_count);
            $display("Configured random transaction target: %0d", transaction_target);
            $display("Random input transactions accepted: %0d", random_accepted_inputs);
            $display("All input transactions accepted   : %0d", accepted_inputs);
            $display("Output transactions consumed      : %0d", consumed_outputs);
            $display("Results checked                    : %0d", results_checked);
            $display("Transactions discarded by reset   : %0d", discarded_by_reset);
            $display("Input bubble cycles                : %0d", input_bubble_cycles);
            $display("Input backpressure cycles          : %0d", input_backpressure_cycles);
            $display("Output not-ready cycles            : %0d", output_not_ready_cycles);
            $display("Output stalled-valid cycles        : %0d", output_stalled_valid_cycles);
            $display("Stall bursts / long stall bursts   : %0d / %0d", stall_bursts,
                     long_stall_bursts);
            $display("Maximum consecutive stalled-valid cycles: %0d",
                     maximum_output_stall_run);
            $display("Reset events                       : %0d", reset_events);
            $display("Post-reset results checked         : %0d", post_reset_results_checked);
            $display("Simultaneous input/output handshakes: %0d", simultaneous_handshakes);
            $display("Maximum scoreboard queue depth     : %0d", maximum_queue_depth);
            $display("Full-pipeline backpressure observed: %s",
                     saw_full_pipeline_backpressure ? "YES" : "NO");
            $display("Protocol/checker failures          : %0d", protocol_failures);
            $display("Unexpected outputs                 : %0d", unexpected_outputs);
            $display("Data mismatches                    : %0d", data_mismatches);
            $display("Timeout failures                   : %0d", timeout_failures);
            $display("========================================================");
        end
    endtask

    task automatic pulse_reset;
        begin
            // Called on a falling edge. An unaccepted source request is dropped.
            rst_n     = 1'b0;
            in_valid  = 1'b0;
            vec_a     = '0;
            vec_b     = '0;
            out_ready = 1'b0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst_n = 1'b1;
        end
    endtask

    task automatic offer_one(
        input logic [VECTOR_WIDTH-1:0] offered_a,
        input logic [VECTOR_WIDTH-1:0] offered_b
    );
        longint unsigned accepted_before;
        bit accepted;
        begin
            accepted_before = accepted_inputs;
            accepted = 1'b0;
            @(negedge clk);
            in_valid = 1'b1;
            vec_a    = offered_a;
            vec_b    = offered_b;
            while (!accepted) begin
                @(posedge clk);
                #1;
                accepted = (accepted_inputs == (accepted_before + 1));
            end
            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;
        end
    endtask

    task automatic wait_until_drained(input int unsigned limit);
        int unsigned waited;
        begin
            waited = 0;
            while (((queue_depth != 0) || out_valid) && (waited < limit)) begin
                @(negedge clk);
                waited = waited + 1;
            end
            if ((queue_depth != 0) || out_valid) begin
                protocol_failures = protocol_failures + 1;
                $error("Drain failed: cycle=%0d queue_depth=%0d out_valid=%b",
                       cycle_count, queue_depth, out_valid);
            end
        end
    endtask

    task automatic run_full_pipeline_stall;
        int unsigned index;
        longint unsigned accepted_before;
        logic [VECTOR_WIDTH-1:0] a_values [0:3];
        logic [VECTOR_WIDTH-1:0] b_values [0:3];
        begin
            a_values[0] = 32'h0403_0201; b_values[0] = 32'h0807_0605;
            a_values[1] = 32'h0101_0101; b_values[1] = 32'h0202_0202;
            a_values[2] = 32'h0400_0201; b_values[2] = 32'h0305_0007;
            a_values[3] = 32'h0202_0202; b_values[3] = 32'h0303_0303;

            @(negedge clk);
            out_ready = 1'b0;
            in_valid  = 1'b1;
            vec_a     = a_values[0];
            vec_b     = b_values[0];

            for (index = 0; index < 3; index = index + 1) begin
                accepted_before = accepted_inputs;
                @(posedge clk);
                #1;
                if (accepted_inputs != (accepted_before + 1)) begin
                    protocol_failures = protocol_failures + 1;
                    $error("Directed full-pipeline input %0d was not accepted", index);
                end
                @(negedge clk);
                vec_a = a_values[index + 1];
                vec_b = b_values[index + 1];
            end

            repeat (12) @(posedge clk);
            #1;
            if ((queue_depth != PIPELINE_CAPACITY)
                || (out_valid !== 1'b1) || (in_ready !== 1'b0)) begin
                protocol_failures = protocol_failures + 1;
                $error("Guaranteed full-pipeline stall was not established: depth=%0d out_valid=%b in_ready=%b",
                       queue_depth, out_valid, in_ready);
            end

            @(negedge clk);
            out_ready = 1'b1;
            accepted_before = accepted_inputs;
            @(posedge clk);
            #1;
            if (accepted_inputs != (accepted_before + 1)) begin
                protocol_failures = protocol_failures + 1;
                $error("Held fourth request was not accepted on stall release");
            end
            @(negedge clk);
            in_valid = 1'b0;
            vec_a    = '0;
            vec_b    = '0;
            wait_until_drained(20);
        end
    endtask

    task automatic reset_with_depth(input int unsigned requested_depth);
        int unsigned index;
        begin
            out_ready = 1'b0;
            for (index = 0; index < requested_depth; index = index + 1) begin
                offer_one(random_vector(), random_vector());
            end
            if (queue_depth != requested_depth) begin
                protocol_failures = protocol_failures + 1;
                $error("Reset-depth setup expected %0d outstanding, observed %0d",
                       requested_depth, queue_depth);
            end
            // offer_one returns on a falling edge.
            rst_n     = 1'b0;
            in_valid  = 1'b0;
            vec_a     = '0;
            vec_b     = '0;
            repeat (2) @(posedge clk);
            @(negedge clk);
            rst_n     = 1'b1;
            out_ready = 1'b1;

            // Every directed reset is followed by a checked recovery transaction.
            offer_one(random_vector(), random_vector());
            wait_until_drained(20);
        end
    endtask

    // Scoreboard and protocol checkers sample only at rising edges. Stimulus owns
    // DUT inputs and changes them only at falling edges, avoiding scheduling races.
    // Blocking assignments are intentional in this transaction model: output
    // removal must complete before same-edge input insertion and final depth use.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk or negedge rst_n) begin
        if (clk === 1'b1) begin
            cycle_count = cycle_count + 1;
        end

        if (!rst_n) begin
            if (!reset_sampled_active) begin
                reset_events = reset_events + 1;
                if (queue_depth != 0) begin
                    saw_reset_with_inflight = 1'b1;
                    case (queue_depth)
                        1: saw_reset_depth_one   = 1'b1;
                        2: saw_reset_depth_two   = 1'b1;
                        3: saw_reset_depth_three = 1'b1;
                        default: begin
                            protocol_failures = protocol_failures + 1;
                            $error("Reset observed illegal queue depth %0d",
                                   queue_depth);
                        end
                    endcase
                    discarded_by_reset = discarded_by_reset + 64'(queue_depth);
                    queue_head  = 0;
                    queue_tail  = 0;
                    queue_depth = 0;
                end
                reset_sampled_active = 1'b1;
            end

            // On an asynchronous reset edge, allow DUT nonblocking reset updates
            // to settle; active-reset clock edges must observe out_valid cleared.
            if (clk && (out_valid !== 1'b0)) begin
                protocol_failures = protocol_failures + 1;
                $error("out_valid was not clear during active reset at cycle %0d", cycle_count);
            end
            previous_input_stalled  = 1'b0;
            previous_output_stalled = 1'b0;
            previous_input_handshake = 1'b0;
        end else begin
            if (reset_sampled_active) begin
                reset_sampled_active = 1'b0;
                awaiting_post_reset_output = 1'b1;
            end

            if (previous_input_stalled
                && ((in_valid !== 1'b1) || (vec_a !== previous_vec_a)
                    || (vec_b !== previous_vec_b))) begin
                protocol_failures = protocol_failures + 1;
                $error("Source changed while blocked: seed=%0d cycle=%0d old_a=%h new_a=%h old_b=%h new_b=%h",
                       seed, cycle_count, previous_vec_a, vec_a, previous_vec_b, vec_b);
            end

            if (previous_output_stalled
                && ((out_valid !== 1'b1) || (result !== previous_result))) begin
                protocol_failures = protocol_failures + 1;
                $error("Output changed while stalled: seed=%0d cycle=%0d old=%h new=%h out_valid=%b",
                       seed, cycle_count, previous_result, result, out_valid);
            end

            if (!in_valid) begin
                input_bubble_cycles = input_bubble_cycles + 1;
                saw_input_bubble = 1'b1;
            end
            if (in_valid && !in_ready) begin
                input_backpressure_cycles = input_backpressure_cycles + 1;
            end
            if (!out_ready) begin
                output_not_ready_cycles = output_not_ready_cycles + 1;
            end
            if (out_valid && !out_ready) begin
                output_stalled_valid_cycles = output_stalled_valid_cycles + 1;
                saw_output_stall = 1'b1;
                current_output_stall_run = current_output_stall_run + 1;
                if (current_output_stall_run > maximum_output_stall_run) begin
                    maximum_output_stall_run = current_output_stall_run;
                end
                if (current_output_stall_run >= 10) begin
                    saw_long_output_stall = 1'b1;
                end
            end else begin
                current_output_stall_run = 0;
            end

            if ((queue_depth == PIPELINE_CAPACITY)
                && out_valid && !out_ready && !in_ready) begin
                saw_full_pipeline_backpressure = 1'b1;
            end

            if (out_valid && (queue_depth == 0)) begin
                unexpected_outputs = unexpected_outputs + 1;
                $error("Unexpected out_valid with empty scoreboard: seed=%0d cycle=%0d result=%h ready=%b",
                       seed, cycle_count, result, out_ready);
            end

            // Pop/check first so a same-edge input can never satisfy this output.
            if (out_valid && out_ready) begin
                consumed_outputs = consumed_outputs + 1;
                if (queue_depth == 0) begin
                    // The unexpected out_valid check above already recorded failure.
                end else begin
                    expected_item = expected_queue[queue_head];
                    queue_head = (queue_head + 1) % PIPELINE_CAPACITY;
                    queue_depth = queue_depth - 1;
                    results_checked = results_checked + 1;
                    if (result !== expected_item.expected) begin
                        data_mismatches = data_mismatches + 1;
                        $error("Mismatch: seed=%0d cycle=%0d id=%0d a=%h b=%h expected=%0d actual=%0d depth_after_pop=%0d accepted=%0d checked=%0d",
                               seed, cycle_count, expected_item.id,
                               expected_item.vec_a, expected_item.vec_b,
                               expected_item.expected, result, queue_depth,
                               accepted_inputs, results_checked);
                    end
                    if (awaiting_post_reset_output) begin
                        awaiting_post_reset_output = 1'b0;
                        saw_post_reset_output = 1'b1;
                        post_reset_results_checked = post_reset_results_checked + 1;
                    end
                end
            end

            if (in_valid && in_ready) begin
                expected_item.id       = next_transaction_id;
                expected_item.vec_a    = vec_a;
                expected_item.vec_b    = vec_b;
                expected_item.expected = golden_dot(vec_a, vec_b);
                expected_queue[queue_tail] = expected_item;
                queue_tail = (queue_tail + 1) % PIPELINE_CAPACITY;
                queue_depth = queue_depth + 1;
                next_transaction_id = next_transaction_id + 1;
                accepted_inputs = accepted_inputs + 1;
                if (phase == PHASE_RANDOM) begin
                    random_accepted_inputs = random_accepted_inputs + 1;
                end
                if (previous_input_handshake) begin
                    saw_back_to_back_input = 1'b1;
                end
            end

            if ((in_valid && in_ready) && (out_valid && out_ready)) begin
                simultaneous_handshakes = simultaneous_handshakes + 1;
                saw_simultaneous_handshake = 1'b1;
            end

            if (queue_depth > maximum_queue_depth) begin
                maximum_queue_depth = queue_depth;
            end
            if (queue_depth > PIPELINE_CAPACITY) begin
                protocol_failures = protocol_failures + 1;
                $error("Scoreboard depth exceeded pipeline capacity: cycle=%0d depth=%0d",
                       cycle_count, queue_depth);
            end

            previous_input_handshake = in_valid && in_ready;
            previous_input_stalled   = in_valid && !in_ready;
            previous_output_stalled  = out_valid && !out_ready;
            previous_vec_a           = vec_a;
            previous_vec_b           = vec_b;
            previous_result          = result;
        end

        if (!test_done && (cycle_count > watchdog_limit)) begin
            timeout_failures = timeout_failures + 1;
            $display("FAIL - timeout/deadlock: seed=%0d cycle=%0d accepted=%0d checked=%0d queue_depth=%0d",
                     seed, cycle_count, accepted_inputs, results_checked,
                     queue_depth);
            show_summary();
            $fatal(1);
        end
    end
    /* verilator lint_on BLKSEQ */

    initial begin : stimulus
        int unsigned plusarg_value;
        int unsigned stall_remaining;
        int unsigned choice;
        int unsigned random_reset_index;
        int unsigned drain_wait;
        bit final_failed;

        rst_n              = 1'b0;
        in_valid           = 1'b0;
        vec_a              = '0;
        vec_b              = '0;
        out_ready          = 1'b0;
        seed               = DEFAULT_SEED;
        transaction_target = 64'(DEFAULT_TXNS);
        phase              = PHASE_DIRECTED;
        test_done          = 1'b0;
        queue_head         = 0;
        queue_tail         = 0;
        queue_depth        = 0;
        cycle_count        = 0;
        next_transaction_id = 0;
        accepted_inputs    = 0;
        random_accepted_inputs = 0;
        consumed_outputs   = 0;
        results_checked    = 0;
        discarded_by_reset = 0;
        input_bubble_cycles = 0;
        input_backpressure_cycles = 0;
        output_not_ready_cycles = 0;
        output_stalled_valid_cycles = 0;
        reset_events = 0;
        post_reset_results_checked = 0;
        simultaneous_handshakes = 0;
        stall_bursts = 0;
        long_stall_bursts = 0;
        maximum_queue_depth = 0;
        current_output_stall_run = 0;
        maximum_output_stall_run = 0;
        protocol_failures = 0;
        unexpected_outputs = 0;
        data_mismatches = 0;
        timeout_failures = 0;
        saw_input_bubble = 1'b0;
        saw_back_to_back_input = 1'b0;
        saw_output_stall = 1'b0;
        saw_long_output_stall = 1'b0;
        saw_full_pipeline_backpressure = 1'b0;
        saw_reset_depth_one = 1'b0;
        saw_reset_depth_two = 1'b0;
        saw_reset_depth_three = 1'b0;
        saw_reset_with_inflight = 1'b0;
        saw_post_reset_output = 1'b0;
        saw_simultaneous_handshake = 1'b0;
        reset_sampled_active = 1'b0;
        awaiting_post_reset_output = 1'b0;
        previous_input_handshake = 1'b0;
        previous_input_stalled = 1'b0;
        previous_output_stalled = 1'b0;
        previous_vec_a = '0;
        previous_vec_b = '0;
        previous_result = '0;

        if ($value$plusargs("SEED=%d", plusarg_value)) begin
            seed = plusarg_value;
        end
        if ($value$plusargs("NUM_TXNS=%d", plusarg_value)) begin
            transaction_target = 64'(plusarg_value);
        end
        if (transaction_target < 1000) begin
            $fatal(1, "NUM_TXNS must be at least 1000 (requested %0d)", transaction_target);
        end
        rng_state = (seed == 0) ? 32'h1 : seed;
        watchdog_limit = (transaction_target * 30) + 5000;

        $display("Random seed: %0d", seed);
        $display("Random accepted-transaction target: %0d", transaction_target);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n     = 1'b1;
        out_ready = 1'b1;

        run_full_pipeline_stall();
        reset_with_depth(1);
        reset_with_depth(2);
        reset_with_depth(3);

        phase = PHASE_RANDOM;
        stall_remaining = 0;
        random_reset_index = 0;

        while (random_accepted_inputs < transaction_target) begin
            @(negedge clk);

            // Three reproducible in-flight resets are distributed across the run.
            if ((random_reset_index < 3)
                && (random_accepted_inputs >= ((64'(random_reset_index) + 64'd1)
                                               * (transaction_target / 4)))
                && (queue_depth != 0)) begin
                pulse_reset();
                random_reset_index = random_reset_index + 1;
                stall_remaining = 0;
            end else begin
                if (stall_remaining != 0) begin
                    out_ready = 1'b0;
                    stall_remaining = stall_remaining - 1;
                end else begin
                    choice = random_below(100);
                    if (choice < 3) begin
                        stall_remaining = 1;
                    end else if (choice < 6) begin
                        stall_remaining = 2 + random_below(3);
                    end else if (choice < 8) begin
                        stall_remaining = 5 + random_below(6);
                    end else if (choice < 9) begin
                        stall_remaining = 11 + random_below(20);
                        long_stall_bursts = long_stall_bursts + 1;
                    end

                    if (stall_remaining != 0) begin
                        out_ready = 1'b0;
                        stall_bursts = stall_bursts + 1;
                        stall_remaining = stall_remaining - 1;
                    end else begin
                        out_ready = (random_below(100) < 72);
                    end
                end

                // A blocked offer owns its data until a real input handshake.
                // Replace an offer only if it was absent or the monitor proved
                // that the previous rising edge accepted it.
                if (!in_valid || previous_input_handshake) begin
                    if (random_accepted_inputs < transaction_target
                        && (random_below(100) < 80)) begin
                        in_valid = 1'b1;
                        vec_a    = random_vector();
                        vec_b    = random_vector();
                    end else begin
                        in_valid = 1'b0;
                        vec_a    = '0;
                        vec_b    = '0;
                    end
                end
            end
        end

        phase = PHASE_DRAIN;
        @(negedge clk);
        in_valid  = 1'b0;
        vec_a     = '0;
        vec_b     = '0;
        out_ready = 1'b1;

        drain_wait = 0;
        while (((queue_depth != 0) || out_valid) && (drain_wait < 100)) begin
            @(negedge clk);
            drain_wait = drain_wait + 1;
        end
        repeat (3) @(posedge clk);
        #1;

        final_failed = 1'b0;
        if (random_accepted_inputs != transaction_target) begin
            final_failed = 1'b1;
            $error("Accepted random target was not reached exactly");
        end
        if (random_reset_index != 3) begin
            final_failed = 1'b1;
            $error("Planned randomized resets incomplete: expected=3 observed=%0d",
                   random_reset_index);
        end
        if (post_reset_results_checked != reset_events) begin
            final_failed = 1'b1;
            $error("Post-reset recovery count mismatch: reset_events=%0d post_reset_results_checked=%0d",
                   reset_events, post_reset_results_checked);
        end
        if (queue_depth != 0) begin
            final_failed = 1'b1;
            $error("Scoreboard was not empty after drain: depth=%0d", queue_depth);
        end
        if (out_valid !== 1'b0) begin
            final_failed = 1'b1;
            $error("out_valid remained asserted after final drain");
        end
        if (accepted_inputs != (consumed_outputs + discarded_by_reset)) begin
            final_failed = 1'b1;
            $error("Accounting failure: accepted=%0d consumed=%0d discarded=%0d",
                   accepted_inputs, consumed_outputs, discarded_by_reset);
        end
        if (results_checked != consumed_outputs) begin
            final_failed = 1'b1;
            $error("Not every consumed output was checked");
        end
        if (maximum_queue_depth != PIPELINE_CAPACITY) begin
            final_failed = 1'b1;
            $error("Full scoreboard depth was not reached");
        end
        if (!saw_input_bubble || !saw_back_to_back_input || !saw_output_stall
            || !saw_long_output_stall || !saw_full_pipeline_backpressure
            || !saw_reset_depth_one || !saw_reset_depth_two || !saw_reset_depth_three
            || !saw_reset_with_inflight || !saw_post_reset_output
            || !saw_simultaneous_handshake) begin
            final_failed = 1'b1;
            $error("Required scenario missing: bubble=%b back_to_back=%b output_stall=%b long_stall=%b full=%b reset1=%b reset2=%b reset3=%b reset_inflight=%b post_reset=%b simultaneous=%b",
                   saw_input_bubble, saw_back_to_back_input, saw_output_stall,
                   saw_long_output_stall, saw_full_pipeline_backpressure,
                   saw_reset_depth_one, saw_reset_depth_two, saw_reset_depth_three,
                   saw_reset_with_inflight, saw_post_reset_output,
                   saw_simultaneous_handshake);
        end
        if ((protocol_failures != 0) || (unexpected_outputs != 0)
            || (data_mismatches != 0) || (timeout_failures != 0)) final_failed = 1'b1;

        test_done = 1'b1;
        show_summary();
        if (final_failed) begin
            $display("RANDOMIZED PIPELINED ACCELERATOR TEST FAILED");
            $fatal(1);
        end else begin
            $display("RANDOMIZED PIPELINED ACCELERATOR TEST PASSED");
            $finish;
        end
    end

endmodule
