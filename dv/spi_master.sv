`timescale 1ns/1ps
// SPI master: 8-bit transfer, MSB first, all four modes via CPOL/CPHA.
// CLK_DIV = system clocks per half SCK period (use >= 3, miso goes through a 2-FF synchronizer).
module spi_master #(
  parameter bit CPOL    = 1'b0,
  parameter bit CPHA    = 1'b0,
  parameter int CLK_DIV = 4
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       start,
  input  logic [7:0] tx_data,
  output logic [7:0] rx_data,
  output logic       busy,
  output logic       done,
  output logic       sck,
  output logic       mosi,
  output logic       cs_n,
  input  logic       miso
);
  typedef enum logic [1:0] {IDLE, RUN, FINISH} state_t;

  state_t      state;
  logic [15:0] div_cnt;
  logic [3:0]  edge_cnt;
  logic [7:0]  tx_sh, rx_sh;
  logic        miso_meta, miso_s;

  wire       tick        = (div_cnt == CLK_DIV-1);
  wire       leading     = ~edge_cnt[0];
  wire       sample_now  = CPHA ? ~leading : leading;
  wire       shift_now   = CPHA ? (leading && edge_cnt != 4'd0) : ~leading;
  wire [7:0] rx_next     = {rx_sh[6:0], miso_s};

  assign mosi = tx_sh[7];

  always_ff @(posedge clk) begin
    miso_meta <= miso;
    miso_s    <= miso_meta;
  end

  always_ff @(posedge clk) begin
    done <= 1'b0;
    if (!rst_n) begin
      state    <= IDLE;
      sck      <= CPOL;
      cs_n     <= 1'b1;
      busy     <= 1'b0;
      div_cnt  <= '0;
      edge_cnt <= '0;
      tx_sh    <= '0;
      rx_sh    <= '0;
      rx_data  <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (start) begin
            tx_sh    <= tx_data;
            rx_sh    <= '0;
            cs_n     <= 1'b0;
            busy     <= 1'b1;
            div_cnt  <= '0;
            edge_cnt <= '0;
            state    <= RUN;
          end
        end

        RUN: begin
          if (tick) begin
            div_cnt  <= '0;
            sck      <= ~sck;
            edge_cnt <= edge_cnt + 1'b1;
            if (sample_now) rx_sh <= rx_next;
            if (shift_now)  tx_sh <= {tx_sh[6:0], 1'b0};
            if (edge_cnt == 4'd15) begin
              rx_data <= sample_now ? rx_next : rx_sh;
              state   <= FINISH;
            end
          end else div_cnt <= div_cnt + 1'b1;
        end

        FINISH: begin
          if (tick) begin
            div_cnt <= '0;
            cs_n    <= 1'b1;
            busy    <= 1'b0;
            done    <= 1'b1;
            state   <= IDLE;
          end else div_cnt <= div_cnt + 1'b1;
        end
      endcase
    end
  end
endmodule
