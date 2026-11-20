# Runs every testbench and prints one PASS/FAIL line per test.
#   Vivado xsim (through .\sim.bat) for the SystemVerilog testbenches,
#   Icarus (iverilog -g2005) for tb_icarus, which also proves the RTL in ..\src is plain Verilog-2005.
# Usage (from this folder):  powershell -ExecutionPolicy Bypass -File .\run_all.ps1
$rtl  = '..\src\sync_fifo.v ..\src\emu_core.v'
$core = "emu_isa_pkg.sv $rtl"
$top  = "emu_isa_pkg.sv emu_fw_pkg.sv $rtl ..\src\host_if.v ..\src\project.v"
$tests = @(
  @('tb_uart',      'uart_tx.sv uart_rx.sv tb_uart.sv'),
  @('tb_spi',       'spi_master.sv spi_slave_model.sv tb_spi.sv'),
  @('tb_i2c',       'i2c_master.sv i2c_slave_model.sv tb_i2c.sv'),
  @('tb_core_uart', "$core uart_rx.sv tb_core_uart.sv"),
  @('tb_core_spi',  "$core spi_slave_model.sv tb_core_spi.sv"),
  @('tb_core_jpin', "$core tb_core_jpin.sv"),
  @('tb_core_i2c',  "$core i2c_slave_model.sv tb_core_i2c.sv"),
  @('tb_top',       "$top i2c_slave_model.sv uart_rx.sv tb_top.sv")
)
$failed = 0

function Show-Result($name, $log) {
  $text = Get-Content $log -Raw
  if ($text -match 'PASS' -and $text -notmatch 'FAIL' -and $text -notmatch 'ERROR:') {
    Write-Host ('{0,-14} PASS' -f $name); Remove-Item $log; return $true
  }
  Write-Host ('{0,-14} FAIL  (see {1})' -f $name, $log); return $false
}

foreach ($t in $tests) {
  $log = "run_$($t[0]).txt"
  $p = Start-Process -FilePath cmd -ArgumentList '/c',".\sim.bat $($t[0]) $($t[1]) > $log 2>&1" -PassThru -NoNewWindow
  if (-not $p.WaitForExit(280000)) {
    Get-Process xsim,xsimk -ErrorAction SilentlyContinue | Stop-Process -Force
    $p | Stop-Process -Force -ErrorAction SilentlyContinue
    '{0,-14} TIMEOUT' -f $t[0]; $failed++; continue
  }
  if (-not (Show-Result $t[0] $log)) { $failed++ }
}

$log = 'run_tb_icarus.txt'
cmd /c "iverilog -g2005 -Wall -o tb_icarus.vvp ..\src\project.v ..\src\host_if.v ..\src\emu_core.v ..\src\sync_fifo.v tb_icarus.v > $log 2>&1 && vvp -n tb_icarus.vvp >> $log 2>&1"
if (-not (Show-Result 'tb_icarus' $log)) { $failed++ }
Remove-Item tb_icarus.vvp -ErrorAction SilentlyContinue

if ($failed -eq 0) { 'ALL TESTS PASS' } else { "$failed test(s) failed"; exit 1 }

