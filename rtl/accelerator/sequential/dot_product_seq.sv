`timescale 1ns/1ps
`default_nettype none

module dot_product_seq #(
    parameter int ELEM_WIDTH   = 8,
    parameter int NUM_ELEMS    = 4,
    parameter int RESULT_WIDTH = 32
)(
    input  logic                         clk,
    input  logic                         rst_n,

    input  logic                         start,
    input  logic [ELEM_WIDTH*NUM_ELEMS-1:0] vec_a,
    input  logic [ELEM_WIDTH*NUM_ELEMS-1:0] vec_b,

    output logic [RESULT_WIDTH-1:0]      result,
    output logic                         busy,
    output logic                         done
);

    localparam int VEC_WIDTH  = ELEM_WIDTH * NUM_ELEMS;
    localparam int PROD_WIDTH = 2 * ELEM_WIDTH;
    localparam int IDX_WIDTH  = (NUM_ELEMS <= 1) ? 1 : $clog2(NUM_ELEMS);

    typedef enum logic [0:0] {
        S_IDLE,
        S_RUN
    } state_e;

    state_e state_q;

    logic [VEC_WIDTH-1:0]       vec_a_q;
    logic [VEC_WIDTH-1:0]       vec_b_q;
    logic [RESULT_WIDTH-1:0]    acc_q;
    logic [IDX_WIDTH-1:0]       idx_q;

    logic [ELEM_WIDTH-1:0]      a_elem;
    logic [ELEM_WIDTH-1:0]      b_elem;
    logic [PROD_WIDTH-1:0]      product;
    logic [RESULT_WIDTH-1:0]    product_ext;
    logic [RESULT_WIDTH-1:0]    acc_next;

    function automatic logic [ELEM_WIDTH-1:0] get_elem(
        input logic [VEC_WIDTH-1:0] vec,
        input logic [IDX_WIDTH-1:0] idx
    );
        get_elem = vec[idx*ELEM_WIDTH +: ELEM_WIDTH];
    endfunction

    always_comb begin
        a_elem     = get_elem(vec_a_q, idx_q);
        b_elem     = get_elem(vec_b_q, idx_q);
        product    = a_elem * b_elem;
        product_ext = {{(RESULT_WIDTH-PROD_WIDTH){1'b0}}, product};
        acc_next   = acc_q + product_ext;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= S_IDLE;
            vec_a_q <= '0;
            vec_b_q <= '0;
            acc_q   <= '0;
            idx_q   <= '0;
            result  <= '0;
            busy    <= 1'b0;
            done    <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state_q)

                S_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        vec_a_q <= vec_a;
                        vec_b_q <= vec_b;
                        acc_q   <= '0;
                        idx_q   <= '0;
                        busy    <= 1'b1;
                        state_q <= S_RUN;
                    end
                end

                S_RUN: begin
                    busy <= 1'b1;

                    if (idx_q == IDX_WIDTH'(NUM_ELEMS-1)) begin
                        result  <= acc_next;
                        acc_q   <= '0;
                        idx_q   <= '0;
                        busy    <= 1'b0;
                        done    <= 1'b1;
                        state_q <= S_IDLE;
                    end else begin
                        acc_q <= acc_next;
                        idx_q <= idx_q + 1'b1;
                    end
                end

                default: begin
                    state_q <= S_IDLE;
                    busy    <= 1'b0;
                    done    <= 1'b0;
                end

            endcase
        end
    end

endmodule

`default_nettype wire
