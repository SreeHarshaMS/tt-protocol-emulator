`timescale 1ns/1ps
// Behavioural I2C slave (testbench only) at address ADDR.
// Stores the byte written to it in mem and returns 3C, C3, 3C, ... on reads.
module i2c_slave_model #(
  parameter logic [6:0] ADDR = 7'h50
) (
  input  logic       scl_line,
  input  logic       sda_line,
  output logic       slv_sda_oe,
  output logic [7:0] mem
);
  int         mode = 0, cnt = 0;
  logic       rw, mnack;
  logic [7:0] sh, txb;

  initial begin
    slv_sda_oe = 1'b0;
    mem        = 8'h00;
  end

  always @(negedge sda_line) if (scl_line) begin mode = 1; cnt = 0; sh = 0; slv_sda_oe = 0; end
  always @(posedge sda_line) if (scl_line) begin mode = 0; slv_sda_oe = 0; end

  always @(posedge scl_line) begin
    case (mode)
      1, 2: begin if (cnt < 8) sh = {sh[6:0], sda_line}; cnt++; end
      3:    begin if (cnt == 8) mnack = sda_line; cnt++; end
      default: ;
    endcase
  end

  always @(negedge scl_line) begin
    case (mode)
      1: if (cnt == 8) begin
           if (sh[7:1] == ADDR) begin slv_sda_oe = 1; rw = sh[0]; end
           else mode = 0;
         end else if (cnt == 9) begin
           slv_sda_oe = 0; cnt = 0; sh = 0;
           if (rw) begin mode = 3; txb = 8'h3C; slv_sda_oe = ~txb[7]; end
           else mode = 2;
         end
      2: if (cnt == 8) begin slv_sda_oe = 1; mem = sh; end
         else if (cnt == 9) begin slv_sda_oe = 0; cnt = 0; sh = 0; end
      3: if (cnt < 8) slv_sda_oe = ~txb[7-cnt];
         else if (cnt == 8) slv_sda_oe = 0;
         else if (cnt == 9) begin
           if (mnack) mode = 0;
           else begin cnt = 0; txb = ~txb; slv_sda_oe = ~txb[7]; end
         end
      default: ;
    endcase
  end
endmodule
