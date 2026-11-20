`timescale 1ns/1ps
// Firmware test: the core transmits UART bytes by bit-banging pin 0; uart_rx decodes them.
module tb_core_uart;
  import emu_isa_pkg::*;

  logic        clk = 0, rst_n = 0, run = 0;
  logic        prog_we = 0;
  logic [5:0]  prog_addr = 0;
  logic [15:0] prog_data = 0;
  logic        tx_wr = 0;
  logic [7:0]  tx_wdata = 0;
  logic        tx_full;
  logic        rx_rd = 0;
  logic [7:0]  rx_rdata;
  logic        rx_empty;
  logic [7:0]  pin_out, pin_oe;
  logic        halted;
  logic [7:0]  rd_data;
  logic        rd_valid, ferr;
  logic [15:0] prog [64];
  logic [7:0]  got [$];
  logic [7:0]  exp [5] = '{8'h41, 8'h55, 8'h00, 8'hFF, 8'hA5};
  int          errors = 0;

  tri1 [7:0] pad;
  wire [7:0] pin_in = pad;
  genvar g;
  generate
    for (g = 0; g < 8; g++) begin : g_pad
      assign pad[g] = pin_oe[g] ? pin_out[g] : 1'bz;
    end
  endgenerate

  emu_core dut (
    .clk(clk), .rst_n(rst_n), .run(run),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .tx_wr(tx_wr), .tx_wdata(tx_wdata), .tx_full(tx_full),
    .rx_rd(rx_rd), .rx_rdata(rx_rdata), .rx_empty(rx_empty),
    .pin_in(pin_in), .pin_out(pin_out), .pin_oe(pin_oe), .halted(halted));

  uart_rx #(.CLKS_PER_BIT(16)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx(pad[0]), .data(rd_data), .valid(rd_valid), .frame_err(ferr));

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (rd_valid) begin
      got.push_back(rd_data);
      if (ferr) begin errors++; $display("FAIL: framing error"); end
    end
  end

  task automatic push(input logic [7:0] b);
    do @(posedge clk); while (tx_full);
    tx_wr <= 1'b1; tx_wdata <= b;
    @(posedge clk);
    tx_wr <= 1'b0;
  endtask

  initial begin
    for (int i = 0; i < 64; i++) prog[i] = i_nop();
    // 16 clocks per bit: SET+WAIT 14 = 16, OUT+WAIT 13+DJNZ = 16
    prog[0]  = i_oe(0, 1);
    prog[1]  = i_set(0, 1);
    prog[2]  = i_pull();
    prog[3]  = i_loadx(7);
    prog[4]  = i_set(0, 0);       // start bit
    prog[5]  = i_wait(14);
    prog[6]  = i_out(0, 0);       // data bit, LSB first
    prog[7]  = i_wait(13);
    prog[8]  = i_djnz(6);
    prog[9]  = i_set(0, 1);       // stop bit
    prog[10] = i_wait(14);
    prog[11] = i_jmp(2);

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

    foreach (exp[i]) push(exp[i]);
    wait (got.size() == 5);
    repeat (4) @(posedge clk);

    foreach (exp[i]) begin
      if (got[i] !== exp[i]) begin
        errors++;
        $display("FAIL: byte %0d sent %02h got %02h", i, exp[i], got[i]);
      end else $display("ok  : byte %0d = %02h", i, got[i]);
    end
    if (errors == 0) $display("TB_CORE_UART PASS");
    else             $display("TB_CORE_UART FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #1ms;
    $display("TB_CORE_UART FAIL: timeout (got %0d bytes)", got.size());
    $finish;
  end
endmodule
