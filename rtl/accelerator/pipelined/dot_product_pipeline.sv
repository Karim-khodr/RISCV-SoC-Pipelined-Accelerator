`timescale 1ns/1ps
`default_nettype none

module dot_product_pipeline #(
    parameter int ELEM_WIDTH   = 8,
    parameter int NUM_ELEMS    = 4,
    parameter int RESULT_WIDTH = 32
)(
    input  logic                              clk,
    input  logic                              rst_n,

    input  logic                              in_valid,
    output logic                              in_ready,
    input  logic [ELEM_WIDTH*NUM_ELEMS-1:0]  vec_a,
    input  logic [ELEM_WIDTH*NUM_ELEMS-1:0]  vec_b,

    output logic                              out_valid,
    input  logic                              out_ready,
    output logic [RESULT_WIDTH-1:0]           result
);

    localparam int PRODUCT_WIDTH  = 2 * ELEM_WIDTH;
    localparam int PAIR_SUM_WIDTH = PRODUCT_WIDTH + 1;
    localparam int FINAL_SUM_WIDTH = PAIR_SUM_WIDTH + 1;
    localparam int RESULT_PAD_WIDTH = RESULT_WIDTH - FINAL_SUM_WIDTH;

    logic [PRODUCT_WIDTH-1:0] stage1_product0_q;
    logic [PRODUCT_WIDTH-1:0] stage1_product1_q;
    logic [PRODUCT_WIDTH-1:0] stage1_product2_q;
    logic [PRODUCT_WIDTH-1:0] stage1_product3_q;
    logic                     stage1_valid_q;

    logic [PAIR_SUM_WIDTH-1:0] stage2_sum0_q;
    logic [PAIR_SUM_WIDTH-1:0] stage2_sum1_q;
    logic                      stage2_valid_q;

    logic [RESULT_WIDTH-1:0] stage3_result_q;
    logic                    stage3_valid_q;

    logic stage1_ready;
    logic stage2_ready;
    logic stage3_ready;

    initial begin
        if (NUM_ELEMS != 4) begin
            $fatal(1, "dot_product_pipeline supports exactly NUM_ELEMS=4");
        end

        if (RESULT_WIDTH < FINAL_SUM_WIDTH) begin
            $fatal(1, "RESULT_WIDTH must preserve the full four-element dot product");
        end
    end

    always_comb begin
        stage3_ready = !stage3_valid_q || out_ready;
        stage2_ready = !stage2_valid_q || stage3_ready;
        stage1_ready = !stage1_valid_q || stage2_ready;

        in_ready  = stage1_ready;
        out_valid = stage3_valid_q;
        result    = stage3_result_q;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_product0_q <= '0;
            stage1_product1_q <= '0;
            stage1_product2_q <= '0;
            stage1_product3_q <= '0;
            stage1_valid_q    <= 1'b0;

            stage2_sum0_q  <= '0;
            stage2_sum1_q  <= '0;
            stage2_valid_q <= 1'b0;

            stage3_result_q <= '0;
            stage3_valid_q  <= 1'b0;
        end else begin
            if (stage3_ready) begin
                stage3_valid_q <= stage2_valid_q;

                if (stage2_valid_q) begin
                    stage3_result_q <= {
                        {RESULT_PAD_WIDTH{1'b0}},
                        ({1'b0, stage2_sum0_q} + {1'b0, stage2_sum1_q})
                    };
                end
            end

            if (stage2_ready) begin
                stage2_valid_q <= stage1_valid_q;

                if (stage1_valid_q) begin
                    stage2_sum0_q <= {1'b0, stage1_product0_q}
                                      + {1'b0, stage1_product1_q};
                    stage2_sum1_q <= {1'b0, stage1_product2_q}
                                      + {1'b0, stage1_product3_q};
                end
            end

            if (stage1_ready) begin
                stage1_valid_q <= in_valid;

                if (in_valid) begin
                    stage1_product0_q <= PRODUCT_WIDTH'(vec_a[0*ELEM_WIDTH +: ELEM_WIDTH])
                                        * PRODUCT_WIDTH'(vec_b[0*ELEM_WIDTH +: ELEM_WIDTH]);
                    stage1_product1_q <= PRODUCT_WIDTH'(vec_a[1*ELEM_WIDTH +: ELEM_WIDTH])
                                        * PRODUCT_WIDTH'(vec_b[1*ELEM_WIDTH +: ELEM_WIDTH]);
                    stage1_product2_q <= PRODUCT_WIDTH'(vec_a[2*ELEM_WIDTH +: ELEM_WIDTH])
                                        * PRODUCT_WIDTH'(vec_b[2*ELEM_WIDTH +: ELEM_WIDTH]);
                    stage1_product3_q <= PRODUCT_WIDTH'(vec_a[3*ELEM_WIDTH +: ELEM_WIDTH])
                                        * PRODUCT_WIDTH'(vec_b[3*ELEM_WIDTH +: ELEM_WIDTH]);
                end
            end
        end
    end

endmodule

`default_nettype wire
