`timescale 1ns/1ps
// Instruction set of the protocol-emulator core, plus encoder functions used as a tiny assembler.
// 16-bit instructions: [15:12] opcode, the rest depends on the opcode.
//   SET   pin,val   : [3] val, [2:0] pin        drive output register of a pin
//   OE    pin,en    : [3] en,  [2:0] pin        output enable of a pin
//   WAIT  n         : [11:0] n                  stall n extra cycles (instruction takes n+1 cycles)
//   LOADX v         : [7:0] v                   X = v
//   DJNZ  addr      : [5:0] addr                if X != 0 then X--, jump
//   JMP   addr      : [5:0] addr
//   JPIN  pin,pol,a : [9] pol, [8:6] pin, [5:0] addr   jump if input pin == pol
//   OUT   pin,msb   : [3] msb, [2:0] pin        pin = OSR bit, shift OSR (msb=0: LSB first)
//   IN    pin,msb   : [3] msb, [2:0] pin        shift pin into ISR (msb=0: LSB-first order)
//   OUTD  pin,msb   : [3] msb, [2:0] pin        open-drain OUT: pin_oe = ~OSR bit (0 pulls low, 1 releases), shift OSR
//   OUTX            : X = OSR (lets firmware dispatch on a host command)
//   PULL            : OSR = TX FIFO (blocks while empty)
//   PUSH            : RX FIFO = ISR (blocks while full)
//   HALT
// Every instruction takes 1 cycle except WAIT (n+1) and blocking PULL/PUSH.
package emu_isa_pkg;
  localparam logic [3:0] OP_NOP   = 4'h0;
  localparam logic [3:0] OP_SET   = 4'h1;
  localparam logic [3:0] OP_WAIT  = 4'h2;
  localparam logic [3:0] OP_LOADX = 4'h3;
  localparam logic [3:0] OP_DJNZ  = 4'h4;
  localparam logic [3:0] OP_JMP   = 4'h5;
  localparam logic [3:0] OP_JPIN  = 4'h6;
  localparam logic [3:0] OP_OUT   = 4'h7;
  localparam logic [3:0] OP_IN    = 4'h8;
  localparam logic [3:0] OP_PULL  = 4'h9;
  localparam logic [3:0] OP_PUSH  = 4'hA;
  localparam logic [3:0] OP_OE    = 4'hB;
  localparam logic [3:0] OP_OUTX  = 4'hC;
  localparam logic [3:0] OP_OUTD  = 4'hD;
  localparam logic [3:0] OP_HALT  = 4'hF;

  function automatic logic [15:0] i_nop();
    return {OP_NOP, 12'd0};
  endfunction
  function automatic logic [15:0] i_set(input logic [2:0] pin, input logic val);
    return {OP_SET, 8'd0, val, pin};
  endfunction
  function automatic logic [15:0] i_oe(input logic [2:0] pin, input logic en);
    return {OP_OE, 8'd0, en, pin};
  endfunction
  function automatic logic [15:0] i_wait(input logic [11:0] n);
    return {OP_WAIT, n};
  endfunction
  function automatic logic [15:0] i_loadx(input logic [7:0] v);
    return {OP_LOADX, 4'd0, v};
  endfunction
  function automatic logic [15:0] i_djnz(input logic [5:0] addr);
    return {OP_DJNZ, 6'd0, addr};
  endfunction
  function automatic logic [15:0] i_jmp(input logic [5:0] addr);
    return {OP_JMP, 6'd0, addr};
  endfunction
  function automatic logic [15:0] i_jpin(input logic [2:0] pin, input logic pol, input logic [5:0] addr);
    return {OP_JPIN, 2'd0, pol, pin, addr};
  endfunction
  function automatic logic [15:0] i_out(input logic [2:0] pin, input logic msb);
    return {OP_OUT, 8'd0, msb, pin};
  endfunction
  function automatic logic [15:0] i_in(input logic [2:0] pin, input logic msb);
    return {OP_IN, 8'd0, msb, pin};
  endfunction
  function automatic logic [15:0] i_pull();
    return {OP_PULL, 12'd0};
  endfunction
  function automatic logic [15:0] i_push();
    return {OP_PUSH, 12'd0};
  endfunction
  function automatic logic [15:0] i_outx();
    return {OP_OUTX, 12'd0};
  endfunction
  function automatic logic [15:0] i_outd(input logic [2:0] pin, input logic msb);
    return {OP_OUTD, 8'd0, msb, pin};
  endfunction
  function automatic logic [15:0] i_halt();
    return {OP_HALT, 12'd0};
  endfunction
endpackage
