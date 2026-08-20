`timescale 1ns/1ps

module dot_product_pipeline_perf_tb;

    localparam int ELEM_WIDTH   = 8;
    localparam int NUM_ELEMS    = 4;
    localparam int RESULT_WIDTH = 32;
    localparam int VECTOR_WIDTH = ELEM_WIDTH * NUM_ELEMS;
    localparam int NUM_TXNS     = 100;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic in_ready;
    logic [VECTOR_WIDTH-1:0] vec_a;
    logic [VECTOR_WIDTH-1:0] vec_b;
    logic out_valid;
    logic out_ready;
    logic [RESULT_WIDTH-1:0] result;

    int unsigned edge_count;
    int unsigned accepted_inputs;
    int unsigned completed_outputs;
    int unsigned accept_edges [0:NUM_TXNS-1];
    int unsigned completion_edges [0:NUM_TXNS-1];
    logic [RESULT_WIDTH-1:0] expected_results [0:NUM_TXNS-1];
    int unsigned errors;

    dot_product_pipeline #(
        .ELEM_WIDTH(ELEM_WIDTH),
        .NUM_ELEMS(NUM_ELEMS),
        .RESULT_WIDTH(RESULT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_ready(in_ready),
        .vec_a(vec_a),
        .vec_b(vec_b),
        .out_valid(out_valid),
        .out_ready(out_ready),
        .result(result)
    );

    initial clk = 1'b0;
    always #5 clk <= ~clk;

    function automatic logic [VECTOR_WIDTH-1:0] make_vec_a(input int unsigned txn);
        int elem;
        begin
            make_vec_a = '0;
            for (elem = 0; elem < NUM_ELEMS; elem = elem + 1) begin
                make_vec_a[elem*ELEM_WIDTH +: ELEM_WIDTH] =
                    ELEM_WIDTH'((txn * 17) + (elem * 29) + 3);
            end
        end
    endfunction

    function automatic logic [VECTOR_WIDTH-1:0] make_vec_b(input int unsigned txn);
        int elem;
        begin
            make_vec_b = '0;
            for (elem = 0; elem < NUM_ELEMS; elem = elem + 1) begin
                make_vec_b[elem*ELEM_WIDTH +: ELEM_WIDTH] =
                    ELEM_WIDTH'((txn * 31) + (elem * 11) + 7);
            end
        end
    endfunction

    function automatic logic [RESULT_WIDTH-1:0] golden_dot(
        input logic [VECTOR_WIDTH-1:0] a,
        input logic [VECTOR_WIDTH-1:0] b
    );
        int elem;
        logic [RESULT_WIDTH-1:0] accumulator;
        begin
            accumulator = '0;
            for (elem = 0; elem < NUM_ELEMS; elem = elem + 1) begin
                accumulator = accumulator
                    + (a[elem*ELEM_WIDTH +: ELEM_WIDTH]
                       * b[elem*ELEM_WIDTH +: ELEM_WIDTH]);
            end
            golden_dot = accumulator;
        end
    endfunction

    // Handshakes are sampled in the active region at each rising edge, before
    // DUT nonblocking assignments update the next pipeline state. Blocking
    // assignments intentionally make same-edge scoreboard ordering explicit.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk or negedge rst_n) begin
        if (clk === 1'b1) begin
            edge_count = edge_count + 1;
        end
        if ((clk === 1'b1) && rst_n) begin
            if (in_valid && in_ready) begin
                if (accepted_inputs >= NUM_TXNS) begin
                    errors = errors + 1;
                end else begin
                    accept_edges[accepted_inputs] = edge_count;
                    expected_results[accepted_inputs] = golden_dot(vec_a, vec_b);
                    accepted_inputs = accepted_inputs + 1;
                end
            end

            if (out_valid && out_ready) begin
                if (completed_outputs >= accepted_inputs) begin
                    errors = errors + 1;
                end else begin
                    completion_edges[completed_outputs] = edge_count;
                    if (result !== expected_results[completed_outputs])
                        errors = errors + 1;
                    completed_outputs = completed_outputs + 1;
                end
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    initial begin : measure_pipeline
        int txn;
        int latency_cycles;
        int minimum_ii_cycles;
        int completion_interval_cycles;
        int batch_span_cycles;

        rst_n = 1'b0;
        in_valid = 1'b0;
        vec_a = '0;
        vec_b = '0;
        out_ready = 1'b1;
        edge_count = 0;
        accepted_inputs = 0;
        completed_outputs = 0;
        errors = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        while (accepted_inputs < NUM_TXNS) begin
            @(negedge clk);
            if (accepted_inputs < NUM_TXNS) begin
                in_valid = 1'b1;
                vec_a = make_vec_a(accepted_inputs);
                vec_b = make_vec_b(accepted_inputs);
            end
        end
        in_valid = 1'b0;
        vec_a = '0;
        vec_b = '0;

        while (completed_outputs < NUM_TXNS) begin
            @(posedge clk);
            #1;
        end

        latency_cycles = completion_edges[0] - accept_edges[0];
        minimum_ii_cycles = accept_edges[1] - accept_edges[0];
        completion_interval_cycles = completion_edges[1] - completion_edges[0];
        batch_span_cycles = completion_edges[NUM_TXNS-1] - accept_edges[0];

        for (txn = 0; txn < NUM_TXNS; txn = txn + 1) begin
            if ((completion_edges[txn] - accept_edges[txn]) != latency_cycles)
                errors = errors + 1;
            if ((txn > 0)
                && ((accept_edges[txn] - accept_edges[txn-1]) != minimum_ii_cycles))
                errors = errors + 1;
            if ((txn > 0)
                && ((completion_edges[txn] - completion_edges[txn-1])
                    != completion_interval_cycles))
                errors = errors + 1;
        end

        $display("PERF architecture=pipelined transactions=%0d latency_cycles=%0d minimum_ii_cycles=%0d completion_interval_cycles=%0d throughput_numerator=1 throughput_denominator=%0d first_accept_edge=%0d last_completion_edge=%0d batch_span_cycles=%0d errors=%0d",
                 NUM_TXNS, latency_cycles, minimum_ii_cycles,
                 completion_interval_cycles, completion_interval_cycles,
                 accept_edges[0], completion_edges[NUM_TXNS-1],
                 batch_span_cycles, errors);

        if (errors != 0) $fatal(1, "pipeline performance measurement failed");
        $finish;
    end

endmodule
