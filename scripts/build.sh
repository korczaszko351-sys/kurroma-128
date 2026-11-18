#!/usr/bin/env bash
# ============================================================================
# build.sh : pelny przeplyw Kurroma-128
#   ./build.sh sim     - symulacja Verilator
#   ./build.sh synth   - synteza Yosys (raport LUT/FF)
#   ./build.sh vivado  - projekt Vivado + bitstream (wymaga Vivado)
#   ./build.sh all     - sim + synth
# ============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

SIM=obj_dir/tb_kurroma
HEX=sw/test_alu.hex

case "${1:-all}" in
  sim)
    echo "[1/3] asemblacja"
    python3 sw/asm.py sw/test_alu.asm $HEX
    echo "[2/3] kompilacja Verilator"
    verilator --binary -j 2 -Wno-fatal -Wno-WIDTH -Wno-UNUSEDSIGNAL \
        -Irtl --top-module tb_kurroma tb/tb_kurroma.v rtl/*.v -o tb_kurroma
    echo "[3/3] symulacja"
    ./$SIM +IMEM=$HEX | tee reports/sim.log
    grep -q "WSZYSTKIE TESTY PRZESZLY" reports/sim.log
    echo "OK: symulacja przeszla"
    ;;
  synth)
    echo "[1/2] synteza Yosys"
    yosys scripts/synth.ys > reports/yosys_synth.log 2>&1
    echo "[2/2] raport"
    grep -A40 "Printing statistics" reports/yosys_synth.log | tail -45
    ;;
  vivado)
    echo "Uruchamiam Vivado w trybie batch..."
    vivado -mode batch -source scripts/build_vivado.tcl -log reports/vivado.log
    ;;
  all)
    "$0" sim
    "$0" synth
    ;;
  *)
    echo "uzycie: $0 {sim|synth|vivado|all}"; exit 1;;
esac
