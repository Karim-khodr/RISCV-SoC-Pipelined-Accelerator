`timescale 1ns/1ps
`default_nettype none

module dot_product_accel_mmio #(
    parameter int ELEM_WIDTH   = 8,
    parameter int NUM_ELEMS    = 4,
    parameter int RESULT_WIDTH = 32
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [31:0] mmio_addr,
    input  logic        mmio_read,
    input  logic        mmio_write,
    input  logic [31:0] mmio_wdata,
    output logic [31:0] mmio_rdata
);

    localparam logic [31:0] CONTROL_OFFSET = 32'h0000_0000;
    localparam logic [31:0] STATUS_OFFSET  = 32'h0000_0004;
    localparam logic [31:0] VEC_A_OFFSET   = 32'h0000_0008;
    localparam logic [31:0] VEC_B_OFFSET   = 32'h0000_000c;
    localparam logic [31:0] RESULT_OFFSET  = 32'h0000_0010;

    localparam int VECTOR_WIDTH = ELEM_WIDTH * NUM_ELEMS;

    logic [31:0] vec_a_q;
    logic [31:0] vec_b_q;
    logic [31:0] command_vec_a_q;
    logic [31:0] command_vec_b_q;
    logic [31:0] result_q;

    logic command_pending_q;
    logic inflight_q;
    logic result_valid_q;

    logic ready;
    logic busy;

    logic                    pipe_in_valid;
    logic                    pipe_in_ready;
    logic [VECTOR_WIDTH-1:0] pipe_vec_a;
    logic [VECTOR_WIDTH-1:0] pipe_vec_b;
    logic                    pipe_out_valid;
    logic                    pipe_out_ready;
    logic [RESULT_WIDTH-1:0] pipe_result;

    logic start_write;
    logic result_read;
    logic input_handshake;
    logic output_handshake;

`ifndef SYNTHESIS
    initial begin
        if (VECTOR_WIDTH != 32) begin
            $fatal(1, "dot_product_accel_mmio requires a 32-bit packed vector");
        end

        if (RESULT_WIDTH != 32) begin
            $fatal(1, "dot_product_accel_mmio requires a 32-bit MMIO result");
        end
    end
`endif

    assign ready = !(command_pending_q || inflight_q || result_valid_q);
    assign busy  = command_pending_q || inflight_q;

    assign start_write = mmio_write
                         && (mmio_addr == CONTROL_OFFSET)
                         && mmio_wdata[0];
    assign result_read = mmio_read && (mmio_addr == RESULT_OFFSET);

    assign pipe_in_valid = command_pending_q;
    assign pipe_vec_a = command_vec_a_q[VECTOR_WIDTH-1:0];
    assign pipe_vec_b = command_vec_b_q[VECTOR_WIDTH-1:0];
    assign pipe_out_ready = !result_valid_q;

    assign input_handshake  = pipe_in_valid && pipe_in_ready;
    assign output_handshake = pipe_out_valid && pipe_out_ready;

    dot_product_pipeline #(
        .ELEM_WIDTH   (ELEM_WIDTH),
        .NUM_ELEMS    (NUM_ELEMS),
        .RESULT_WIDTH (RESULT_WIDTH)
    ) u_pipeline (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (pipe_in_valid),
        .in_ready  (pipe_in_ready),
        .vec_a     (pipe_vec_a),
        .vec_b     (pipe_vec_b),
        .out_valid (pipe_out_valid),
        .out_ready (pipe_out_ready),
        .result    (pipe_result)
    );

    always_comb begin
        mmio_rdata = 32'h0000_0000;

        if (mmio_read) begin
            case (mmio_addr)
                CONTROL_OFFSET: mmio_rdata = 32'h0000_0000;
                STATUS_OFFSET: begin
                    mmio_rdata = {29'd0, result_valid_q, busy, ready};
                end
                VEC_A_OFFSET:  mmio_rdata = vec_a_q;
                VEC_B_OFFSET:  mmio_rdata = vec_b_q;
                RESULT_OFFSET: mmio_rdata = result_q;
                default:       mmio_rdata = 32'h0000_0000;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vec_a_q            <= 32'h0000_0000;
            vec_b_q            <= 32'h0000_0000;
            command_vec_a_q    <= 32'h0000_0000;
            command_vec_b_q    <= 32'h0000_0000;
            result_q           <= 32'h0000_0000;
            command_pending_q  <= 1'b0;
            inflight_q         <= 1'b0;
            result_valid_q     <= 1'b0;
        end else begin
            if (mmio_write && ready) begin
                case (mmio_addr)
                    VEC_A_OFFSET: vec_a_q <= mmio_wdata;
                    VEC_B_OFFSET: vec_b_q <= mmio_wdata;
                    default: begin
                    end
                endcase
            end

            if (start_write && ready) begin
                command_vec_a_q   <= vec_a_q;
                command_vec_b_q   <= vec_b_q;
                command_pending_q <= 1'b1;
            end

            if (input_handshake) begin
                command_pending_q <= 1'b0;
                inflight_q        <= 1'b1;
            end

            if (result_read && result_valid_q) begin
                result_valid_q <= 1'b0;
            end

            // Capture has priority over a simultaneous early RESULT read.
            if (output_handshake) begin
                result_q       <= pipe_result;
                result_valid_q <= 1'b1;
                inflight_q     <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
