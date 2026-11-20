`timescale 1ns/1ps
module tb_spi;
  logic       clk = 0, rst_n = 0;
  logic       start = 0;
  logic [7:0] tx_data = 8'h3C;
  int         errors = 0;

  logic [3:0] busy, done, sck, mosi, cs_n, miso;
  logic [7:0] rx_data [4];
  logic [7:0] slv_rx  [4];

  always #5 clk = ~clk;

  genvar m;
  generate
    for (m = 0; m < 4; m++) begin : g_mode
      spi_master #(.CPOL(m[1]), .CPHA(m[0]), .CLK_DIV(4)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .tx_data(tx_data), .rx_data(rx_data[m]),
        .busy(busy[m]), .done(done[m]), .sck(sck[m]), .mosi(mosi[m]), .cs_n(cs_n[m]), .miso(miso[m]));
      spi_slave_model #(.CPOL(m[1]), .CPHA(m[0])) slv (
        .sck(sck[m]), .cs_n(cs_n[m]), .mosi(mosi[m]), .miso(miso[m]), .rx(slv_rx[m]));
    end
  endgenerate

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;
    repeat (400) @(posedge clk);
    for (int i = 0; i < 4; i++) begin
      if (rx_data[i] !== 8'hA5 || slv_rx[i] !== 8'h3C) begin
        errors++;
        $display("FAIL mode %0d: master rx=%02h (want A5), slave rx=%02h (want 3C)", i, rx_data[i], slv_rx[i]);
      end else $display("ok   mode %0d: master rx=%02h, slave rx=%02h", i, rx_data[i], slv_rx[i]);
    end
    if (errors == 0) $display("TB_SPI PASS");
    else             $display("TB_SPI FAIL (%0d errors)", errors);
    $finish;
  end
endmodule
