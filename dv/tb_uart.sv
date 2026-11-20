`timescale 1ns/1ps
// Loopback test: uart_tx -> uart_rx. Sends several bytes and checks each one.
module tb_uart;
  localparam int CPB = 16;

  logic       clk = 0, rst_n = 0;
  logic       start = 0;
  logic [7:0] tx_data = 0;
  logic       line, busy;
  logic [7:0] rx_data;
  logic       rx_valid, frame_err;
  int         errors = 0;

  uart_tx #(.CLKS_PER_BIT(CPB)) u_tx (
    .clk(clk), .rst_n(rst_n), .start(start), .data(tx_data), .tx(line), .busy(busy));
  uart_rx #(.CLKS_PER_BIT(CPB)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx(line), .data(rx_data), .valid(rx_valid), .frame_err(frame_err));

  always #5 clk = ~clk;

  task automatic send_and_check(input logic [7:0] b);
    @(posedge clk);
    tx_data <= b;
    start   <= 1'b1;
    @(posedge clk);
    start   <= 1'b0;
    do @(posedge clk); while (!rx_valid);
    if (rx_data !== b || frame_err) begin
      errors++;
      $display("FAIL: sent %02h got %02h frame_err=%0b", b, rx_data, frame_err);
    end else $display("ok  : %02h", b);
    while (busy) @(posedge clk);
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);
    send_and_check(8'h41);
    send_and_check(8'h55);
    send_and_check(8'h00);
    send_and_check(8'hFF);
    send_and_check(8'hA5);
    if (errors == 0) $display("TB_UART PASS");
    else             $display("TB_UART FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #1ms;
    $display("TB_UART FAIL: timeout");
    $finish;
  end
endmodule
