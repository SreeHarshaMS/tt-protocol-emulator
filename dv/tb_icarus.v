`timescale 1ns / 1ps
// Plain Verilog-2005 testbench (Icarus, the simulator the Tiny Tapeout CI uses).
// Checks the status byte, a tiny program (OE/SET/HALT), and the UART firmware loaded over the host port.
// Run:  iverilog -g2005 -o tb_icarus.vvp ../src/*.v tb_icarus.v  &&  vvp tb_icarus.vvp
module tb_icarus;
  reg        clk = 1'b0;
  reg        rst_n = 1'b0;
  reg  [7:0] ui_in = 8'h04;
  wire [7:0] uo_out, uio_out, uio_oe;
  tri1 [7:0] uio;
  integer    errors = 0;

  genvar g;
  generate
    for (g = 0; g < 8; g = g + 1) begin : g_pad
      assign uio[g] = uio_oe[g] ? uio_out[g] : 1'bz;
    end
  endgenerate

  tt_um_sreeharshams_protocol_emulator dut (
      .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio), .uio_out(uio_out), .uio_oe(uio_oe),
      .ena(1'b1), .clk(clk), .rst_n(rst_n));

  always #5 clk = ~clk;

  reg [15:0] uart_fw [0:11];
  initial begin
    uart_fw[0]  = 16'h1008;  // SET 0,1
    uart_fw[1]  = 16'hB008;  // OE 0,1
    uart_fw[2]  = 16'h9000;  // PULL
    uart_fw[3]  = 16'h3007;  // LOADX 7
    uart_fw[4]  = 16'h1000;  // SET 0,0   start bit
    uart_fw[5]  = 16'h200E;  // WAIT 14
    uart_fw[6]  = 16'h7000;  // OUT 0     data bit, LSB first
    uart_fw[7]  = 16'h200D;  // WAIT 13
    uart_fw[8]  = 16'h4006;  // DJNZ 6
    uart_fw[9]  = 16'h1008;  // SET 0,1   stop bit
    uart_fw[10] = 16'h200E;  // WAIT 14
    uart_fw[11] = 16'h5002;  // JMP 2
  end

  task spi_byte(input [7:0] tx, output [7:0] rx);
    integer i;
    begin
      for (i = 7; i >= 0; i = i - 1) begin
        ui_in[0] = tx[i];
        repeat (5) @(posedge clk);
        rx[i] = uo_out[0];
        ui_in[1] = 1'b1;
        repeat (5) @(posedge clk);
        ui_in[1] = 1'b0;
      end
    end
  endtask

  reg [7:0] r;
  task frame(input [7:0] b0, input [7:0] b1, input [7:0] b2, input [7:0] b3, input integer nb,
             output [7:0] last);
    begin
      ui_in[2] = 1'b0;
      repeat (4) @(posedge clk);
      spi_byte(b0, r);
      if (nb > 1) spi_byte(b1, r);
      if (nb > 2) spi_byte(b2, r);
      if (nb > 3) spi_byte(b3, r);
      last = r;
      repeat (4) @(posedge clk);
      ui_in[2] = 1'b1;
      repeat (4) @(posedge clk);
    end
  endtask

  reg [7:0] st, sink;
  task check8(input [8*24-1:0] what, input [7:0] got, input [7:0] exp);
    begin
      if (got !== exp) begin
        errors = errors + 1;
        $display("FAIL: %0s got %02h want %02h", what, got, exp);
      end else $display("ok  : %0s = %02h", what, got);
    end
  endtask

  reg [7:0] ub;
  reg       uok;
  task uart_recv;
    integer i;
    begin
      @(negedge uio[0]);
      repeat (8) @(posedge clk);
      uok = (uio[0] == 1'b0);
      for (i = 0; i < 8; i = i + 1) begin
        repeat (16) @(posedge clk);
        ub[i] = uio[0];
      end
      repeat (16) @(posedge clk);
      uok = uok & (uio[0] == 1'b1);
    end
  endtask

  integer k;
  initial begin
    repeat (6) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    frame(8'h05, 8'h00, 8'h00, 8'h00, 2, st);
    check8("status after reset", st, 8'h02);

    frame(8'h01, 8'd0, 8'hB0, 8'h0D, 4, sink);   // OE 5,1
    frame(8'h01, 8'd1, 8'h10, 8'h05, 4, sink);   // SET 5,0
    frame(8'h01, 8'd2, 8'hF0, 8'h00, 4, sink);   // HALT
    frame(8'h02, 8'h01, 8'h00, 8'h00, 2, sink);  // run
    repeat (20) @(posedge clk);
    check8("pin 5 oe/out", {6'b0, uio_oe[5], uio_out[5]}, 8'h02);
    frame(8'h05, 8'h00, 8'h00, 8'h00, 2, st);
    check8("status after HALT", st, 8'h0E);

    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);
    for (k = 0; k < 12; k = k + 1)
      frame(8'h01, k[7:0], uart_fw[k][15:8], uart_fw[k][7:0], 4, sink);
    frame(8'h02, 8'h01, 8'h00, 8'h00, 2, sink);
    fork
      frame(8'h03, 8'hA5, 8'h00, 8'h00, 2, sink);
      uart_recv;
    join
    check8("uart byte", ub, 8'hA5);
    check8("uart framing ok", {7'b0, uok}, 8'h01);

    if (errors == 0) $display("TB_ICARUS PASS");
    else             $display("TB_ICARUS FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #2000000;
    $display("TB_ICARUS FAIL: timeout");
    $finish;
  end
endmodule
