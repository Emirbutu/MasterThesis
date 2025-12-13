# Copyright 2025 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set HDL_PATH ../../rtl

set HDL_FILES [ list \
    "./tb_update_dot_products.sv" \
    "${HDL_PATH}/handle_input_rows.sv" \
    "${HDL_PATH}/full_adder.sv" \
    "${HDL_PATH}/generic_mux.sv" \
    "${HDL_PATH}/ripple_carry_adder.sv" \
    "${HDL_PATH}/adder_tree.sv" \
    "${HDL_PATH}/adder_tree_layer.sv" \
    "${HDL_PATH}/adder_subtractor.sv" \
    "${HDL_PATH}/update_dot_products.sv" \
]
