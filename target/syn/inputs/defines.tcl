# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
# Defines default values for synthesis parameters



# CLK_SPD = clock period in ps
if {[info exists ::env(CLK_SPD)]} { 
    set CLK_SPD $::env(CLK_SPD)
} else {
    set CLK_SPD 100000
}


# RETIME = 1 to enable retiming, 0 to disable it
if {[info exists ::env(RETIME)]} { 
    set RETIME $::env(RETIME)
} else {
    set RETIME 0
}



if {[info exists ::env(OUTPUTS_DIR)]} { 
    set OUTPUTS_DIR $::env(OUTPUTS_DIR)
} else {
    set OUTPUTS_DIR $SCRIPT_DIR/outputs/${SYN_MODULE}/_C${CLK_SPD}_RT${RETIME}
}