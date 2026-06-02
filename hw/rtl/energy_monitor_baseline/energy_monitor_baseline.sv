// Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Author: Jiacong Sun <jiacong.sun@kuleuven.be>
//
// Module description:
// Energy monitor module.
//
// Parameters:
// - BITJ: bit precision of J
// - BITH: bit precision of h
// - DATASPIN: number of spins, must be multiple of PARALLELISM
// - SCALING_BIT: number of bits of scaling factor for h
// - PARALLELISM: number of parallel energy calculation units
// - LOCAL_ENERGY_BIT: bit precision of partial energy value
// - ENERGY_TOTAL_BIT: bit precision of total energy value
// - LITTLE_ENDIAN: storage format of weight matrix and spin vector, 1 for little-endian, 0 for big-endian
// - PIPESINTF: number of pipeline stages for each input path interface
// - PIPESMID: number of pipeline stages at the middle adder tree interface
//
// Port definitions:
// - clk_i: input clock signal
// - rst_ni: asynchornous reset, active low
// - en_i: module enable signal
// - config_valid_i: input config valid signal
// - config_counter_i: configuration counter
// - config_ready_o: output config ready signal
// - spin_valid_i: input spin valid signal
// - spin_i: input spin data
// - spin_ready_o: output spin ready signal
// - weight_valid_i: input weight valid signal
// - weight_i: input weight data
// - hbias_i: h bias
// - hscaling_i: h scaling factor
// - weight_ready_o: output weight ready signal
// - energy_valid_o: output energy valid signal
// - energy_ready_i: input energy ready signal
// - energy_o: output energy value
// - debug_en_i: debug enable signal
//
// Case tested:
// - BITJ=4, BITH=4, DATASPIN=256, SCALING_BIT=5, LOCAL_ENERGY_BIT=16, ENERGY_TOTAL_BIT=32, PIPESINTF=0/1/2
// -- All spins are 1, all weights are +1, hbias=+1, hscaling=1, 20 same cases
// -- All spins are 0, all weights are +1, hbias=+1, hscaling=1, 20 same cases
// -- All spins are 0, all weights are -1, hbias=-1, hscaling=1, 20 same cases
// -- All spins are 1, all weights are -1, hbias=-1, hscaling=1, 20 same cases
// -- All spins are 1, all weights are +7, hbias=+7, hscaling=16, 20 same cases
// -- All spins are 0, all weights are -7, hbias=-7, hscaling=16, 20 same cases
// -- All spins and weights are random, hbias and hscaling are random, 1,000,000 different cases
//Emirhan Notes: this is fast mode and I need to ignore first operation otherwise it wont stuck first operation should be zero all the time oon testbench
//First operation might be created when enable signal becomes high but need to know how we use enable signal exactly
`include "../include/registers.svh"
`define True 1'b1
`define False 1'b0
`define LOG2UP(x)   (((x) > 1) ? $clog2(x) : 1)
module energy_monitor_baseline #(
    parameter int BITJ = 4,
    parameter int BITH = 4,
    parameter int DATASPIN = 256,
    parameter int SCALING_BIT = 4,
    parameter int PARALLELISM = 4,
    parameter int ENERGY_TOTAL_BIT = 32,
    parameter int LITTLE_ENDIAN = `True,
    parameter int PIPESINTF = 0,
    parameter int PIPESMID = 0,
    parameter int LOCAL_ENERGY_BIT = $clog2(DATASPIN) + BITH + SCALING_BIT ,
    parameter int DATAJ = DATASPIN * BITJ * PARALLELISM,
    parameter int DATAH = BITH * PARALLELISM,
    parameter int DATASCALING = SCALING_BIT * PARALLELISM,
    parameter int SPINIDX_BIT = $clog2(DATASPIN)
)(
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    // we can even have a normal mode to avoid any bug related to new implementation
    input logic config_valid_i,
    input logic [SPINIDX_BIT-1:0] config_counter_i,
    output logic config_ready_o,

    input logic spin_valid_i,
    input logic [DATASPIN-1:0] spin_i,
    output logic spin_ready_o,

    input logic weight_valid_i,
    input logic [DATAJ-1:0] weight_i,
    input logic [DATAH-1:0] hbias_i,
    input logic [DATASCALING-1:0] hscaling_i,
    output logic weight_ready_o,
    output logic [SPINIDX_BIT-1:0] counter_spin_o,
    // Parallel output for weight_raddr_em_o
    output logic [PARALLELISM-1:0][$clog2(DATASPIN / PARALLELISM)-1:0] weight_raddr_em_o,
    // Per-lane valid for weight_raddr_em_o to gate SRAM reads in top wrapper
    output logic [PARALLELISM-1:0] weight_raddr_valid_em_o,

    output logic energy_valid_o,
    input logic energy_ready_i,
    output logic signed [ENERGY_TOTAL_BIT-1:0] energy_o
);
    // pipe all input signals
    logic config_valid_pipe;
    logic [SPINIDX_BIT-1:0] config_counter_pipe;
    logic config_ready_pipe;
    logic [DATASPIN-1:0] spin_pipe;
    logic spin_valid_pipe;
    logic spin_ready_pipe;
    logic [DATAJ-1:0] weight_pipe;
    logic signed [DATAH-1:0] hbias_pipe;
    logic unsigned [DATASCALING-1:0] hscaling_pipe;
    logic weight_valid_pipe;
    logic weight_ready_pipe;

    logic weight_ready_masked;
    logic [DATASPIN-1:0] spin_flipped;
    logic [DATASPIN-1:0] spin_unflipped;
    logic [DATASPIN-1:0] spin_cached;
    logic [DATASPIN-1:0] spin_cached_reg;
    logic [SPINIDX_BIT-1:0] counter_q;
    logic [SPINIDX_BIT-1:0] counter_q_diff;
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] counter_q_sram;
    
    logic counter_ready_diff;
    logic counter_ready_sram;
    logic counter_load_sram;
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] counter_d_sram;
    logic first_operation_sampled;
    logic max_flipped_count_valid;

    logic energy_valid_o_pulse;
    logic cmpt_done;
    logic [PARALLELISM-1:0] current_spin;
    logic [PARALLELISM-1:0] current_spin_raw;
    logic signed [PARALLELISM-1:0][LOCAL_ENERGY_BIT-1:0] local_energy;
    logic signed [LOCAL_ENERGY_BIT + $clog2(PARALLELISM) - 1:0] local_energy_parallel;
     // Store accumulator output when energy_valid_o is high
    logic signed [ENERGY_TOTAL_BIT-1:0] energy_o_stored;

    
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] flipped_count [PARALLELISM-1:0];
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] max_flipped_count;

    logic signed [ENERGY_TOTAL_BIT-1:0] accum_data_in;
    logic accum_valid_in;
    // Arrays for legal variable indexing
    localparam int BITS_PER_CHUNK = DATASPIN / PARALLELISM;
    logic [PARALLELISM-1:0][BITS_PER_CHUNK-1:0] flipped_valid_array;
    logic [PARALLELISM-1:0][BITS_PER_CHUNK-1:0][`LOG2UP(BITS_PER_CHUNK)-1:0] flipped_positions_array;

    // handshake signals
    logic accum_prev_energy_valid;
    logic spin_handshake;
    logic spin_handshake_d;
    logic spin_handshake_pulse;
    logic [PARALLELISM-1:0] spin_handshake_sampled;
    logic weight_handshake;
    logic energy_handshake;
    logic [PIPESMID:0] weight_handshake_accum;
    localparam logic signed [ENERGY_TOTAL_BIT-1:0] ENERGY_RESET = 0;
  
    genvar i,j;
    genvar i_weight_raddr;

   
    `FFL(spin_handshake_d, spin_handshake, 1'b1, 1'b0, clk_i, rst_ni)
    `FFL(energy_o_stored, energy_o, energy_valid_o_pulse, ENERGY_RESET, clk_i, rst_ni)
    assign spin_ready_o = spin_ready_pipe;
    assign weight_ready_masked = weight_ready_pipe;
    assign weight_ready_o = weight_ready_masked;
    assign counter_q = counter_q_diff; // Use the counter that controls the spin vector caching and current_spin assignment
    assign counter_spin_o = counter_q;
    assign spin_handshake = spin_valid_pipe && spin_ready_pipe;
    assign spin_handshake_pulse = spin_handshake && !spin_handshake_d;
    assign weight_handshake = weight_valid_pipe && weight_ready_masked;
    assign energy_handshake = energy_valid_o && energy_ready_i;
    assign weight_handshake_accum[0] = weight_handshake;

    //Might need to use spin_ready_o signal of the control unit

    assign accum_data_in = local_energy_parallel;
    assign accum_valid_in = weight_handshake_accum[PIPESMID];
    generate
        for (i = 0; i < PIPESMID; i++) begin: gen_weight_handshake_accum
            `FFL(weight_handshake_accum[i+1], weight_handshake_accum[i], en_i, 1'b0, clk_i, rst_ni)
        end
    endgenerate

    // Input interface signals are used directly to remove the fixed PIPESINTF latency.
    assign config_counter_pipe = config_counter_i;
    assign config_valid_pipe = config_valid_i;
    assign config_ready_o = config_ready_pipe;

    assign spin_pipe = spin_i;
    assign spin_valid_pipe = spin_valid_i;

    assign {weight_pipe, hbias_pipe, hscaling_pipe} = {weight_i, hbias_i, hscaling_i};
    assign weight_valid_pipe = weight_valid_i;
    // Logic FSM
    logic_ctrl #(
        .PIPESMID(PIPESMID),
        .MAX_FLIPPED_COUNT_W($clog2(DATASPIN/PARALLELISM+1))
    ) u_logic_ctrl (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .config_valid_i(config_valid_pipe),
        .config_ready_o(config_ready_pipe),
        .spin_valid_i(spin_valid_pipe),
        .spin_ready_o(spin_ready_pipe),
        .weight_valid_i(weight_valid_pipe),
        .weight_ready_o(weight_ready_pipe),
        .counter_ready_i(counter_ready_diff),
        .cmpt_done_i(cmpt_done),
        .energy_valid_o(energy_valid_o),
        .energy_ready_i(energy_ready_i),
        .debug_en_i(1'b0) // disable debug_en_i
    );
    
    
    step_counter #(
        .COUNTER_BITWIDTH(SPINIDX_BIT),
        .PARALLELISM(PARALLELISM) // Always 1 
    ) u_step_counter_diff (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i ),
        .load_i(config_valid_pipe && config_ready_pipe),
        .d_i(config_counter_pipe),
        .recount_en_i(spin_handshake),
        .step_en_i(weight_handshake),
        .q_o(counter_q_diff),
        .overflow_o(counter_ready_diff)
    );

    always_comb begin
  
            counter_load_sram = config_valid_pipe && config_ready_pipe;
            counter_d_sram = config_counter_pipe / PARALLELISM;
        
    end

     // Counter to control SRAM accesses
    step_counter #(
        .COUNTER_BITWIDTH($clog2(DATASPIN/PARALLELISM+1)),
        .PARALLELISM(1) // Always 1 
    ) u_step_counter_sram (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .load_i(counter_load_sram),
        .d_i(counter_d_sram),
        .recount_en_i(spin_handshake),
        .step_en_i(weight_ready_pipe),
        .q_o(counter_q_sram),
        .overflow_o(counter_ready_sram)
    );

    // Spin path
    vector_caching #(
        .DATAWIDTH(DATASPIN)
    ) u_spin_cache (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .data_valid_i(spin_handshake),
        .data_i(spin_pipe),
        .data_o(spin_cached),
        .data_cached_o(spin_cached_reg) // Updated 1 cycle later than spin_cached
    );

   




    
    

    generate
        for (genvar i = 0; i < PARALLELISM; i++) begin: gen_current_spin_raw
            if (LITTLE_ENDIAN == `True) begin
                always_comb begin
                   current_spin_raw[i] = en_i ? spin_cached[counter_q + i] : 1'b0;
                end
            end else begin
                always_comb begin
                   current_spin_raw[i] = en_i ? spin_cached[DATASPIN - 1 - counter_q - i] : 1'b0;
                end
            end
        end
    endgenerate

    // map raw bits to current_spin, I guess this is redundant after assigning current_spin_raw in a loop above
    generate
        for (i = 0; i < PARALLELISM; i = i + 1) begin: map_current_spin
            if (LITTLE_ENDIAN == `True) begin
                assign current_spin[i] = current_spin_raw[i];
            end else begin
                assign current_spin[i] = current_spin_raw[i]; //assign current_spin[i] = current_spin_raw[PARALLELISM - 1 - i];
            end
        end
    endgenerate
    // Energy calculation and accumulation
    // Conditionally zero hbias if not first_operation or standard_mode

    generate
        for (i = 0; i < PARALLELISM; i = i + 1) begin: partial_energy_calc_inst
            partial_energy_calc #(
                .BITJ(BITJ),
                .BITH(BITH),
                .DATASPIN(DATASPIN),
                .SCALING_BIT(SCALING_BIT),
                .PIPES(PIPESMID)
            ) u_partial_energy_calc (
                .clk_i(clk_i),
                .rst_ni(rst_ni),
                .en_i(en_i),
                .data_valid_i(weight_handshake),
                .spin_vector_i(spin_cached),
                .current_spin_i(current_spin[i]),
                .weight_i(weight_pipe[i*BITJ*DATASPIN +: BITJ*DATASPIN]),
                .hbias_i(hbias_pipe[i*BITH +: BITH]),
                .hscaling_i(hscaling_pipe[i*SCALING_BIT +: SCALING_BIT]),
                .energy_o(local_energy[i])
            );
        end
    endgenerate

    // Sum the parallel local energy
    always_comb begin
        local_energy_parallel = '0;
        for (int i = 0; i < PARALLELISM; i++) begin
            local_energy_parallel +=  $signed(local_energy[i]);
        end
    end

    // Accumulator
    accumulator #(
        .IN_WIDTH(ENERGY_TOTAL_BIT ),// Changed the input bit width to since we accumulate the stored energy
        .ACCUM_WIDTH(ENERGY_TOTAL_BIT)
    ) u_accumulator (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .clear_i(energy_handshake), // clear when the output energy is accepted
        .valid_i(accum_valid_in),
        .data_i(accum_data_in),
        .accum_o(energy_o),
        .overflow_o(),
        .valid_o(cmpt_done)
    );
   
    // Assign weight_raddr_em_o for each parallel unit (at end of module)
    generate
        for (i_weight_raddr = 0; i_weight_raddr < PARALLELISM; i_weight_raddr = i_weight_raddr + 1) begin : gen_weight_raddr_em_o
            always_comb begin
                    weight_raddr_em_o[i_weight_raddr] = counter_q_sram;
                    weight_raddr_valid_em_o[i_weight_raddr] = 1'b1;
               
            end
        end
    endgenerate

endmodule
