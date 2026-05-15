# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: GitHub Copilot
# First-pass standalone power-analysis script for Genus.
#
# Expected flow:
#   1. Run synthesis with target/syn/src/syn.tcl
#   2. Simulate the synthesized or RTL-matching testbench and dump a VCD
#   3. Run this script to annotate the VCD and generate power reports

set_attribute information_level 2

set SCRIPT_DIR [file dirname [info script]]
set PROJECT_DIR $SCRIPT_DIR/../../..
set SYN_DIR     $PROJECT_DIR/target/syn
set INPUTS_DIR  $SCRIPT_DIR/../inputs

echo "Power script: $SCRIPT_DIR"
echo "Project directory: $PROJECT_DIR"
echo "Synthesis directory: $SYN_DIR"

source ${INPUTS_DIR}/../src/config.tcl

# Override defaults for power analysis of syn_tle_with_sram design.
# config.tcl may have set SYN_MODULE to DUS; we force the correct top-level name.
set SYN_MODULE "syn_tle_with_sram"
set TECH_NODE "tsmc28"
set CLK_SPD 2500
set RETIME 1
set OUTPUTS_DIR ${SYN_DIR}/src/outputs/${SYN_MODULE}/_C${CLK_SPD}_RT${RETIME}

# Reuse the same technology setup as synthesis.
source ${SYN_DIR}/tech/tsmc28/${TECH_NODE}_setup.tcl

if {![info exists target_library] || [llength $target_library] == 0} {
    puts "Error: target_library is not defined or empty after tech setup."
    exit 1
}
set_attribute library $target_library /
puts "Loaded [llength $target_library] technology libraries."

set DESIGN ${SYN_MODULE}
puts "Design: ${DESIGN}"

# Use the original synthesized netlist (non-injected).
# Note: For power analysis, we don't need cdeFileInit parameters (those are for simulation).
# The original netlist allows Genus to properly elaborate SRAM library cells.
set NETLIST_FILE ${OUTPUTS_DIR}/${DESIGN}.v

if {![info exists ::env(VCD_FILE)]} {
    puts "Error: VCD_FILE is not defined. Export it before running the power script."
    exit 1
} else {
    set VCD_FILE $::env(VCD_FILE)
}

if {![file exists $NETLIST_FILE]} {
    puts "Error: netlist file not found: $NETLIST_FILE"
    exit 1
}

if {![file exists $VCD_FILE]} {
    puts "Error: VCD file not found: $VCD_FILE"
    exit 1
}

if {![info exists ::env(POWER_SCOPE)]} {
    # Override this to the VCD hierarchy that matches the synthesized top.
    # Example: tb_syn_tle_with_sram/DUT
    set POWER_SCOPE ""
} else {
    set POWER_SCOPE $::env(POWER_SCOPE)
}

if {![info exists ::env(POWER_ACTIVITY_FORMAT)]} {
    set POWER_ACTIVITY_FORMAT VCD
} else {
    set POWER_ACTIVITY_FORMAT [string toupper $::env(POWER_ACTIVITY_FORMAT)]
}

if {![info exists ::env(POWER_REPORT_PREFIX)]} {
    set POWER_REPORT_PREFIX ${OUTPUTS_DIR}/${DESIGN}_power_vcd
} else {
    set POWER_REPORT_PREFIX $::env(POWER_REPORT_PREFIX)
}

set search_path [join "${PROJECT_DIR}/hw/rtl
                        ${PROJECT_DIR}/hw/rtl/libs/include
                        ${PROJECT_DIR}/hw/rtl/libs"]
set_attribute init_hdl_search_path ${PROJECT_DIR}/hw/rtl
set_attribute hdl_search_path $search_path
set_attribute auto_ungroup none
set_attribute hdl_bidirectional_assign false
set_attribute hdl_undriven_signal_value 0
set_attribute hdl_generate_separator _
set_attribute hdl_generate_index_style "%s_%d"
set_attribute hdl_allow_inout_const_port_connect true
set_attribute interconnect_mode ple

file mkdir $OUTPUTS_DIR

puts "Reading synthesized netlist from ${NETLIST_FILE}"
read_hdl -sv $NETLIST_FILE
elaborate ${DESIGN}
check_design -unresolved

read_sdc ${INPUTS_DIR}/constraints.sdc

puts "Annotating activity from ${VCD_FILE}"
puts "Activity format: ${POWER_ACTIVITY_FORMAT}"
if {$POWER_ACTIVITY_FORMAT ne "VCD"} {
    puts "Error: this script is VCD-only now; set POWER_ACTIVITY_FORMAT=VCD"
    exit 1
}

if {$POWER_SCOPE ne ""} {
    read_vcd \
        -vcd_scope $POWER_SCOPE \
        $VCD_FILE
} else {
    read_vcd $VCD_FILE
}

puts "Running power reporting"
report power > ${POWER_REPORT_PREFIX}.rpt
report power -summary > ${POWER_REPORT_PREFIX}_summary.rpt

puts "Wrote power reports to ${POWER_REPORT_PREFIX}.rpt and ${POWER_REPORT_PREFIX}_summary.rpt"

exit