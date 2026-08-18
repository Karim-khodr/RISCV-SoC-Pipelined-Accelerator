`timescale 1ns/1ps

module data_mem #(
  parameter int DEPTH = 256
) (
  input  logic        clk,

  input  logic        mem_re,
  input  logic        mem_we,
  input  logic [31:0] addr,
  input  logic [31:0] wdata,
  output logic [31:0] rdata
);

  localparam int ADDR_WIDTH = $clog2(DEPTH);

  logic [31:0] mem [0:DEPTH-1];

  logic [31:0] word_addr_full;
  logic [ADDR_WIDTH-1:0] word_addr;

  assign word_addr_full = addr >> 2;
  assign word_addr      = word_addr_full[ADDR_WIDTH-1:0];

  initial begin
    for (int i = 0; i < DEPTH; i++) begin
      mem[i] = 32'd0;
    end
  end

  always_comb begin
    if (mem_re && (word_addr_full < DEPTH)) begin
      rdata = mem[word_addr];
    end else begin
      rdata = 32'd0;
    end
  end

  always_ff @(posedge clk) begin
    if (mem_we && (word_addr_full < DEPTH)) begin
      mem[word_addr] <= wdata;
    end
  end

`ifndef SYNTHESIS
  always_comb begin
    if (mem_re || mem_we) begin
      assert (addr[1:0] == 2'b00)
        else $error("data_mem unaligned address: %h", addr);

      assert (word_addr_full < DEPTH)
        else $error("data_mem address out of range: %h", addr);
    end
  end
`endif

endmodule
