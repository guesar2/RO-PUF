#!/usr/bin/env bash
# Runs the PoC testbenches in Verilator. Build products go to a temporary directory.
# Exits non-zero if any testbench doesn't print "TB PASS".
set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/../../src"
pvt="$src/SweRVolfSoC/Peripherals/pvt"
cells="$src/OtherSources/pulp-platform.org__common_cells_1.20.0/src"
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT

sources=(
    "$pvt/ring_osc.v"
    "$pvt/meas_unit.v"
    "$pvt/ro_standalone_top.v"
    "$src/SweRVolfSoC/Peripherals/SystemController/swervolf_syscon.sv"
    "$cells/delta_counter.sv"
    "$cells/counter.sv"
)

status=0
for tb in tb_meas_unit tb_ro_standalone; do
    echo "=== $tb"
    verilator --binary --timing -DSIM -Wno-fatal -j 0 \
              --timescale 1ps/1ps --top-module "$tb" \
              --Mdir "$build/$tb" -o "$tb" \
              "${sources[@]}" "$here/$tb.v" > "$build/$tb.log" 2>&1 \
        || { cat "$build/$tb.log"; status=1; continue; }
    "$build/$tb/$tb" > "$build/$tb.out" 2>&1
    grep -E '^(ok:|FAIL|TB )|Error|%Warning' "$build/$tb.out"
    grep -q '^TB PASS' "$build/$tb.out" || status=1
done
exit $status
