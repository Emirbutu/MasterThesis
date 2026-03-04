 // Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Module description:
// Find maximum value among N inputs with registered output
//
// Parameters:
// - N: number of inputs
// - DATAW: bit width of each input
//
// Port definitions:
// - clk_i: input clock signal
// - rst_ni: asynchronous reset, active low
// - en_i: module enable signal
// - valid_i: input valid signal
// - data_i: array of N input values
// - valid_o: output valid signal
// - max_o: maximum value output

`include "common_cells/registers.svh"

module find_max #(
    parameter int N = 4,
    parameter int DATAW = 64
)(
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    input logic valid_i,
    input logic [DATAW-1:0] data_i [N-1:0],
    output logic valid_o,
    output logic [DATAW-1:0] max_o
);

    logic [DATAW-1:0] max_comb;

    // Combinational max finding
    always_comb begin
        max_comb = data_i[0];
        for (int i = 1; i < N; i++) begin
            if (data_i[i] > max_comb) begin
                max_comb = data_i[i];
            end
        end
        // Output max_comb - 1 if not zero, else zero
        if (max_comb != '0)
            max_comb = max_comb - 1;
    end

    // Register the output
    `FFL(max_o, max_comb, en_i && valid_i, '0, clk_i, rst_ni);
    `FFL(valid_o, valid_i, en_i, 1'b0, clk_i, rst_ni);

endmodule
