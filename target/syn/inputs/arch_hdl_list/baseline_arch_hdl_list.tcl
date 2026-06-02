# Copyright 2024 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set HDL_LIST [ list \
    ${HDL_PATH}/lib/VX_pipe_register.sv \
    ${HDL_PATH}/lib/VX_pipe_buffer.sv \
    ${HDL_PATH}/lib/bp_pipe.sv \
    ${HDL_PATH}/energy_monitor_baseline/accumulator.sv \
    ${HDL_PATH}/energy_monitor_baseline/adder_tree.sv \
    ${HDL_PATH}/energy_monitor_baseline/logic_ctrl.sv \
    ${HDL_PATH}/energy_monitor_baseline/partial_energy_calc.sv \
    ${HDL_PATH}/energy_monitor_baseline/step_counter.sv \
    ${HDL_PATH}/energy_monitor_baseline/vector_caching.sv \
    ${HDL_PATH}/energy_monitor_baseline/energy_monitor_baseline.sv \
]