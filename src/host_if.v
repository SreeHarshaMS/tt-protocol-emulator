/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// Host interface: an SPI slave (mode 0, MSB first, byte oriented) that loads the program, starts/stops
// the core, and moves bytes through the core's FIFOs. SCK must be at most clk/4.
//   Each transaction is one chip-select low period; the first byte is the command:
//     01 aa hh ll : write program word hh/ll at address aa
//     02 rr       : rr[0] = run
//     03 dd       : push byte dd into the TX FIFO (read by the firmware's PULL)
//     04 xx       : pop the RX FIFO; the byte shifted out during xx is the data (00 if empty)
//     05 xx       : status shifted out during xx = {4'b0, halted, run, rx_empty, tx_full}
module host_if (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        sdi,
    input  wire        sck,
    input  wire        cs_n,
    output wire        sdo,

    output reg         run,
    output reg         prog_we,
    output reg  [5:0]  prog_addr,
    output reg  [15:0] prog_data,
    output reg         tx_wr,
    output reg  [7:0]  tx_wdata,
    output reg         rx_rd,
    input  wire [7:0]  rx_rdata,
    input  wire        rx_empty,
    input  wire        tx_full,
    input  wire        halted
);
  localparam [2:0] S_CMD = 3'd0, S_ADDR = 3'd1, S_HI = 3'd2, S_LO = 3'd3,
                   S_RUN = 3'd4, S_PUSH = 3'd5, S_SHIFT = 3'd6;

  reg [2:0] state;
  reg [2:0] bitcnt;
  reg [7:0] rx_sr, tx_sr, hi_r;
  reg [5:0] addr_r;
  reg       sdi_m, sdi_s, sck_m, sck_s, sck_d, cs_m, cs_s;
  reg       skip_fall;  // the SCK fall that ends a command byte must not shift out the freshly loaded byte

  wire       rise    = sck_s & ~sck_d;
  wire       fall    = ~sck_s & sck_d;
  wire [7:0] byte_in = {rx_sr[6:0], sdi_s};

  assign sdo = tx_sr[7];

  always @(posedge clk) begin
    if (!rst_n) begin
      sdi_m <= 1'b0; sdi_s <= 1'b0;
      sck_m <= 1'b0; sck_s <= 1'b0; sck_d <= 1'b0;
      cs_m  <= 1'b1; cs_s  <= 1'b1;
    end else begin
      sdi_m <= sdi;  sdi_s <= sdi_m;
      sck_m <= sck;  sck_s <= sck_m;  sck_d <= sck_s;
      cs_m  <= cs_n; cs_s  <= cs_m;
    end
  end

  always @(posedge clk) begin
    prog_we <= 1'b0;
    tx_wr   <= 1'b0;
    rx_rd   <= 1'b0;
    if (!rst_n) begin
      run       <= 1'b0;
      state     <= S_CMD;
      bitcnt    <= 3'd0;
      rx_sr     <= 8'd0;
      tx_sr     <= 8'd0;
      hi_r      <= 8'd0;
      addr_r    <= 6'd0;
      prog_addr <= 6'd0;
      prog_data <= 16'd0;
      tx_wdata  <= 8'd0;
      skip_fall <= 1'b0;
    end else if (cs_s) begin
      state     <= S_CMD;
      bitcnt    <= 3'd0;
      tx_sr     <= 8'd0;
      skip_fall <= 1'b0;
    end else begin
      if (fall) begin
        if (skip_fall) skip_fall <= 1'b0;
        else           tx_sr <= {tx_sr[6:0], 1'b0};
      end
      if (rise) begin
        rx_sr  <= byte_in;
        bitcnt <= bitcnt + 3'd1;
        if (bitcnt == 3'd7) begin
          case (state)
            S_CMD: begin
              case (byte_in)
                8'h01: state <= S_ADDR;
                8'h02: state <= S_RUN;
                8'h03: state <= S_PUSH;
                8'h04: begin
                  tx_sr     <= rx_empty ? 8'h00 : rx_rdata;
                  rx_rd     <= ~rx_empty;
                  skip_fall <= 1'b1;
                  state     <= S_SHIFT;
                end
                8'h05: begin
                  tx_sr     <= {4'b0000, halted, run, rx_empty, tx_full};
                  skip_fall <= 1'b1;
                  state     <= S_SHIFT;
                end
                default: state <= S_CMD;
              endcase
            end
            S_ADDR: begin
              addr_r <= byte_in[5:0];
              state  <= S_HI;
            end
            S_HI: begin
              hi_r  <= byte_in;
              state <= S_LO;
            end
            S_LO: begin
              prog_addr <= addr_r;
              prog_data <= {hi_r, byte_in};
              prog_we   <= 1'b1;
              state     <= S_CMD;
            end
            S_RUN: begin
              run   <= byte_in[0];
              state <= S_CMD;
            end
            S_PUSH: begin
              tx_wdata <= byte_in;
              tx_wr    <= 1'b1;
              state    <= S_CMD;
            end
            S_SHIFT: state <= S_CMD;
            default: state <= S_CMD;
          endcase
        end
      end
    end
  end
endmodule

`default_nettype wire
