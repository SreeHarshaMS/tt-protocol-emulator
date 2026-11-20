`timescale 1ns/1ps
// End-to-end test of the Tiny Tapeout top: everything goes through the host SPI port.
// Loads the I2C firmware, then does write / repeated START / read transactions against the slave model,
// and finally reloads the UART firmware and checks a transmitted byte.
module tb_top;
  import emu_fw_pkg::*;

  logic       clk = 0, rst_n = 0;
  logic [7:0] ui_in = 8'h04;                 // CS_n high
  logic [7:0] uo_out, uio_out, uio_oe;
  int         errors = 0;
  prog_t      prog;
  int         plen;

  tri1 [7:0] uio;
  genvar g;
  generate
    for (g = 0; g < 8; g++) begin : g_pad
      assign uio[g] = uio_oe[g] ? uio_out[g] : 1'bz;
    end
  endgenerate

  logic       slv_sda_oe;
  logic [7:0] mem;
  assign uio[1] = slv_sda_oe ? 1'b0 : 1'bz;

  tt_um_sreeharshams_protocol_emulator dut (
    .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio), .uio_out(uio_out), .uio_oe(uio_oe),
    .ena(1'b1), .clk(clk), .rst_n(rst_n));

  i2c_slave_model slv (.scl_line(uio[0]), .sda_line(uio[1]), .slv_sda_oe(slv_sda_oe), .mem(mem));

  logic [7:0] u_data;
  logic       u_valid, u_ferr;
  uart_rx #(.CLKS_PER_BIT(16)) u_rx (
    .clk(clk), .rst_n(rst_n), .rx(uio[0]), .data(u_data), .valid(u_valid), .frame_err(u_ferr));

  always #5 clk = ~clk;

  // host SPI master, mode 0, SCK = clk/10
  task automatic spi_byte(input logic [7:0] tx, output logic [7:0] rx);
    for (int i = 7; i >= 0; i--) begin
      ui_in[0] = tx[i];
      repeat (5) @(posedge clk);
      rx[i] = uo_out[0];
      ui_in[1] = 1'b1;
      repeat (5) @(posedge clk);
      ui_in[1] = 1'b0;
    end
  endtask

  task automatic frame(input logic [7:0] b0, input logic [7:0] b1, input logic [7:0] b2,
                       input logic [7:0] b3, input int nbytes, output logic [7:0] last);
    logic [7:0] r;
    ui_in[2] = 1'b0;
    repeat (4) @(posedge clk);
    spi_byte(b0, r);
    if (nbytes > 1) spi_byte(b1, r);
    if (nbytes > 2) spi_byte(b2, r);
    if (nbytes > 3) spi_byte(b3, r);
    last = r;
    repeat (4) @(posedge clk);
    ui_in[2] = 1'b1;
    repeat (4) @(posedge clk);
  endtask

  logic [7:0] sink;

  task automatic load_prog();
    for (int i = 0; i < 64; i++)
      frame(8'h01, i[7:0], prog[i][15:8], prog[i][7:0], 4, sink);
  endtask

  task automatic set_run(input logic r);
    frame(8'h02, {7'b0, r}, 8'h00, 8'h00, 2, sink);
  endtask

  task automatic h_push(input logic [7:0] b);
    logic [7:0] st;
    do frame(8'h05, 8'h00, 8'h00, 8'h00, 2, st); while (st[0]);   // wait while TX FIFO full
    frame(8'h03, b, 8'h00, 8'h00, 2, sink);
  endtask

  task automatic h_pop(output logic [7:0] b);
    logic [7:0] st;
    do frame(8'h05, 8'h00, 8'h00, 8'h00, 2, st); while (st[1]);   // wait until RX FIFO has data
    frame(8'h04, 8'h00, 8'h00, 8'h00, 2, b);
  endtask

  task automatic i2c_write(input logic [7:0] b, output logic ack);
    logic [7:0] r;
    h_push(8'd1); h_push(b); h_pop(r);
    ack = r[0];
  endtask

  task automatic i2c_read(input logic nack, output logic [7:0] b);
    h_push(8'd2); h_push({7'b0, nack}); h_pop(b);
  endtask

  task automatic check(input string what, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s got %02h want %02h", what, got, exp);
    end else $display("ok  : %s = %02h", what, got);
  endtask

  logic       ack;
  logic [7:0] rd;
  logic [7:0] seen [$];

  always @(posedge clk) if (u_valid) seen.push_back(u_data);

  // ---- invariants of the core and host port, checked on every clock
  a_stopped_pc: assert property (@(posedge clk) disable iff (!rst_n)
      !dut.u_core.run |=> $stable(dut.u_core.pc))
    else begin errors++; $display("FAIL: assertion a_stopped_pc at %0t", $time); end
  a_halt_sticky: assert property (@(posedge clk) disable iff (!rst_n)
      dut.u_core.halted |=> dut.u_core.halted)
    else begin errors++; $display("FAIL: assertion a_halt_sticky at %0t", $time); end
  a_wait_op: assert property (@(posedge clk) disable iff (!rst_n)
      dut.u_core.wait_active |-> dut.u_core.op == 4'h2)
    else begin errors++; $display("FAIL: assertion a_wait_op at %0t", $time); end
  a_rx_no_overflow: assert property (@(posedge clk) disable iff (!rst_n)
      dut.u_core.rx_push |-> !dut.u_core.rx_full)
    else begin errors++; $display("FAIL: assertion a_rx_no_overflow at %0t", $time); end
  a_tx_no_underflow: assert property (@(posedge clk) disable iff (!rst_n)
      dut.u_core.tx_pop |-> !dut.u_core.tx_empty)
    else begin errors++; $display("FAIL: assertion a_tx_no_underflow at %0t", $time); end
  a_fifo_sane: assert property (@(posedge clk) disable iff (!rst_n)
      !(dut.u_core.tx_full && dut.u_core.tx_empty) && !(dut.u_core.rx_full && dut.u_core.rx_empty))
    else begin errors++; $display("FAIL: assertion a_fifo_sane at %0t", $time); end
  a_host_push_room: assert property (@(posedge clk) disable iff (!rst_n)
      dut.u_host.tx_wr |-> !dut.u_core.tx_full)
    else begin errors++; $display("FAIL: assertion a_host_push_room at %0t (byte would be dropped)", $time); end

  logic [7:0] rnd;
  logic [7:0] exp_q [$];

  initial begin
    repeat (6) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    // ---- I2C firmware through the host port
    fw_i2c(prog, plen, 3);
    $display("i2c firmware: %0d of 64 words", plen);
    load_prog();
    set_run(1);

    h_push(8'd0);                                   // START
    i2c_write(8'hA0, ack);  check("write addr ack", {7'b0, ack}, 8'h00);
    i2c_write(8'h5A, ack);  check("write data ack", {7'b0, ack}, 8'h00);
    check("slave memory", mem, 8'h5A);
    h_push(8'd0);                                   // repeated START
    i2c_write(8'hA1, ack);  check("read addr ack", {7'b0, ack}, 8'h00);
    i2c_read(0, rd);        check("read byte 1 (ACK)", rd, 8'h3C);
    i2c_read(1, rd);        check("read byte 2 (NACK)", rd, 8'hC3);
    h_push(8'd3);                                   // STOP
    h_push(8'd0);
    i2c_write(8'hA4, ack);  check("wrong addr nack", {7'b0, ack}, 8'h01);
    h_push(8'd3);

    // ---- constrained-random I2C writes: random data, every one must land in the slave
    for (int k = 0; k < 16; k++) begin
      rnd = $urandom;
      h_push(8'd0);
      i2c_write(8'hA0, ack);
      if (ack) begin errors++; $display("FAIL: random write %0d: address NACK", k); end
      i2c_write(rnd, ack);
      if (ack) begin errors++; $display("FAIL: random write %0d: data NACK", k); end
      h_push(8'd3);
      if (mem !== rnd) begin errors++; $display("FAIL: random write %0d: slave has %02h want %02h", k, mem, rnd); end
    end
    $display("ok  : 16 random I2C writes checked");

    // ---- switch to the UART firmware
    set_run(0);
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);
    seen.delete();                                  // the I2C clock on pin 0 decoded as UART noise
    fw_uart_tx(prog, plen);
    $display("uart firmware: %0d of 64 words", plen);
    load_prog();
    set_run(1);
    h_push(8'h41);
    h_push(8'hC3);
    wait (seen.size() >= 2);
    check("uart byte 0", seen[0], 8'h41);
    check("uart byte 1", seen[1], 8'hC3);

    // ---- constrained-random UART stream: 32 random bytes back to back, compared in order
    for (int k = 0; k < 32; k++) begin
      rnd = $urandom;
      exp_q.push_back(rnd);
      h_push(rnd);
    end
    wait (seen.size() >= 34);
    repeat (20) @(posedge clk);
    if (seen.size() != 34) begin errors++; $display("FAIL: uart got %0d bytes, want 34", seen.size()); end
    foreach (exp_q[k])
      if (seen[k+2] !== exp_q[k]) begin
        errors++; $display("FAIL: random uart byte %0d got %02h want %02h", k, seen[k+2], exp_q[k]);
      end
    $display("ok  : 32 random UART bytes checked");

    if (errors == 0) $display("TB_TOP PASS");
    else             $display("TB_TOP FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #30ms;
    $display("TB_TOP FAIL: timeout");
    $finish;
  end
endmodule
