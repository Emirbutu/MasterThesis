# Copyright 2025 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set PROJECT_ROOT ../../..
set HDL_PATH ../../rtl
set TSMC28_PDK_HOME /users/micas/micas/design/tsmc28hpcplus/standard_cell_libraries/tcbn28hpcplusbwp30p140-set

set HDL_FILES [ list \
    "./tb_syn_tle_with_sram.sv" \
    "${HDL_PATH}/tc_sram_syn.sv" \
    "/users/micas/micas/design/tsmc28hpcplus/memories/compilers/MC2/tsn28hpcpuhdspsram_20120200_170a/ts1n28hpcpuhdhvtb64x256m1swbso_170a/VERILOG/ts1n28hpcpuhdhvtb64x256m1swbso_170a_tt0p9v25c.v" \
    "/users/students/r1024900/MasterThesis/target/syn/src/outputs/syn_tle_with_sram/_C2500_RT1/syn_tle_with_sram.v" \
    "${TSMC28_PDK_HOME}/tcbn28hpcplusbwp30p140_190a_FE/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140_110a/tcbn28hpcplusbwp30p140.v" \
    "${TSMC28_PDK_HOME}/tcbn28hpcplusbwp30p140lvt_190a_FE/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140lvt_110a/tcbn28hpcplusbwp30p140lvt.v" \
    "${TSMC28_PDK_HOME}/tcbn28hpcplusbwp30p140hvt_190a_FE/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140hvt_110a/tcbn28hpcplusbwp30p140hvt.v" \
    "${TSMC28_PDK_HOME}/tcbn28hpcplusbwp30p140uhvt_190a_FE/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140uhvt_140a/tcbn28hpcplusbwp30p140uhvt.v" \
    "${TSMC28_PDK_HOME}/tcbn28hpcplusbwp30p140ulvt_190a_FE/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp30p140ulvt_140a/tcbn28hpcplusbwp30p140ulvt.v" \
    "${HDL_PATH}/energy_monitor/energy_monitor.sv" \
    "${HDL_PATH}/lib/bp_pipe.sv" \
    "${HDL_PATH}/include/registers.svh" \
    "${HDL_PATH}/energy_monitor/vector_caching.sv" \
    "${HDL_PATH}/energy_monitor/step_counter.sv" \
    "${HDL_PATH}/energy_monitor/logic_ctrl.sv" \
    "${HDL_PATH}/energy_monitor/partial_energy_calc.sv" \
    "${HDL_PATH}/energy_monitor/adder_tree.sv" \
    "${HDL_PATH}/energy_monitor/accumulator.sv" \
    "${HDL_PATH}/energy_monitor/find_max.sv" \
    "${HDL_PATH}/energy_monitor/spin_flip_detector.sv" \
    "${HDL_PATH}/energy_monitor/adder_tree_unsigned.sv" \
    "${HDL_PATH}/energy_monitor/find_all_ones_iterative.sv" \
    "${HDL_PATH}/energy_monitor/lzc.sv" \
    "${HDL_PATH}/energy_monitor/VX_find_first.sv" \
]
