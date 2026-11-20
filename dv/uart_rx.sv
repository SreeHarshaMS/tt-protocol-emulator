`timescale 1ns/1ps
// UART receiver: 8N1, LSB first. Samples each bit at its midpoint.
// valid pulses for one clock with data; frame_err is set if the stop bit was low.
module uart_rx #(
  parameter int CLKS_PER_BIT = 16
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       rx,
  output logic [7:0] data,
  output logic       valid,
  output logic       frame_err
);
  typedef enum logic [1:0] {IDLE, START_BIT, DATA_BITS, STOP_BIT} state_t;

  state_t      state;
  logic [15:0] cnt;
  logic [2:0]  bit_idx;
  logic [7:0]  shreg;
  logic        rx_meta, rx_s;

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      rx_meta <= 1'b1;
      rx_s    <= 1'b1;
    end else begin
      rx_meta <= rx;
      rx_s    <= rx_meta;
    end
  end

  always_ff @(posedge clk) begin
    valid <= 1'b0;
    if (!rst_n) begin
      state     <= IDLE;
      cnt       <= '0;
      bit_idx   <= '0;
      shreg     <= '0;
      data      <= '0;
      frame_err <= 1'b0;
    end else begin
      case (state)
        IDLE: begin
          cnt <= '0;
          if (!rx_s) state <= START_BIT;
        end

        START_BIT: begin
          if (cnt == (CLKS_PER_BIT/2)-1) begin
            cnt <= '0;
            if (!rx_s) begin
              bit_idx <= '0;
              state   <= DATA_BITS;
            end else state <= IDLE;
          end else cnt <= cnt + 1'b1;
        end

        DATA_BITS: begin
          if (cnt == CLKS_PER_BIT-1) begin
            cnt   <= '0;
            shreg <= {rx_s, shreg[7:1]};
            if (bit_idx == 3'd7) state <= STOP_BIT;
            else bit_idx <= bit_idx + 1'b1;
          end else cnt <= cnt + 1'b1;
        end

        STOP_BIT: begin
          if (cnt == CLKS_PER_BIT-1) begin
            cnt       <= '0;
            data      <= shreg;
            valid     <= 1'b1;
            frame_err <= ~rx_s;
            state     <= IDLE;
          end else cnt <= cnt + 1'b1;
        end
      endcase
    end
  end
endmodule
