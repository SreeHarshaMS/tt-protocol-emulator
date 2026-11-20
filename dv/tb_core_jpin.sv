`timescale 1ns/1ps
// Firmware test: JPIN polls pin 4 until it goes high, then SET drives pin 5 and HALT stops the core.
module tb_core_jpin;
  import emu_isa_pkg::*;

  logic        clk = 0, rst_n = 0, run = 0;
  logic        prog_we = 0;
  logic [5:0]  prog_addr = 0;
  logic [15:0] prog_data = 0;
  logic [7:0]  rx_rdata;
  logic        rx_empty, tx_full;
  logic [7:0]  pin_out, pin_oe;
  logic        halted;
  logic [15:0] prog [64];
  logic        p4 = 1'b0;
  int          errors = 0;

  tri1 [7:0] pad;
  wire [7:0] pin_in = pad;
  genvar g;
  generate
    for (g = 0; g < 8; g++) begin : g_pad
      assign pad[g] = pin_oe[g] ? pin_out[g] : 1'bz;
    end
  endgenerate
  assign pad[4] = p4;

  emu_core dut (
    .clk(clk), .rst_n(rst_n), .run(run),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .tx_wr(1'b0), .tx_wdata(8'h00), .tx_full(tx_full),
    .rx_rd(1'b0), .rx_rdata(rx_rdata), .rx_empty(rx_empty),
    .pin_in(pin_in), .pin_out(pin_out), .pin_oe(pin_oe), .halted(halted));

  always #5 clk = ~clk;

  initial begin
    for (int i = 0; i < 64; i++) prog[i] = i_nop();
    prog[0] = i_oe(5, 1);
    prog[1] = i_set(5, 0);
    prog[2] = i_jpin(4, 0, 2);    // loop while pin 4 is low
    prog[3] = i_set(5, 1);
    prog[4] = i_halt();

    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);
    for (int i = 0; i < 64; i++) begin
      @(posedge clk);
      prog_we <= 1'b1; prog_addr <= i[5:0]; prog_data <= prog[i];
    end
    @(posedge clk);
    prog_we <= 1'b0;
    run <= 1'b1;

    repeat (30) @(posedge clk);
    if (pad[5] !== 1'b0 || halted) begin
      errors++;
      $display("FAIL: core should still be polling (pad5=%b halted=%b)", pad[5], halted);
    end else $display("ok  : polling while pin 4 low");

    p4 = 1'b1;
    repeat (10) @(posedge clk);
    if (pad[5] !== 1'b1 || !halted) begin
      errors++;
      $display("FAIL: expected pad5=1 and halted (pad5=%b halted=%b)", pad[5], halted);
    end else $display("ok  : jumped out, pin 5 high, halted");

    if (errors == 0) $display("TB_CORE_JPIN PASS");
    else             $display("TB_CORE_JPIN FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #100us;
    $display("TB_CORE_JPIN FAIL: timeout");
    $finish;
  end
endmodule
