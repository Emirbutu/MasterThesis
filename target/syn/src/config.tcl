# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Author: Giuseppe Sarda <giuseppe.sarda@esat.kuleuven.be>
#         Emirhan Bututaki <emirhan.bututaki@student.kuleuven.be>

puts "--------------------------------------------------------------------------------"
puts "Synthesis configuration parameters:"

# TECH_NODE: Technology node for synthesis
# Default: tsmc28
# Used to select the technology-specific setup script
if { [info exists ::env(TECH_NODE)] } {
    set TECH_NODE $::env(TECH_NODE)
} else {
    set TECH_NODE "tsmc28"
}
puts "\tTECH_NODE: $TECH_NODE"

# SYN_TLE: Synthesis top-level entity name
# Default: syn_tle
# Used to specify the top-level module for synthesis
if { [info exists ::env(SYN_TLE)] } {
    set SYN_TLE $::env(SYN_TLE)
} else {
    set SYN_TLE "syn_tle"
}
puts "\tSYN_TLE: $SYN_TLE"

# SYN_MODULE: Synthesis module name
# Default: DUS (Design Under Synthesis)
# Used to specify the design module for synthesis
if { [info exists ::env(SYN_MODULE)] } {
    set SYN_MODULE $::env(SYN_MODULE)
} else {
    set SYN_MODULE "DUS"
}
puts "\tSYN_MODULE: $SYN_MODULE"

# RETIME: Whether to enable retiming during synthesis
# Default: 1 (enabled)
# Used to control whether retiming optimizations are applied during synthesis
if { [info exists ::env(RETIME)] } {
    set RETIME $::env(RETIME)
} else {
    set RETIME 1
}
puts "\tRETIME: $RETIME"