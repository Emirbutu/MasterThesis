// Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Parameters:
// - DATAWIDTH: data width
`include "common_cells/registers.svh"
module spin_flip_detector #(
    parameter int DATAWIDTH = 256
) (
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    input logic data_valid_i,
    input logic [DATAWIDTH-1:0] spin_previous_i,
    input logic [DATAWIDTH-1:0] spin_i,
    output logic [DATAWIDTH-1:0] spin_flipped_o,
    output logic [DATAWIDTH-1:0] spin_unflipped_o
);
    // Generate flipped and unflipped spin vectors by comparing new and cached spins
    // Register them since sigma_i is only valid for 1 cycle during handshake
    logic [DATAWIDTH-1:0] spin_flipped_comb;
    logic [DATAWIDTH-1:0] spin_unflipped_comb;
    logic data_handshake;

    assign data_handshake = en_i & data_valid_i;
    assign spin_flipped_comb = spin_i ^ spin_previous_i;      // bits that changed (flipped)
    assign spin_unflipped_comb = ~(spin_i ^ spin_previous_i); // bits that stayed the same
    
    `FFLARNC(spin_flipped_o, spin_flipped_comb, data_handshake, !en_i, '0, clk_i, rst_ni)
    `FFLARNC(spin_unflipped_o, spin_unflipped_comb, data_handshake, !en_i, '0, clk_i, rst_ni)

endmodule   