## How it works

A tiny processor whose only job is moving bits on eight pins with cycle-exact timing. Protocols such as
UART, SPI and I2C are firmware, so new protocols can be added after fabrication.

- 64 x 16-bit program memory, written through the host port.
- 15 instructions: `SET`, `OE`, `WAIT n`, `LOADX`, `DJNZ`, `JMP`, `JPIN` (branch on a pin, used for clock
  stretching), `OUT` / `OUTD` (push-pull / open-drain bit out), `IN`, `OUTX`, `PULL`, `PUSH`, `HALT`, `NOP`.
  Every instruction is one cycle except `WAIT n` (n+1) and a blocked `PULL` / `PUSH`.
- Two 4-byte FIFOs connect the firmware with the host.
- The eight emulator pins are `uio[7:0]`, each with its own output enable, so open-drain buses like I2C work.

## How to test

The host talks SPI mode 0 (MSB first, SCK at most clk/4) on `ui[0]` SDI, `ui[1]` SCK, `ui[2]` CS_N, with
SDO on `uo[0]`. One transaction per CS_N low period:

| Command | Bytes | Effect |
|---|---|---|
| `01` | `aa hh ll` | write program word `hhll` at address `aa` |
| `02` | `rr` | `rr[0]` = run |
| `03` | `dd` | push `dd` to the firmware (TX FIFO) |
| `04` | `xx` | pop a byte from the firmware (shifted out during `xx`) |
| `05` | `xx` | status during `xx`: bit 3 halted, bit 2 run, bit 1 rx_empty, bit 0 tx_full |

Example: load the 12-word UART firmware (pin 0, 16 clocks per bit), set run, then every byte pushed with
`03 dd` comes out of `uio[0]` as 8N1 serial.

## External hardware

Whatever the firmware talks to: a UART adapter, an SPI or I2C peripheral (with pull-ups on SCL/SDA), and a
microcontroller or USB-SPI adapter acting as the host.
