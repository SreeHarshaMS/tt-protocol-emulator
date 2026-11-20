`timescale 1ns/1ps
// Behavioural SPI slave (testbench only): returns 8'hA5 on MISO and records what it receives on MOSI.
module spi_slave_model #(
  parameter bit CPOL = 0,
  parameter bit CPHA = 0
) (
  input  logic sck,
  input  logic cs_n,
  input  logic mosi,
  output logic miso,
  output logic [7:0] rx
);
  localparam logic [7:0] RESP = 8'hA5;
  int idx;

  initial miso = 1'b0;

  always @(negedge cs_n) begin
    idx = 0;
    rx  = 8'h00;
    if (!CPHA) begin
      miso = RESP[7];
      idx  = 1;
    end
  end

  always @(sck) begin
    if (!cs_n) begin
      if (sck != CPOL) begin
        if (!CPHA) rx = {rx[6:0], mosi};
        else if (idx < 8) begin miso = RESP[7-idx]; idx++; end
      end else begin
        if (!CPHA) begin if (idx < 8) begin miso = RESP[7-idx]; idx++; end end
        else rx = {rx[6:0], mosi};
      end
    end
  end
endmodule
