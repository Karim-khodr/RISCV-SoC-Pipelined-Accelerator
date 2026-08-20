`timescale 1ns/1ps

module dot_product_seq_perf_tb;

    localparam int ELEM_WIDTH   = 8;
    localparam int NUM_ELEMS    = 4;
    localparam int RESULT_WIDTH = 32;
    localparam int VECTOR_WIDTH = ELEM_WIDTH * NUM_ELEMS;
    localparam int NUM_TXNS     = 100;

    logic clk;
    logic rst_n;
    logic start;
    logic [VECTOR_WIDTH-1:0] vec_a;
    logic [VECTOR_WIDTH-1:0] vec_b;
    logic [RESULT_WIDTH-1:0] result;
    logic busy;
    logic done;

    int unsigned edge_count;
    int unsigned accept_edges [0:NUM_TXNS-1];
    int unsigned completion_edges [0:NUM_TXNS-1];
    int unsigned errors;

    dot_product_seq #(
        .ELEM_WIDTH(ELEM_WIDTH),
        .NUM_ELEMS(NUM_ELEMS),
        .RESULT_WIDTH(RESULT_WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .vec_a(vec_a),
        .vec_b(vec_b),
        .result(result),
        .busy(busy),
        .done(done)
    );

    initial clk = 1'b0;
    always #5 clk <= ~clk;

    // Blocking update is intentional: measurements sample the settled counter
    // after each edge and the counter is testbench bookkeeping, not DUT logic.
    /* verilator lint_off BLKSEQ */
    always @(posedge clk) begin
        edge_count = edge_count + 1;
    end
    /* verilator lint_on BLKSEQ */

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

    initial begin : measure_sequential
        int txn;
        int latency_cycles;
        int minimum_ii_cycles;
        int completion_interval_cycles;
        int batch_span_cycles;
        logic [RESULT_WIDTH-1:0] expected;

        rst_n = 1'b0;
        start = 1'b0;
        vec_a = '0;
        vec_b = '0;
        edge_count = 0;
        errors = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        for (txn = 0; txn < NUM_TXNS; txn = txn + 1) begin
            @(negedge clk);
            vec_a = make_vec_a(txn);
            vec_b = make_vec_b(txn);
            expected = golden_dot(vec_a, vec_b);
            start = 1'b1;

            @(posedge clk);
            #1;
            accept_edges[txn] = edge_count;
            if ((busy !== 1'b1) || (done !== 1'b0)) errors = errors + 1;

            @(negedge clk);
            start = 1'b0;

            while (done !== 1'b1) begin
                @(posedge clk);
                #1;
            end
            completion_edges[txn] = edge_count;
            if ((result !== expected) || (busy !== 1'b0)) errors = errors + 1;
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

        $display("PERF architecture=sequential transactions=%0d latency_cycles=%0d minimum_ii_cycles=%0d completion_interval_cycles=%0d throughput_numerator=1 throughput_denominator=%0d first_accept_edge=%0d last_completion_edge=%0d batch_span_cycles=%0d errors=%0d",
                 NUM_TXNS, latency_cycles, minimum_ii_cycles,
                 completion_interval_cycles, completion_interval_cycles,
                 accept_edges[0], completion_edges[NUM_TXNS-1],
                 batch_span_cycles, errors);

        if (errors != 0) $fatal(1, "sequential performance measurement failed");
        $finish;
    end

endmodule
