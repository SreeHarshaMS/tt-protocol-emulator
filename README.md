# Programmable protocol emulator

A small programmable pin-I/O core for the Jane Street open-source ASIC competition (IHP 130nm CMOS5L via
Tiny Tapeout, up to 6x4 tiles, deadline 18 Jan 2027). Protocols are firmware, not fixed logic: UART, SPI
and I2C run on the same core and the same pins, and new ones can be loaded after fabrication.

This folder is laid out as a Tiny Tapeout CMOS5L project (`src/`, `test/`, `docs/`, `info.yaml`,
`.github/workflows/` from the template), plus a `dv/` folder with the full verification environment.

## Architecture

```
 host SPI (ui_in)  ->  host_if  -> program memory (64 x 16)
                          |-----> TX FIFO (4 x 8) -> PULL
                          '<----- RX FIFO (4 x 8) <- PUSH
 emu_core: PC, X counter, OSR/ISR shift registers, 8 pins (out, oe, 2-FF synchronised in)
 tt_um_sreeharshams_protocol_emulator: host_if + emu_core on the Tiny Tapeout pins (uio[7:0] = emulator pins)
```

## Instruction set (16 bits, `[15:12]` opcode)

| Instruction | Effect |
|---|---|
| `SET pin,val` / `OE pin,en` | drive the output register / output enable of a pin |
| `WAIT n` | stall n extra cycles (the instruction takes n+1 cycles) |
| `LOADX v`, `DJNZ a`, `JMP a` | loop counter, loop, jump |
| `JPIN pin,pol,a` | jump if the synchronised input pin equals `pol`; used for clock stretching |
| `OUT pin,msb` / `OUTD pin,msb` | push-pull / open-drain output of one OSR bit, then shift OSR |
| `IN pin,msb` | shift a pin into ISR |
| `OUTX` | X = OSR (lets firmware dispatch on a host command) |
| `PULL` / `PUSH` | OSR = TX FIFO / RX FIFO = ISR (block while empty / full) |
| `HALT`, `NOP` | stop / do nothing |

Every instruction takes one cycle except `WAIT` (n+1) and a blocked `PULL`/`PUSH`, so protocol timing is
cycle-exact. Encoders: `dv/emu_isa_pkg.sv`. Firmware: `dv/emu_fw_pkg.sv` (UART TX 12 words, I2C master
63 of 64 words) and SPI mode 0 in `dv/tb_core_spi.sv` (19 words).

## Host interface (SPI slave, mode 0, SCK at most clk/4)

One transaction per chip-select low period; the first byte is the command.

| Command | Bytes | Effect |
|---|---|---|
| `01` | `aa hh ll` | write program word `hhll` at address `aa` |
| `02` | `rr` | `rr[0]` = run |
| `03` | `dd` | push `dd` into the TX FIFO |
| `04` | `xx` | pop the RX FIFO; the data is shifted out during `xx` |
| `05` | `xx` | status during `xx`: bit 3 halted, bit 2 run, bit 1 rx_empty, bit 0 tx_full |

Outputs: `uo[0]` SDO, `uo[1]` halted, `uo[2]` rx_empty, `uo[3]` tx_full, `uo[4]` run.

## Files

| Folder | Contents |
|---|---|
| `src/` | synthesizable RTL, plain Verilog-2005: `project.v` (top), `host_if.v`, `emu_core.v`, `sync_fifo.v` |
| `test/` | Tiny Tapeout CI test (cocotb + Icarus): `tb.v`, `test.py`, `Makefile`, `requirements.txt` |
| `docs/info.md` | datasheet page for Tiny Tapeout |
| `dv/` | verification: SystemVerilog testbenches, slave models, ISA and firmware packages, fixed-function reference blocks (`uart_tx/rx`, `spi_master`, `i2c_master`), `tb_icarus.v`, `run_all.ps1`, `sim.bat`, `synth_ihp.sh` |
| `.github/workflows/` | `gds.yaml` and `test.yaml`, unchanged from the CMOS5L template |

## Verification

| Test | What it checks |
|---|---|
| `tb_uart`, `tb_spi`, `tb_i2c` | fixed-function reference blocks (SPI in all four modes) |
| `tb_core_uart`, `tb_core_spi`, `tb_core_i2c`, `tb_core_jpin` | each protocol as firmware on the core |
| `tb_top` | end to end through the host SPI port: I2C (write, repeated START, read ACK/NACK, wrong address), 16 random I2C writes, UART firmware swap, 32 random UART bytes, and 7 concurrent assertions on the core and host port every cycle |
| `tb_icarus` | the RTL compiled as plain Verilog-2005 in Icarus (the CI simulator): status byte, a small program, the UART firmware |

Run everything (Windows, Vivado xsim + Icarus, from `dv/`):

```
powershell -ExecutionPolicy Bypass -File .\run_all.ps1
```

`sim.bat` has the Vivado path on its `VIV=` line; edit it for your install. Single test:
`.\sim.bat tb_spi spi_master.sv spi_slave_model.sv tb_spi.sv` (add `-gui` first for waveforms).

## Synthesis (Yosys 0.70, IHP SG13CMOS5L typical 1.2 V / 25 C)

`dv/synth_ihp.sh` (WSL or Linux, needs the OSS CAD Suite in `~/oss-cad-install`; downloads the liberty file
on first run). It uses Yosys's built-in Verilog reader, like the Tiny Tapeout flow. Result in
`dv/synth_ihp_stat.txt`:

| Metric | Value |
|---|---|
| Cells | 4,992 |
| Cell area | 102,046 um^2, about 24% of a 6x4 tile area (24 x 167 x 108 um) |
| Flip-flops | 1,269 (61% of the area; 1,024 of them are the program memory) |

## What is still needed before submission

1. Push this folder to a public GitHub repo (or a fork of `TinyTapeout/ttihp-verilog-template`, branch
   `cmos5l`) and let the `gds`, `precheck`, `gl_test` and `test` workflows run. That is the real
   place-and-route, timing and gate-level check; it has not been run yet.
2. `clock_hz` is set to 10 MHz; confirm the GDS run meets it.
3. Submit through the competition form before 18 Jan 2027.

## Known limits

- Program memory is 64 words; I2C uses 63. More protocols need more memory (an SRAM macro would also cut
  most of the area) or a denser ISA.
- The I2C write reply only guarantees bit 0 (the ack); the other bits are leftover ISR content.
- `test/test.py` and `test/requirements.txt` (cocotb 2.0.1) were not run locally: cocotb is not installed
  here. The same checks pass in `dv/tb_icarus.v`.
