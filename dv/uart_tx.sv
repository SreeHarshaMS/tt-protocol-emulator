`timescale 1ns/1ps
// UART transmitter: 8N1, LSB first. start is accepted only while busy is low.
module uart_tx #(
  parameter int CLKS_PER_BIT = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [7:0] data,
  output logic       tx,
  output logic       busy
);
  typedef enum logic [1:0] {IDLE, START_BIT, DATA_BITS, STOP_BIT} state_t;

  state_t      state;
  logic [15:0] cnt;
  logic [2:0]  bit_idx;
  logic [7:0]  shreg;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      state   <= IDLE;
      tx      <= 1'b1;
      busy    <= 1'b0;
      cnt     <= '0;
      bit_idx <= '0;
      shreg   <= '0;
    end else begin
      case (state)
        IDLE: begin
          tx <= 1'b1;
          if (start) begin
            shreg <= data;
            busy  <= 1'b1;
            cnt   <= '0;
            tx    <= 1'b0;
            state <= START_BIT;
          end
        end

        START_BIT: begin
          if (cnt == CLKS_PER_BIT-1) begin
            cnt     <= '0;
            bit_idx <= '0;
            tx      <= shreg[0];
            state   <= DATA_BITS;
          end else cnt <= cnt + 1'b1;
        end

        DATA_BITS: begin
          if (cnt == CLKS_PER_BIT-1) begin
            cnt <= '0;
            if (bit_idx == 3'd7) begin
              tx    <= 1'b1;
              state <= STOP_BIT;
            end else begin
              bit_idx <= bit_idx + 1'b1;
              tx      <= shreg[bit_idx + 1'b1];
            end
          end else cnt <= cnt + 1'b1;
        end

        STOP_BIT: begin
          if (cnt == CLKS_PER_BIT-1) begin
            cnt   <= '0;
            busy  <= 1'b0;
            state <= IDLE;
          end else cnt <= cnt + 1'b1;
        end
      endcase
    end
  end
endmodule
