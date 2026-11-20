/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// Programmable pin-I/O core: runs firmware that bit-bangs protocols with cycle-exact timing.
// Program memory is written through prog_* (any time, normally while run = 0). The host talks to the
// firmware through a TX FIFO (host -> core, read by PULL) and an RX FIFO (core -> host, written by PUSH).
//
// 16-bit instructions, [15:12] = opcode (encoders live in dv/emu_isa_pkg.sv):
//   SET   pin,val   [3] val, [2:0] pin        drive the output register of a pin
//   OE    pin,en    [3] en,  [2:0] pin        output enable of a pin
//   WAIT  n         [11:0] n                  stall n extra cycles (instruction takes n+1 cycles)
//   LOADX v         [7:0] v                   X = v
//   DJNZ  addr      [5:0] addr                if X != 0 then X--, jump
//   JMP   addr      [5:0] addr
//   JPIN  pin,pol,a [9] pol, [8:6] pin, [5:0] addr   jump if the synchronised input pin == pol
//   OUT   pin,msb   [3] msb, [2:0] pin        pin = OSR bit, shift OSR (msb = 0: LSB first)
//   OUTD  pin,msb   [3] msb, [2:0] pin        open drain: pin_oe = ~OSR bit, shift OSR
//   OUTX                                      X = OSR
//   IN    pin,msb   [3] msb, [2:0] pin        shift the pin into ISR (msb = 0: LSB-first order)
//   PULL                                      OSR = TX FIFO (blocks while empty)
//   PUSH                                      RX FIFO = ISR (blocks while full)
//   HALT
module emu_core #(
    parameter [7:0] PIN_OUT_RESET = 8'hFF,
    parameter [7:0] PIN_OE_RESET  = 8'h00
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        run,

    input  wire        prog_we,
    input  wire [5:0]  prog_addr,
    input  wire [15:0] prog_data,

    input  wire        tx_wr,
    input  wire [7:0]  tx_wdata,
    output wire        tx_full,
    input  wire        rx_rd,
    output wire [7:0]  rx_rdata,
    output wire        rx_empty,

    input  wire [7:0]  pin_in,
    output reg  [7:0]  pin_out,
    output reg  [7:0]  pin_oe,
    output reg         halted
);
  localparam [3:0] OP_NOP   = 4'h0;
  localparam [3:0] OP_SET   = 4'h1;
  localparam [3:0] OP_WAIT  = 4'h2;
  localparam [3:0] OP_LOADX = 4'h3;
  localparam [3:0] OP_DJNZ  = 4'h4;
  localparam [3:0] OP_JMP   = 4'h5;
  localparam [3:0] OP_JPIN  = 4'h6;
  localparam [3:0] OP_OUT   = 4'h7;
  localparam [3:0] OP_IN    = 4'h8;
  localparam [3:0] OP_PULL  = 4'h9;
  localparam [3:0] OP_PUSH  = 4'hA;
  localparam [3:0] OP_OE    = 4'hB;
  localparam [3:0] OP_OUTX  = 4'hC;
  localparam [3:0] OP_OUTD  = 4'hD;
  localparam [3:0] OP_HALT  = 4'hF;

  (* ram_style = "registers" *) reg [15:0] prog_mem[0:63];
  reg [5:0]  pc;
  reg [7:0]  x, osr, isr;
  reg [11:0] wait_cnt;
  reg        wait_active;
  reg [7:0]  pin_meta, pin_s;

  wire [15:0] instr = prog_mem[pc];
  wire [3:0]  op    = instr[15:12];
  wire [2:0]  pin   = instr[2:0];
  wire        flag  = instr[3];
  wire [5:0]  addr  = instr[5:0];
  wire [2:0]  jpin  = instr[8:6];
  wire        pol   = instr[9];
  wire [11:0] n     = instr[11:0];
  wire [7:0]  imm   = instr[7:0];

  wire        tx_empty, rx_full;
  wire [7:0]  tx_rdata;

  wire active  = run && !halted && !wait_active;
  wire tx_pop  = active && (op == OP_PULL) && !tx_empty;
  wire rx_push = active && (op == OP_PUSH) && !rx_full;

  sync_fifo #(.WIDTH(8), .DEPTH_LOG2(2)) u_tx_fifo (
      .clk(clk), .rst_n(rst_n),
      .wr(tx_wr), .wdata(tx_wdata), .full(tx_full),
      .rd(tx_pop), .rdata(tx_rdata), .empty(tx_empty));

  sync_fifo #(.WIDTH(8), .DEPTH_LOG2(2)) u_rx_fifo (
      .clk(clk), .rst_n(rst_n),
      .wr(rx_push), .wdata(isr), .full(rx_full),
      .rd(rx_rd), .rdata(rx_rdata), .empty(rx_empty));

  always @(posedge clk) begin
    if (prog_we) prog_mem[prog_addr] <= prog_data;
  end

  always @(posedge clk) begin
    pin_meta <= pin_in;
    pin_s    <= pin_meta;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      pc          <= 6'd0;
      x           <= 8'd0;
      osr         <= 8'd0;
      isr         <= 8'd0;
      wait_cnt    <= 12'd0;
      wait_active <= 1'b0;
      pin_out     <= PIN_OUT_RESET;
      pin_oe      <= PIN_OE_RESET;
      halted      <= 1'b0;
    end else if (run && !halted) begin
      if (wait_active) begin
        if (wait_cnt == 12'd0) begin
          wait_active <= 1'b0;
          pc          <= pc + 6'd1;
        end else begin
          wait_cnt <= wait_cnt - 12'd1;
        end
      end else begin
        case (op)
          OP_SET: begin
            pin_out[pin] <= flag;
            pc           <= pc + 6'd1;
          end
          OP_OE: begin
            pin_oe[pin] <= flag;
            pc          <= pc + 6'd1;
          end
          OP_WAIT: begin
            if (n == 12'd0) begin
              pc <= pc + 6'd1;
            end else begin
              wait_cnt    <= n - 12'd1;
              wait_active <= 1'b1;
            end
          end
          OP_LOADX: begin
            x  <= imm;
            pc <= pc + 6'd1;
          end
          OP_DJNZ: begin
            if (x != 8'd0) begin
              x  <= x - 8'd1;
              pc <= addr;
            end else begin
              pc <= pc + 6'd1;
            end
          end
          OP_JMP: pc <= addr;
          OP_JPIN: begin
            if (pin_s[jpin] == pol) pc <= addr;
            else pc <= pc + 6'd1;
          end
          OP_OUT: begin
            pin_out[pin] <= flag ? osr[7] : osr[0];
            osr          <= flag ? {osr[6:0], 1'b0} : {1'b0, osr[7:1]};
            pc           <= pc + 6'd1;
          end
          OP_OUTD: begin
            pin_oe[pin] <= ~(flag ? osr[7] : osr[0]);
            osr         <= flag ? {osr[6:0], 1'b0} : {1'b0, osr[7:1]};
            pc          <= pc + 6'd1;
          end
          OP_OUTX: begin
            x  <= osr;
            pc <= pc + 6'd1;
          end
          OP_IN: begin
            isr <= flag ? {isr[6:0], pin_s[pin]} : {pin_s[pin], isr[7:1]};
            pc  <= pc + 6'd1;
          end
          OP_PULL: begin
            if (!tx_empty) begin
              osr <= tx_rdata;
              pc  <= pc + 6'd1;
            end
          end
          OP_PUSH: begin
            if (!rx_full) pc <= pc + 6'd1;
          end
          OP_HALT: halted <= 1'b1;
          default: pc <= pc + 6'd1;
        endcase
      end
    end
  end
endmodule

`default_nettype wire
