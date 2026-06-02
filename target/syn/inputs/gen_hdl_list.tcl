# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

if {[info exists ::env(ARCH_HDL_LIST_TCL)] && $::env(ARCH_HDL_LIST_TCL) ne ""} {
	set HDL_LIST_TCL $::env(ARCH_HDL_LIST_TCL)
} else {
	set HDL_LIST_TCL ${INPUTS_DIR}/arch_hdl_list/base_arch_hdl_list.tcl
}

source $HDL_LIST_TCL
