/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// Tiny Tapeout top level: programmable protocol emulator.
//   ui_in[0] = host SDI, ui_in[1] = host SCK, ui_in[2] = host CS_n   (SPI slave, mode 0)
//   uo_out[0] = host SDO, [1] = halted, [2] = rx_empty, [3] = tx_full, [4] = run
//   uio[7:0]  = the eight emulator pins (output, output enable and input per pin)
module tt_um_sreeharshams_protocol_emulator (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
  wire        run, prog_we, tx_wr, rx_rd;
  wire [5:0]  prog_addr;
  wire [15:0] prog_data;
  wire [7:0]  tx_wdata, rx_rdata;
  wire        tx_full, rx_empty, halted, sdo;

  host_if u_host (
      .clk(clk), .rst_n(rst_n),
      .sdi(ui_in[0]), .sck(ui_in[1]), .cs_n(ui_in[2]), .sdo(sdo),
      .run(run),
      .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
      .tx_wr(tx_wr), .tx_wdata(tx_wdata),
      .rx_rd(rx_rd), .rx_rdata(rx_rdata), .rx_empty(rx_empty),
      .tx_full(tx_full), .halted(halted));

  emu_core #(.PIN_OUT_RESET(8'hFC), .PIN_OE_RESET(8'h00)) u_core (
      .clk(clk), .rst_n(rst_n), .run(run),
      .prog_we(prog_we), .prog_addr(prog_addr), .prog_data(prog_data),
      .tx_wr(tx_wr), .tx_wdata(tx_wdata), .tx_full(tx_full),
      .rx_rd(rx_rd), .rx_rdata(rx_rdata), .rx_empty(rx_empty),
      .pin_in(uio_in), .pin_out(uio_out), .pin_oe(uio_oe), .halted(halted));

  assign uo_out = {3'b000, run, tx_full, rx_empty, halted, sdo};

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], 1'b0};
endmodule

`default_nettype wire
