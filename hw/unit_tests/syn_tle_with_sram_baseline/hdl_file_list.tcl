# Copyright 2025 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set PROJECT_ROOT ../../..
set HDL_PATH ../../rtl

set HDL_FILES [ list \
    "./tb_syn_tle_with_sram_baseline.sv" \
    "${HDL_PATH}/tc_sram_syn.sv" \
    "/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/tsn28hpcpuhdspsram_20120200_170a/ts1n28hpcpuhdhvtb64x256m1swbso_170a/VERILOG/ts1n28hpcpuhdhvtb64x256m1swbso_170a_tt0p9v25c.v" \
    "${HDL_PATH}/energy_monitor_baseline/energy_monitor_baseline.sv" \
    "${HDL_PATH}/syn_tle_with_sram_nobh_baseline.sv" \
    "${HDL_PATH}/lib/bp_pipe.sv" \
    "${HDL_PATH}/include/registers.svh" \
    "${HDL_PATH}/energy_monitor_baseline/vector_caching.sv" \
    "${HDL_PATH}/energy_monitor_baseline/step_counter.sv" \
    "${HDL_PATH}/energy_monitor_baseline/logic_ctrl.sv" \
    "${HDL_PATH}/energy_monitor_baseline/partial_energy_calc.sv" \
    "${HDL_PATH}/energy_monitor_baseline/adder_tree.sv" \
    "${HDL_PATH}/energy_monitor_baseline/accumulator.sv" \
]

# set INCLUDE_DIRS [list \
#    "[exec bender path common_cells]/include" \
# ]