`timescale 1ns/1ps
// I2C master, byte-level commands: START, WRITE, READ, STOP.
// Open-drain: scl_oe/sda_oe = 1 pulls the line low, 0 releases it (external pull-up).
// SCL frequency = clk / (4 * CLK_DIV). Use CLK_DIV >= 4. Supports clock stretching.
//   CMD_WRITE: sends tx_byte, then slave_nack = 1 if the slave did not acknowledge.
//   CMD_READ : returns rx_byte, then sends ACK when nack_in = 0, NACK when nack_in = 1.
module i2c_master #(
  parameter int CLK_DIV = 4
) (
  input  logic       clk,
  input  logic       rst_n,
  input  logic       cmd_valid,
  input  logic [1:0] cmd,
  input  logic [7:0] tx_byte,
  input  logic       nack_in,
  output logic       busy,
  output logic       done,
  output logic [7:0] rx_byte,
  output logic       slave_nack,
  input  logic       scl_i,
  input  logic       sda_i,
  output logic       scl_oe,
  output logic       sda_oe
);
  localparam logic [1:0] CMD_START = 2'd0;
  localparam logic [1:0] CMD_WRITE = 2'd1;
  localparam logic [1:0] CMD_READ  = 2'd2;
  localparam logic [1:0] CMD_STOP  = 2'd3;

  typedef enum logic {IDLE, RUN} state_t;

  state_t      state;
  logic [1:0]  cmd_r;
  logic [1:0]  q;
  logic [3:0]  bitn;
  logic [15:0] div_cnt;
  logic [7:0]  sh, rx_sh;
  logic        nack_r;
  logic        scl_meta, scl_s, sda_meta, sda_s;

  wire tick = (div_cnt == CLK_DIV-1);

  always_ff @(posedge clk) begin
    scl_meta <= scl_i;
    scl_s    <= scl_meta;
    sda_meta <= sda_i;
    sda_s    <= sda_meta;
  end

  always_ff @(posedge clk) begin
    done <= 1'b0;
    if (!rst_n) begin
      state      <= IDLE;
      scl_oe     <= 1'b0;
      sda_oe     <= 1'b0;
      busy       <= 1'b0;
      slave_nack <= 1'b0;
      rx_byte    <= '0;
      rx_sh      <= '0;
      sh         <= '0;
      cmd_r      <= '0;
      nack_r     <= 1'b0;
      q          <= '0;
      bitn       <= '0;
      div_cnt    <= '0;
    end else begin
      case (state)
        IDLE: begin
          if (cmd_valid) begin
            cmd_r   <= cmd;
            sh      <= tx_byte;
            nack_r  <= nack_in;
            q       <= '0;
            bitn    <= '0;
            div_cnt <= '0;
            busy    <= 1'b1;
            state   <= RUN;
          end
        end

        RUN: begin
          if (!tick) div_cnt <= div_cnt + 1'b1;
          else begin
            div_cnt <= '0;
            case (q)
              2'd0: begin
                case (cmd_r)
                  CMD_START: sda_oe <= 1'b0;
                  CMD_STOP:  sda_oe <= 1'b1;
                  CMD_WRITE: sda_oe <= (bitn < 4'd8) ? ~sh[7] : 1'b0;
                  CMD_READ:  sda_oe <= (bitn < 4'd8) ? 1'b0 : ~nack_r;
                endcase
                q <= 2'd1;
              end

              2'd1: begin
                scl_oe <= 1'b0;
                q      <= 2'd2;
              end

              2'd2: begin
                if (scl_s) begin
                  case (cmd_r)
                    CMD_START: sda_oe <= 1'b1;
                    CMD_STOP:  sda_oe <= 1'b0;
                    CMD_WRITE: if (bitn == 4'd8) slave_nack <= sda_s;
                    CMD_READ:  if (bitn < 4'd8) rx_sh <= {rx_sh[6:0], sda_s};
                  endcase
                  q <= 2'd3;
                end
              end

              2'd3: begin
                q <= 2'd0;
                case (cmd_r)
                  CMD_START: begin
                    scl_oe <= 1'b1;
                    busy   <= 1'b0;
                    done   <= 1'b1;
                    state  <= IDLE;
                  end
                  CMD_STOP: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                  end
                  default: begin
                    scl_oe <= 1'b1;
                    if (bitn < 4'd8) sh <= {sh[6:0], 1'b0};
                    if (bitn == 4'd8) begin
                      rx_byte <= rx_sh;
                      busy    <= 1'b0;
                      done    <= 1'b1;
                      state   <= IDLE;
                    end else bitn <= bitn + 1'b1;
                  end
                endcase
              end
            endcase
          end
        end
      endcase
    end
  end
endmodule
