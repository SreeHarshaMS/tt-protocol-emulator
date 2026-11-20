`timescale 1ns/1ps
// I2C master against the behavioural slave at address 0x50.
module tb_i2c;
  localparam logic [1:0] CMD_START = 2'd0, CMD_WRITE = 2'd1, CMD_READ = 2'd2, CMD_STOP = 2'd3;

  logic       clk = 0, rst_n = 0;
  logic       cmd_valid = 0;
  logic [1:0] cmd = 0;
  logic [7:0] tx_byte = 0;
  logic       nack_in = 0;
  logic       busy, done, slave_nack;
  logic [7:0] rx_byte;
  logic       dut_scl_oe, dut_sda_oe;
  logic       slv_sda_oe;
  logic [7:0] mem;
  int         errors = 0;

  wire scl_line = ~dut_scl_oe;
  wire sda_line = ~(dut_sda_oe | slv_sda_oe);

  i2c_master #(.CLK_DIV(4)) dut (
    .clk(clk), .rst_n(rst_n), .cmd_valid(cmd_valid), .cmd(cmd), .tx_byte(tx_byte), .nack_in(nack_in),
    .busy(busy), .done(done), .rx_byte(rx_byte), .slave_nack(slave_nack),
    .scl_i(scl_line), .sda_i(sda_line), .scl_oe(dut_scl_oe), .sda_oe(dut_sda_oe));

  i2c_slave_model slv (.scl_line(scl_line), .sda_line(sda_line), .slv_sda_oe(slv_sda_oe), .mem(mem));

  always #5 clk = ~clk;

  task automatic i2c_cmd(input logic [1:0] c, input logic [7:0] b, input logic nk);
    @(posedge clk);
    cmd <= c; tx_byte <= b; nack_in <= nk; cmd_valid <= 1'b1;
    @(posedge clk);
    cmd_valid <= 1'b0;
    do @(posedge clk); while (!done);
  endtask

  task automatic check(input string what, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s got %02h want %02h", what, got, exp);
    end else $display("ok  : %s = %02h", what, got);
  endtask

  initial begin
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    i2c_cmd(CMD_START, 8'h00, 0);
    i2c_cmd(CMD_WRITE, 8'hA0, 0);  check("write addr ack (slave_nack)", {7'b0, slave_nack}, 8'h00);
    i2c_cmd(CMD_WRITE, 8'h5A, 0);  check("write data ack (slave_nack)", {7'b0, slave_nack}, 8'h00);
    i2c_cmd(CMD_STOP,  8'h00, 0);
    check("slave memory", mem, 8'h5A);

    i2c_cmd(CMD_START, 8'h00, 0);
    i2c_cmd(CMD_WRITE, 8'hA1, 0);  check("read addr ack (slave_nack)", {7'b0, slave_nack}, 8'h00);
    i2c_cmd(CMD_READ,  8'h00, 0);  check("read byte 1", rx_byte, 8'h3C);
    i2c_cmd(CMD_READ,  8'h00, 1);  check("read byte 2", rx_byte, 8'hC3);
    i2c_cmd(CMD_STOP,  8'h00, 0);

    i2c_cmd(CMD_START, 8'h00, 0);
    i2c_cmd(CMD_WRITE, 8'hA4, 0);  check("wrong addr nack (slave_nack)", {7'b0, slave_nack}, 8'h01);
    i2c_cmd(CMD_STOP,  8'h00, 0);

    if (errors == 0) $display("TB_I2C PASS");
    else             $display("TB_I2C FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #5ms;
    $display("TB_I2C FAIL: timeout");
    $finish;
  end
endmodule
