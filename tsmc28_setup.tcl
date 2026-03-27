# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
#         Emirhan Bututaki <emirhan.bututaki@student.kuleuven.be>

set SCRIPTDIR [file dirname [info script]]

set TSMC28_PDK_HOME /users/micas/micas/design/tsmc28hpcplus
set TSMC28_CCS_HOME $TSMC28_PDK_HOME/libs/TSMCHOME/digital/Front_End/timing_power_noise/CCS

set STDC_LENGTH "12t35p"
set CORNER "tt"
set V_VAL "0p9v"
set T_VAL "25c"
set V_T ${V_VAL}${T_VAL}

set TSMC28_ID tcbn28hpcplusbwp${STDC_LENGTH}

set TSMC28_TIMING_STDC [ list \
    $TSMC28_CCS_HOME/${TSMC28_ID}lvt_180a/${TSMC28_ID}lvt${CORNER}${V_T}_ccs.lib \
    $TSMC28_CCS_HOME/${TSMC28_ID}hvt_180a/${TSMC28_ID}hvt${CORNER}${V_T}_ccs.lib \
    $TSMC28_CCS_HOME/${TSMC28_ID}uhvt_180a/${TSMC28_ID}uhvt${CORNER}${V_T}_ccs.lib \
    $TSMC28_CCS_HOME/${TSMC28_ID}ulvt_180a/${TSMC28_ID}ulvt${CORNER}${V_T}_ccs.lib \
]

#source $SCRIPTDIR/IPs/sram.tcl

set target_library [
    {*}$TSMC28_TIMING_STDC \
    {*}$TSMC28_SRAM \
]

# Check that the libraries exist
foreach lib $target_library {
    if { ![file exists $lib] } {
        puts "Error: a library file does not exist!"
        puts "Missing file: $lib"
        exit 1
    }
}

set link_library "* $target_library"