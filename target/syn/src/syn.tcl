# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
#         Mats Vanhamel <mats.vanhamel@student.kuleuven.be>
# Basic synthesis script

set_attribute information_level 2

set SCRIPT_DIR [file dirname [info script]]
set PROJECT_DIR    $SCRIPT_DIR/../../..
set SYN_DIR        $PROJECT_DIR/target/syn
set INPUTS_DIR     $SCRIPT_DIR/../inputs
echo "Synthesis script: $SCRIPT_DIR)"
echo "Project directory: $PROJECT_DIR"
echo "Synthesis directory: $SYN_DIR"
source ${INPUTS_DIR}/../src/config.tcl
source ${INPUTS_DIR}/defines.tcl

# Setting up the technology
source ${SYN_DIR}/tech/tsmc28/${TECH_NODE}_setup.tcl

# In Genus, technology .lib files must be attached to the root "library"
# attribute before elaborate.
if {![info exists target_library] || [llength $target_library] == 0} {
    puts "Error: target_library is not defined or empty after tech setup."
    exit 1
}
set_attribute library $target_library /
puts "Loaded [llength $target_library] technology libraries."

set DESIGN ${SYN_MODULE}
puts "Design: ${DESIGN}"

set HDL_PATH [ list \
    $PROJECT_DIR/hw/rtl \
]

#Add other paths here

set search_path [ join "$HDL_PATH
                        $HDL_PATH/libs/include
                        $HDL_PATH/libs" ]

set_attribute auto_ungroup none
set_attribute hdl_bidirectional_assign false
set_attribute hdl_undriven_signal_value 0

## Set up low-power flow variables
set_attribute lp_insert_clock_gating true
set_attribute lp_clock_gating_prefix lowp_cg

set_attribute leakage_power_effort medium
set_attribute lp_power_analysis_effort medium

set_attribute hdl_generate_separator _
set_attribute hdl_generate_index_style "%s_%d"

## Set up allowing const_value for inout to PAD RETC
set_attribute hdl_allow_inout_const_port_connect true

set_attribute interconnect_mode ple

set_attribute init_hdl_search_path $HDL_PATH
set_attr hdl_search_path $search_path

puts "Reading HDL files for ${DESIGN}"

source ${INPUTS_DIR}/gen_hdl_list.tcl
lappend HDL_LIST ${HDL_PATH}/syn_tle.sv
lappend HDL_LIST ${HDL_PATH}/syn_tle_with_sram.sv
lappend HDL_LIST ${HDL_PATH}/tc_sram_syn.sv
read_hdl -sv ${HDL_LIST}

# Example of defines
# read_hdl -sv -define M=${M_SIZE} -define N=${N_SIZE} -define K=${K_SIZE} \
#         -define P=${DATAW} -define PIPESTAGES=(${PIPE_REGS}+1) \
#         -define TREE=${TREE} -define MODE=${DOTP_ARCH} -define MANUAL_PIPELINE=${MANUAL_PIPELINE} \
#         ${HDL_LIST}


elaborate ${DESIGN}
check_design -unresolved

if {$RETIME} {
    set_attribute dont_retime true ${DESIGN}/input_buffer
    set_attribute dont_retime true ${DESIGN}/output_buffer
    set_attribute retime true *${SYN_MODULE}*
}

read_sdc ${INPUTS_DIR}/constraints.sdc

# read_power_intent ${SCRIPT_DIR}/tech/power_intent.upf
# apply_power_intent
# commit_power_intent

set_attribute syn_generic_effort medium
set_attribute syn_map_effort     medium
set_attribute syn_opt_effort     medium

file mkdir $OUTPUTS_DIR

syn_generic ${DESIGN}
report timing -lint

syn_map ${DESIGN}
syn_opt

check_timing_intent

report timing > ${OUTPUTS_DIR}/${DESIGN}_timing.rpt
report timing -summary > ${OUTPUTS_DIR}/${DESIGN}_timing_summary.rpt
report area > ${OUTPUTS_DIR}/${DESIGN}_area.rpt
report datapath > ${OUTPUTS_DIR}/${DESIGN}_datapath_incr.rpt
report messages > ${OUTPUTS_DIR}/${DESIGN}_messages.rpt
report gates > ${OUTPUTS_DIR}/${DESIGN}_gates.rpt
report power > ${OUTPUTS_DIR}/${DESIGN}_power.rpt
report disabled_transparent_latches > ${OUTPUTS_DIR}/${DESIGN}_latches.rpt

write_hdl -pg > ${OUTPUTS_DIR}/${DESIGN}.v

exit