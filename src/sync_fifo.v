/*
 * Copyright (c) 2026
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

// Small synchronous FIFO, show-ahead read (rdata is valid whenever empty is low).
module sync_fifo #(
    parameter WIDTH      = 8,
    parameter DEPTH_LOG2 = 2
) (
    input  wire             clk,
    input  wire             rst_n,
    input  wire             wr,
    input  wire [WIDTH-1:0] wdata,
    output wire             full,
    input  wire             rd,
    output wire [WIDTH-1:0] rdata,
    output wire             empty
);
  localparam DEPTH = 1 << DEPTH_LOG2;

  (* ram_style = "registers" *) reg [WIDTH-1:0] mem[0:DEPTH-1];
  reg [DEPTH_LOG2-1:0] wp, rp;
  reg [DEPTH_LOG2:0]   count;

  wire do_wr = wr && !full;
  wire do_rd = rd && !empty;

  assign full  = (count == DEPTH);
  assign empty = (count == 0);
  assign rdata = mem[rp];

  always @(posedge clk) begin
    if (!rst_n) begin
      wp    <= 0;
      rp    <= 0;
      count <= 0;
    end else begin
      if (do_wr) begin
        mem[wp] <= wdata;
        wp      <= wp + 1'b1;
      end
      if (do_rd) rp <= rp + 1'b1;
      count <= count + (do_wr ? 1 : 0) - (do_rd ? 1 : 0);
    end
  end
endmodule

`default_nettype wire
