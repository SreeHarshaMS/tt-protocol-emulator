`timescale 1ns/1ps
// Firmware test: I2C master as firmware. Pins: 0 = SCL, 1 = SDA (open-drain, pull-ups on the bus).
// Pins 0 and 1 reset to 0 in pin_out, so OE alone pulls a line low or releases it.
// Host protocol: send a command byte to the TX FIFO, then:
//   0 START                    -> no reply
//   1 WRITE, data byte         -> reply byte, bit 0 = ack bit (0 = ACK, 1 = NACK)
//   2 READ,  flag byte         -> reply byte = data read; flag 0 = send ACK, 1 = send NACK
//   3 STOP                     -> no reply
module tb_core_i2c;
  import emu_isa_pkg::*;

  localparam int Q = 3;   // WAIT count for each quarter of an SCL period

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
  logic [15:0] prog [64];
  logic        slv_sda_oe;
  logic [7:0]  mem, rd;
  int          errors = 0;

  tri1 [7:0] pad;
  wire [7:0] pin_in = pad;
  genvar g;
  generate
    for (g = 0; g < 8; g++) begin : g_pad
      assign pad[g] = pin_oe[g] ? pin_out[g] : 1'bz;
    end
  endgenerate
  assign pad[1] = slv_sda_oe ? 1'b0 : 1'bz;

  emu_core #(.PIN_OUT_RESET(8'hFC)) dut (
    .clk(clk), .rst_n(rst_n), .run(run),
    .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
    .tx_wr(tx_wr), .tx_wdata(tx_wdata), .tx_full(tx_full),
    .rx_rd(rx_rd), .rx_rdata(rx_rdata), .rx_empty(rx_empty),
    .pin_in(pin_in), .pin_out(pin_out), .pin_oe(pin_oe), .halted(halted));

  i2c_slave_model slv (.scl_line(pad[0]), .sda_line(pad[1]), .slv_sda_oe(slv_sda_oe), .mem(mem));

  always #5 clk = ~clk;

  // tiny assembler
  int pcn = 0;
  int L_main, L_start, L_write, L_read, L_stop;
  int j_start, j_write, j_read, j_stop;
  int bit_loop;

  task automatic emit(input logic [15:0] w);
    if (pcn < 64) prog[pcn] = w;
    pcn++;
  endtask

  task automatic scl_pulse();
    emit(i_oe(0, 0));
    emit(i_jpin(0, 0, pcn[5:0]));   // wait while SCL is held low (clock stretching)
    emit(i_wait(Q));
  endtask

  task automatic build_firmware();
    for (int i = 0; i < 64; i++) prog[i] = i_nop();

    L_main = pcn;
    emit(i_pull());
    emit(i_outx());                 // X = command, then a DJNZ ladder dispatches on it
    emit(i_djnz(pcn[5:0] + 6'd2));  j_start = pcn; emit(i_jmp(0));
    emit(i_djnz(pcn[5:0] + 6'd2));  j_write = pcn; emit(i_jmp(0));
    emit(i_djnz(pcn[5:0] + 6'd2));  j_read  = pcn; emit(i_jmp(0));
    emit(i_djnz(L_main[5:0]));      j_stop  = pcn; emit(i_jmp(0));

    // START (also repeated START)
    L_start = pcn;
    emit(i_oe(1, 0));  emit(i_wait(Q));
    scl_pulse();
    emit(i_oe(1, 1));  emit(i_wait(Q));
    emit(i_oe(0, 1));
    emit(i_jmp(L_main[5:0]));

    // WRITE one byte, then clock in the ack bit
    L_write = pcn;
    emit(i_pull());
    emit(i_loadx(7));
    bit_loop = pcn;
    emit(i_outd(1, 1));  emit(i_wait(Q));
    scl_pulse();
    emit(i_oe(0, 1));
    emit(i_djnz(bit_loop[5:0]));
    emit(i_oe(1, 0));  emit(i_wait(Q));
    emit(i_oe(0, 0));
    emit(i_jpin(0, 0, pcn[5:0]));
    emit(i_wait(Q));
    emit(i_in(1, 1));                // sample ack
    emit(i_oe(0, 1));
    emit(i_push());
    emit(i_jmp(L_main[5:0]));

    // READ one byte; the host's flag byte (0 = ACK, 1 = NACK) is applied to SDA with OUTD
    L_read = pcn;
    emit(i_pull());
    emit(i_oe(1, 0));
    emit(i_loadx(7));
    bit_loop = pcn;
    emit(i_wait(Q));
    emit(i_oe(0, 0));
    emit(i_jpin(0, 0, pcn[5:0]));
    emit(i_wait(Q));
    emit(i_in(1, 1));
    emit(i_oe(0, 1));
    emit(i_djnz(bit_loop[5:0]));
    emit(i_outd(1, 0));              // ACK drives SDA low, NACK leaves it released
    emit(i_wait(Q));
    scl_pulse();
    emit(i_oe(0, 1));
    emit(i_oe(1, 0));
    emit(i_push());
    emit(i_jmp(L_main[5:0]));

    // STOP
    L_stop = pcn;
    emit(i_oe(1, 1));  emit(i_wait(Q));
    scl_pulse();
    emit(i_oe(1, 0));
    emit(i_jmp(L_main[5:0]));

    prog[j_start] = i_jmp(L_start[5:0]);
    prog[j_write] = i_jmp(L_write[5:0]);
    prog[j_read]  = i_jmp(L_read[5:0]);
    prog[j_stop]  = i_jmp(L_stop[5:0]);
    $display("firmware: %0d of 64 instructions", pcn);
    if (pcn > 64) begin
      errors++;
      $display("FAIL: firmware does not fit in program memory");
    end
  endtask

  task automatic hpush(input logic [7:0] b);
    do @(posedge clk); while (tx_full);
    tx_wr <= 1'b1; tx_wdata <= b;
    @(posedge clk);
    tx_wr <= 1'b0;
  endtask

  task automatic hpop(output logic [7:0] b);
    do @(posedge clk); while (rx_empty);
    b = rx_rdata;
    rx_rd <= 1'b1;
    @(posedge clk);
    rx_rd <= 1'b0;
  endtask

  task automatic i2c_start();            hpush(8'd0); endtask
  task automatic i2c_stop();             hpush(8'd3); endtask
  task automatic i2c_write(input logic [7:0] b, output logic ack);
    logic [7:0] r;
    hpush(8'd1); hpush(b); hpop(r);
    ack = r[0];
  endtask
  task automatic i2c_read(input logic nack, output logic [7:0] b);
    hpush(8'd2); hpush({7'b0, nack}); hpop(b);
  endtask

  task automatic check(input string what, input logic [7:0] got, input logic [7:0] exp);
    if (got !== exp) begin
      errors++;
      $display("FAIL: %s got %02h want %02h", what, got, exp);
    end else $display("ok  : %s = %02h", what, got);
  endtask

  logic ack;

  initial begin
    build_firmware();

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

    i2c_start();
    i2c_write(8'hA0, ack);  check("write addr ack", {7'b0, ack}, 8'h00);
    i2c_write(8'h5A, ack);  check("write data ack", {7'b0, ack}, 8'h00);
    check("slave memory", mem, 8'h5A);
    i2c_start();                                   // repeated START
    i2c_write(8'hA1, ack);  check("read addr ack", {7'b0, ack}, 8'h00);
    i2c_read(0, rd);        check("read byte 1 (ACK)", rd, 8'h3C);
    i2c_read(1, rd);        check("read byte 2 (NACK)", rd, 8'hC3);
    i2c_stop();

    i2c_start();
    i2c_write(8'hA4, ack);  check("wrong addr nack", {7'b0, ack}, 8'h01);
    i2c_stop();

    repeat (100) @(posedge clk);
    if (errors == 0) $display("TB_CORE_I2C PASS");
    else             $display("TB_CORE_I2C FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #2ms;
    $display("TB_CORE_I2C FAIL: timeout");
    $finish;
  end
endmodule
