`timescale 1ns/1ps

module instr_mem #(
  parameter int DEPTH = 256
) (
  input  logic [31:0] addr,
  output logic [31:0] instr
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
    if (word_addr_full < DEPTH) begin
      instr = mem[word_addr];
    end else begin
      instr = 32'd0;
    end
  end

`ifndef SYNTHESIS
  always_comb begin
    assert (addr[1:0] == 2'b00)
      else $error("instr_mem unaligned address: %h", addr);
  end
`endif

endmodule
