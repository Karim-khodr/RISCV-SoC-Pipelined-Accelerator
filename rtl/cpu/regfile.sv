`timescale 1ns/1ps

module regfile (
  input  logic        clk,
  input  logic        rst_n,

  input  logic        we,
  input  logic [4:0]  waddr,
  input  logic [31:0] wdata,

  input  logic [4:0]  raddr1,
  input  logic [4:0]  raddr2,
  output logic [31:0] rdata1,
  output logic [31:0] rdata2
);

  logic [31:0] regs [31:0];

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      for (int i = 0; i < 32; i++) begin
        regs[i] <= 32'd0;
      end
    end else begin
      if (we && (waddr != 5'd0)) begin
        regs[waddr] <= wdata;
      end

      regs[0] <= 32'd0;
    end
  end

  assign rdata1 = (raddr1 == 5'd0) ? 32'd0 : regs[raddr1];
  assign rdata2 = (raddr2 == 5'd0) ? 32'd0 : regs[raddr2];

`ifndef SYNTHESIS
  always_comb begin
    assert (!$isunknown(raddr1))
      else $error("regfile raddr1 contains X/Z");

    assert (!$isunknown(raddr2))
      else $error("regfile raddr2 contains X/Z");

    assert (!$isunknown(waddr))
      else $error("regfile waddr contains X/Z");

    assert (!$isunknown(we))
      else $error("regfile we contains X/Z");
  end

  always_ff @(posedge clk) begin
    if (rst_n) begin
      assert (regs[0] == 32'd0)
        else $error("regfile x0 was modified");
    end
  end
`endif

endmodule
