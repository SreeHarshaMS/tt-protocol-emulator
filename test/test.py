# SPDX-FileCopyrightText: 2026
# SPDX-License-Identifier: Apache-2.0
#
# Smoke test for the Tiny Tapeout CI (cocotb + Icarus, RTL and gate level):
# talks to the design only through the host SPI port on ui_in / uo_out.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles

SDI, SCK, CS_N = 0b001, 0b010, 0b100


async def spi_byte(dut, tx):
    """Mode 0, MSB first, SCK = clk / 10. CS_n must already be low."""
    rx = 0
    for i in range(7, -1, -1):
        base = SDI if (tx >> i) & 1 else 0
        dut.ui_in.value = base
        await ClockCycles(dut.clk, 5)
        rx = (rx << 1) | (int(dut.uo_out.value) & 1)
        dut.ui_in.value = base | SCK
        await ClockCycles(dut.clk, 5)
        dut.ui_in.value = base
    return rx


async def frame(dut, data):
    """One chip-select low transaction. Returns the byte shifted out during the last byte."""
    dut.ui_in.value = 0
    await ClockCycles(dut.clk, 4)
    rx = 0
    for b in data:
        rx = await spi_byte(dut, b)
    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = CS_N
    await ClockCycles(dut.clk, 4)
    return rx


async def status(dut):
    return await frame(dut, [0x05, 0x00])


@cocotb.test()
async def test_project(dut):
    clock = Clock(dut.clk, 100, unit="ns")  # 10 MHz
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = CS_N
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

    # after reset: stopped, RX FIFO empty, TX FIFO not full, not halted
    st = await status(dut)
    dut._log.info(f"status after reset = {st:02x}")
    assert st == 0x02

    # program: OE 5,1 ; SET 5,0 ; HALT   (pin 5 must end up driven low, core halted)
    program = [0xB00D, 0x1005, 0xF000]
    for addr, word in enumerate(program):
        await frame(dut, [0x01, addr, word >> 8, word & 0xFF])
    await frame(dut, [0x02, 0x01])  # run
    await ClockCycles(dut.clk, 20)

    assert (int(dut.uio_oe.value) >> 5) & 1 == 1
    assert (int(dut.uio_out.value) >> 5) & 1 == 0
    st = await status(dut)
    dut._log.info(f"status after HALT = {st:02x}")
    assert st == 0x0E  # halted, run, rx_empty
