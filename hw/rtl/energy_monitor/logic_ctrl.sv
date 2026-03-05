// Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Author: Jiacong Sun <jiacong.sun@kuleuven.be>
//
// Module description:
// Logic FSM for the energy monitor module.
//
// Parameters:
// - None
//
// Port definitions:
// - clk_i: input clock signal
// - rst_ni: asynchornous reset, active low
// - en_i: module enable signal
// - config_valid_i: input config valid signal
// - config_ready_o: output config ready signal
// - spin_valid_i: input spin valid signal
// - spin_ready_o: output spin ready signal
// - weight_valid_i: input weight valid signal
// - weight_ready_o: output weight ready signal
// - counter_ready_i: counter ready signal
// - cmpt_done_i: computation done signal
// - energy_valid_o: output energy valid signal
// - energy_ready_i: input energy ready signal
// - debug_en_i: debug step signal


//Buraya state ekle previous energyi accumulate etmek icin, orda baya siknitilar oluyo
`include "../include/registers.svh"

module logic_ctrl #(
    parameter int PIPESMID = 1
)(
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    input logic standard_mode_i,
    input logic first_operation_sampled_i,
    input logic max_flipped_count_valid,

    input logic config_valid_i,
    output logic config_ready_o,

    input logic spin_valid_i,
    output logic spin_ready_o,

    input logic weight_valid_i,
    output logic weight_ready_o,

    input logic counter_ready_i,
    input logic cmpt_done_i,

    output logic energy_valid_o,
    input logic energy_ready_i,

    input logic debug_en_i
);
    // State enumeration
    typedef enum logic [1:0] {
        IDLE = 2'b00,
        COMPUTE_STANDARD = 2'b01,
        COMPUTE_NONSTANDARD = 2'b10
    } state_t;
    state_t current_state, next_state;

    logic spin_handshake;
    logic weight_handshake;
    logic energy_valid_comb;
    logic energy_valid_reg;
    logic energy_handshake;
    logic [PIPESMID:0] counter_ready_pipe;
    logic [2:0] spin_handshake_pipe;

    assign weight_handshake = weight_valid_i && weight_ready_o;
    assign energy_handshake = energy_valid_o && energy_ready_i;
    assign spin_handshake   = spin_valid_i && spin_ready_o;


    assign config_ready_o = (current_state == IDLE) && !debug_en_i;
    assign spin_ready_o = (current_state == IDLE) && !debug_en_i && (!config_valid_i);
    assign weight_ready_o = ((current_state == COMPUTE_STANDARD) || (current_state == COMPUTE_NONSTANDARD)) && (!counter_ready_i) && (!debug_en_i);
    assign energy_valid_comb = ((current_state == COMPUTE_STANDARD) || (current_state == COMPUTE_NONSTANDARD)) && counter_ready_pipe[PIPESMID] && cmpt_done_i;

    // Pipeline counter_ready_i signal
    assign counter_ready_pipe[0] = counter_ready_i;
    assign spin_handshake_pipe[0] = spin_handshake;
    generate
        genvar i;
        for (i = 0; i < PIPESMID; i++) begin : gen_counter_ready_pipe_loop
            `FFL(counter_ready_pipe[i+1], counter_ready_pipe[i], en_i, 1'b0, clk_i, rst_ni);
        end
    endgenerate

     generate
        genvar j;
        for (j = 0; j < 3; j++) begin : gen_spin_ready_pipe_loop
            `FFL(spin_handshake_pipe[j+1], spin_handshake_pipe[j], en_i, 1'b0, clk_i, rst_ni);
        end
    endgenerate

    `FFLARNC(energy_valid_reg, 1'b1, energy_valid_comb, energy_ready_i, 1'b0, clk_i, rst_ni)
    assign energy_valid_o = energy_valid_comb || energy_valid_reg;

    `FFL(current_state, next_state, en_i, IDLE, clk_i, rst_ni)

    always_comb begin
        next_state = current_state;
        case (current_state)
            IDLE: begin
                if (debug_en_i)
                    next_state = IDLE; // stay in IDLE in debug mode
                else begin
                    if ((standard_mode_i || first_operation_sampled_i) && spin_handshake)
                        next_state = COMPUTE_STANDARD;
                    else if (!standard_mode_i && !first_operation_sampled_i && max_flipped_count_valid)
                        next_state = COMPUTE_NONSTANDARD;
                end
            end
            COMPUTE_STANDARD: begin
                if (debug_en_i)
                    next_state = COMPUTE_STANDARD; // stay in COMPUTE_STANDARD in debug mode
                else begin
                    if (energy_handshake)
                        next_state = IDLE;
                    else
                        next_state = COMPUTE_STANDARD;
                end
            end
            COMPUTE_NONSTANDARD: begin
                if (debug_en_i)
                    next_state = COMPUTE_NONSTANDARD; // stay in COMPUTE_NONSTANDARD in debug mode
                else begin
                    if (energy_handshake)
                        next_state = IDLE;
                    else
                        next_state = COMPUTE_NONSTANDARD;
                end
            end
            default: begin
                next_state = IDLE;
            end
        endcase
    end
endmodule