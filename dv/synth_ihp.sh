#!/bin/bash
# Synthesize src/*.v to IHP SG13CMOS5L standard cells with Yosys (run inside WSL / Linux).
# Uses Yosys's own Verilog reader, like the Tiny Tapeout flow, so it also checks the RTL is readable there.
set -e
source "$HOME/oss-cad-install/oss-cad-suite/environment"
LIBDIR="$HOME/ihp-lib"
LIB="$LIBDIR/sg13cmos5l_stdcell_typ_1p20V_25C.lib"
if [ ! -s "$LIB" ]; then
  mkdir -p "$LIBDIR"
  curl -L --fail -o "$LIB" "https://raw.githubusercontent.com/IHP-GmbH/IHP-Open-PDK/main/ihp-sg13cmos5l/libs.ref/sg13cmos5l_stdcell/lib/sg13cmos5l_stdcell_typ_1p20V_25C.lib"
fi
cd "$(dirname "$0")/../src"
yosys -q -l synth_ihp.log -p "
read_liberty -lib $LIB
read_verilog project.v host_if.v emu_core.v sync_fifo.v
synth -top tt_um_sreeharshams_protocol_emulator -flatten
dfflegalize -cell \$_DFF_P_ 01
dfflibmap -liberty $LIB
abc -liberty $LIB
opt_clean -purge
check -assert
tee -o ../dv/synth_ihp_stat.txt stat -liberty $LIB
"
rm -f synth_ihp.log
cat ../dv/synth_ihp_stat.txt
