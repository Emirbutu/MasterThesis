# Copyright 2025 KU Leuven.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

set HDL_PATH ../../rtl

set HDL_FILES [ list \
    "./tb_MatMul.sv" \
    "${HDL_PATH}/MatMul.sv" \
    "${HDL_PATH}/adder_subtractor_unit.sv" \
    "${HDL_PATH}/counter.sv" \
    "${HDL_PATH}/DotProductTree.sv" \
    "${HDL_PATH}/adder_tree_layer.sv" \
]