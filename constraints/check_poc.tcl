# Saves the PoC reports to doc/poc/ and checks that the ring survived implementation.
# With the implemented design open in the GUI, type in the Tcl console:
#   source <path to RO-PUF>/constraints/check_poc.tcl

set reports [file normalize [file dirname [info script]]/../doc/poc]
file mkdir $reports

report_utilization       -file $reports/poc_utilization.rpt
report_timing_summary    -file $reports/poc_timing_summary.rpt -max_paths 10
report_timing -corner Slow -delay_type min_max -max_paths 10 -file $reports/poc_timing_slow.rpt
report_timing -corner Fast -delay_type min_max -max_paths 10 -file $reports/poc_timing_fast.rpt
report_clock_interaction -file $reports/poc_clock_interaction.rpt
report_drc               -file $reports/poc_drc.rpt
report_route_status      -file $reports/poc_route_status.rpt

set failures {}

set ring_luts [get_cells -hierarchical -filter {NAME =~ u_ro/* && REF_NAME =~ LUT*}]
if {[llength $ring_luts] != 5} {
    lappend failures "expected 5 ring LUTs, found [llength $ring_luts]: $ring_luts"
}

foreach site [get_sites -of_objects $ring_luts] {
    set tile_type [get_property TILE_TYPE [get_tiles -of_objects $site]]
    if {[get_property SITE_TYPE $site] ne "SLICEL" || ![string match CLBLL* $tile_type]} {
        lappend failures "$site is [get_property SITE_TYPE $site] in $tile_type, not SLICEL in CLBLL"
    }
}

foreach net [get_nets {u_ro/ring[*]}] {
    if {![get_property ALLOW_COMBINATORIAL_LOOPS $net]} {
        lappend failures "$net lacks ALLOW_COMBINATORIAL_LOOPS"
    }
}

foreach clk {ro_clk ro_div} {
    if {[llength [get_clocks -quiet $clk]] != 1} { lappend failures "clock $clk is missing" }
}

# Each of these constraints targets cells by name, so a renamed register would drop it.
foreach cell {u_meas/gate_reg u_meas/clr_reg u_meas/u_chan_a/gate_s1_reg u_meas/u_chan_a/div_reg} {
    if {[llength [get_cells -quiet $cell]] != 1} { lappend failures "cell $cell not found" }
}
if {[llength [get_cells -quiet {shown_reg[*]}]] == 0} { lappend failures "shown_reg not found" }

set bad_nets [get_nets -hierarchical -filter {ROUTE_STATUS == CONFLICTS || ROUTE_STATUS == NOLOADS_CONFLICTS || ROUTE_STATUS == PARTIAL || ROUTE_STATUS == UNROUTED}]
if {[llength $bad_nets] != 0} { lappend failures "nets not fully routed: $bad_nets" }

puts "RING_SITES: [lsort -unique [get_sites -of_objects $ring_luts]]"
puts "WNS: [get_property SLACK [get_timing_paths -max_paths 1 -setup]]"
puts "WHS: [get_property SLACK [get_timing_paths -max_paths 1 -hold]]"

if {[llength $failures] == 0} {
    puts "CHECKS PASSED. Reports are in $reports"
} else {
    foreach f $failures { puts "CHECK FAILED: $f" }
}
