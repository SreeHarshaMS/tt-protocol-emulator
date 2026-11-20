`timescale 1ns/1ps
// Firmware images for the emulator core, built with the encoders in emu_isa_pkg.
// Both programs leave the unused program words as NOP.
package emu_fw_pkg;
  import emu_isa_pkg::*;

  typedef logic [15:0] prog_t [64];

  task automatic emit(ref prog_t p, ref int n, input logic [15:0] w);
    if (n < 64) p[n] = w;
    n++;
  endtask

  // UART transmitter on pin 0, 8N1, 16 clocks per bit. Host: push one byte per frame.
  task automatic fw_uart_tx(output prog_t p, output int n);
    n = 0;
    foreach (p[i]) p[i] = i_nop();
    emit(p, n, i_set(0, 1));
    emit(p, n, i_oe(0, 1));
    emit(p, n, i_pull());
    emit(p, n, i_loadx(7));
    emit(p, n, i_set(0, 0));          // start bit
    emit(p, n, i_wait(14));
    emit(p, n, i_out(0, 0));          // data bit, LSB first
    emit(p, n, i_wait(13));
    emit(p, n, i_djnz(6));
    emit(p, n, i_set(0, 1));          // stop bit
    emit(p, n, i_wait(14));
    emit(p, n, i_jmp(2));
  endtask

  task automatic emit_pulse(ref prog_t p, ref int n, input int q);
    logic [5:0] a;
    emit(p, n, i_oe(0, 0));
    a = n[5:0];
    emit(p, n, i_jpin(0, 0, a));      // wait while SCL is held low (clock stretching)
    emit(p, n, i_wait(q[11:0]));
  endtask

  // I2C master on pins 0 (SCL) and 1 (SDA); needs pin_out[1:0] to reset to 0.
  //   Host sends a command byte: 0 START | 1 WRITE + data | 2 READ + flag (0 ACK, 1 NACK) | 3 STOP
  //   WRITE replies with a byte whose bit 0 is the ack bit, READ replies with the byte read.
  task automatic fw_i2c(output prog_t p, output int n, input int q);
    int l_main, l_start, l_write, l_read, l_stop;
    int j_start, j_write, j_read, j_stop, bl;
    logic [5:0] a;
    n = 0;
    foreach (p[i]) p[i] = i_nop();

    l_main = n;
    emit(p, n, i_pull());
    emit(p, n, i_outx());
    a = n[5:0] + 6'd2;  emit(p, n, i_djnz(a));  j_start = n;  emit(p, n, i_jmp(0));
    a = n[5:0] + 6'd2;  emit(p, n, i_djnz(a));  j_write = n;  emit(p, n, i_jmp(0));
    a = n[5:0] + 6'd2;  emit(p, n, i_djnz(a));  j_read  = n;  emit(p, n, i_jmp(0));
    a = l_main[5:0];    emit(p, n, i_djnz(a));  j_stop  = n;  emit(p, n, i_jmp(0));

    l_start = n;
    emit(p, n, i_oe(1, 0));  emit(p, n, i_wait(q[11:0]));
    emit_pulse(p, n, q);
    emit(p, n, i_oe(1, 1));  emit(p, n, i_wait(q[11:0]));
    emit(p, n, i_oe(0, 1));
    a = l_main[5:0];    emit(p, n, i_jmp(a));

    l_write = n;
    emit(p, n, i_pull());
    emit(p, n, i_loadx(7));
    bl = n;
    emit(p, n, i_outd(1, 1));  emit(p, n, i_wait(q[11:0]));
    emit_pulse(p, n, q);
    emit(p, n, i_oe(0, 1));
    a = bl[5:0];        emit(p, n, i_djnz(a));
    emit(p, n, i_oe(1, 0));  emit(p, n, i_wait(q[11:0]));
    emit(p, n, i_oe(0, 0));
    a = n[5:0];         emit(p, n, i_jpin(0, 0, a));
    emit(p, n, i_wait(q[11:0]));
    emit(p, n, i_in(1, 1));
    emit(p, n, i_oe(0, 1));
    emit(p, n, i_push());
    a = l_main[5:0];    emit(p, n, i_jmp(a));

    l_read = n;
    emit(p, n, i_pull());
    emit(p, n, i_oe(1, 0));
    emit(p, n, i_loadx(7));
    bl = n;
    emit(p, n, i_wait(q[11:0]));
    emit(p, n, i_oe(0, 0));
    a = n[5:0];         emit(p, n, i_jpin(0, 0, a));
    emit(p, n, i_wait(q[11:0]));
    emit(p, n, i_in(1, 1));
    emit(p, n, i_oe(0, 1));
    a = bl[5:0];        emit(p, n, i_djnz(a));
    emit(p, n, i_outd(1, 0));
    emit(p, n, i_wait(q[11:0]));
    emit_pulse(p, n, q);
    emit(p, n, i_oe(0, 1));
    emit(p, n, i_oe(1, 0));
    emit(p, n, i_push());
    a = l_main[5:0];    emit(p, n, i_jmp(a));

    l_stop = n;
    emit(p, n, i_oe(1, 1));  emit(p, n, i_wait(q[11:0]));
    emit_pulse(p, n, q);
    emit(p, n, i_oe(1, 0));
    a = l_main[5:0];    emit(p, n, i_jmp(a));

    a = l_start[5:0];   p[j_start] = i_jmp(a);
    a = l_write[5:0];   p[j_write] = i_jmp(a);
    a = l_read[5:0];    p[j_read]  = i_jmp(a);
    a = l_stop[5:0];    p[j_stop]  = i_jmp(a);
  endtask
endpackage
