@echo off
REM One-command Vivado simulation.
REM   sim.bat <top_module> <file1.v> [file2.v ...]         run in the terminal, print results
REM   sim.bat -gui <top_module> <file1.v> [file2.v ...]    open the waveform viewer with all signals
REM Run it from the folder that holds your .v files, e.g.  cd C:\VERILOG_SV\day01  then  ..\sim.bat tb_addsub4 addsub4.v tb_addsub4.v
setlocal
set VIV=C:\Electronics\2025.1\Vivado\bin
set GUI=
if /I "%~1"=="-gui" (
    set GUI=1
    shift
)
set TOP=%~1
shift
set FILES=
:collect
if "%~1"=="" goto build
set FILES=%FILES% "%~1"
shift
goto collect

:build
if "%TOP%"=="" (echo Usage: sim.bat [-gui] top_module file1.v [file2.v ...] & exit /b 1)
call "%VIV%\xvlog.bat" -sv %FILES% > xvlog_out.log || (type xvlog_out.log & exit /b 1)
call "%VIV%\xelab.bat" %TOP% -s %TOP%_sim -debug typical > xelab_out.log || (type xelab_out.log & exit /b 1)

if defined GUI (
    > wave.tcl echo log_wave -recursive *
    >> wave.tcl echo add_wave -recursive /%TOP%/*
    >> wave.tcl echo run all
    call "%VIV%\xsim.bat" %TOP%_sim -gui -tclbatch wave.tcl
) else (
    call "%VIV%\xsim.bat" %TOP%_sim -R
)
