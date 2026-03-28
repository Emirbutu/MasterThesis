# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set HDL_LIST [ list \
    ${HDL_PATH}/lib/VX_pipe_register.sv \
    ${HDL_PATH}/lib/VX_pipe_buffer.sv \
    ${HDL_PATH}/energy_monitor/accumulator.sv \
    ${HDL_PATH}/energy_monitor/adder_tree_unsigned.sv \
    ${HDL_PATH}/energy_monitor/adder_tree.sv \
    ${HDL_PATH}/energy_monitor/find_all_ones_iterative.sv \
    ${HDL_PATH}/energy_monitor/find_max.sv \
    ${HDL_PATH}/energy_monitor/lzc.sv \
    ${HDL_PATH}/energy_monitor/logic_ctrl.sv \
    ${HDL_PATH}/energy_monitor/partial_energy_calc.sv \
    ${HDL_PATH}/energy_monitor/spin_flip_detector.sv \
    ${HDL_PATH}/energy_monitor/step_counter.sv \
    ${HDL_PATH}/energy_monitor/vector_caching.sv \
    ${HDL_PATH}/energy_monitor/VX_find_first.sv \
    ${HDL_PATH}/energy_monitor/energy_monitor.sv \
]
