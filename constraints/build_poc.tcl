# Builds the PoC bitstream (ro_standalone_top), then saves the reports and checks the ring
# with check_poc.tcl. Run it from RVfpga/vivado/, which is gitignored, so Vivado's own logs
# stay out of the repo:
#   cd RVfpga/vivado
#   vivado -mode batch -source ../RO-PUF/constraints/build_poc.tcl
#
# It recreates the project at vivado/ro_standalone/, replacing any existing one. Open
# vivado/ro_standalone/ro_standalone.xpr in the GUI afterwards for the Device view.

set here  [file normalize [file dirname [info script]]]
set root  [file normalize $here/../..]
set src   $root/src
set proj  $root/vivado/ro_standalone
set cells $src/OtherSources/pulp-platform.org__common_cells_1.20.0/src

create_project -force ro_standalone $proj -part xc7a100tcsg324-1

add_files -norecurse [list \
    $src/SweRVolfSoC/Peripherals/pvt/ring_osc.v \
    $src/SweRVolfSoC/Peripherals/pvt/meas_unit.v \
    $src/SweRVolfSoC/Peripherals/pvt/ro_standalone_top.v \
    $src/SweRVolfSoC/Peripherals/SystemController/swervolf_syscon.sv \
    $cells/delta_counter.sv \
    $cells/counter.sv]
set_property top ro_standalone_top [current_fileset]
update_compile_order -fileset sources_1

# Implementation only: the div_reg and shown_reg cells don't exist until after synthesis.
add_files -fileset constrs_1 -norecurse $src/rvfpganexys.xdc
set_property USED_IN_SYNTHESIS false [get_files rvfpganexys.xdc]

launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis failed: see $proj/ro_standalone.runs/synth_1/runme.log"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set bit $proj/ro_standalone.runs/impl_1/ro_standalone_top.bit
if {![file exists $bit]} {
    error "No bitstream: see $proj/ro_standalone.runs/impl_1/runme.log"
}

open_run impl_1
source $here/check_poc.tcl

if {[llength $failures] != 0} { error "PoC checks failed, see CHECK FAILED above" }

puts "BITSTREAM: $bit"
