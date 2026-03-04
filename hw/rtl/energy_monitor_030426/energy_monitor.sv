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

//Emirhan Notes: When we calculate the energy difference with some of the J columns, the biases of the other columns are not considered. Might need to fix that.
//

`include "common_cells/registers.svh"

`define True 1'b1
`define False 1'b0

module energy_monitor #(
    parameter int BITJ = 4,
    parameter int BITH = 4,
    parameter int DATASPIN = 256,
    parameter int SCALING_BIT = 4,
    parameter int PARALLELISM = 4,
    parameter int ENERGY_TOTAL_BIT = 32,
    parameter int LITTLE_ENDIAN = `True,
    parameter int PIPESINTF = 0,
    parameter int PIPESMID = 0,
    parameter int LOCAL_ENERGY_BIT = $clog2(DATASPIN) + BITH + SCALING_BIT - 1,
    parameter int DATAJ = DATASPIN * BITJ * PARALLELISM,
    parameter int DATAH = BITH * PARALLELISM,
    parameter int DATASCALING = SCALING_BIT * PARALLELISM,
    parameter int SPINIDX_BIT = $clog2(DATASPIN)
)(
    input logic clk_i,
    input logic rst_ni,
    input logic en_i,
    input logic standart_mode_i, // Enables energy difference calculation mode if it is 0
    input logic first_operation_i, 
    // new signal to indicate if it's the first operation (no spin flip masking),
    // assumed it comes from outside for simplicity,
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

    output logic energy_valid_o,
    input logic energy_ready_i,
    output logic signed [ENERGY_TOTAL_BIT-1:0] energy_o;
    output logic [$clog2(DATASPIN / PARALLELISM)-1:0] weight_raddr_em_o,
    // Store accumulator output when energy_valid_o is high
    logic signed [ENERGY_TOTAL_BIT-1:0] energy_o_stored;
);
    // pipe all input signals
    logic config_valid_pipe;
    logic [SPINIDX_BIT-1:0] config_counter_pipe;
    logic config_ready_pipe;

    logic [DATASPIN-1:0] spin_pipe;
    logic spin_valid_pipe;
    logic spin_valid_pipe_sampled;
    logic spin_ready_pipe;

    logic [DATAJ-1:0] weight_pipe;
    logic signed [DATAH-1:0] hbias_pipe;
    logic signed [DATAH-1:0] hbias_conditional;
    logic unsigned [DATASCALING-1:0] hscaling_pipe;
    logic weight_valid_pipe;
    logic weight_ready_pipe;

    // internal signals
    logic [DATASPIN-1:0] spin_flipped;
    logic [DATASPIN-1:0] spin_unflipped;
    logic [DATASPIN-1:0] spin_cached;
    logic [DATASPIN-1:0] spin_cached_reg;
    logic [SPINIDX_BIT-1:0] flipped_count;
    logic [SPINIDX_BIT-1:0] counter_q;
    logic [SPINIDX_BIT-1:0] counter_q_diff;
    logic counter_ready;
    logic counter_ready_diff;
    logic first_operation_sampled;
    logic max_flipped_count_valid;
    logic energy_valid_o_d;
    logic energy_valid_o_pulse;
    logic cmpt_done;
    logic [PARALLELISM-1:0] current_spin;
    logic [PARALLELISM-1:0] current_spin_raw;
    logic signed [LOCAL_ENERGY_BIT*PARALLELISM-1:0] local_energy;
    logic signed [LOCAL_ENERGY_BIT + $clog2(PARALLELISM) - 1:0] local_energy_parallel;
    logic [DATAJ-1:0] weight_masked;
    logic [DATAJ-1:0] weight_selected;
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] flipped_count [PARALLELISM-1:0];
    logic [$clog2(DATASPIN/PARALLELISM+1)-1:0] max_flipped_count;

    // handshake signals
    logic accum_prev_energy_valid;
    logic spin_handshake;
    logic spin_handshake_sampled;
    logic weight_handshake;
    logic energy_handshake;
    logic [PIPESMID:0] weight_handshake_accum;
  


    genvar i;
    genvar i_weight_raddr;

    assign counter_spin_o = counter_q;
    assign spin_handshake = spin_valid_pipe && spin_ready_pipe;
    assign weight_handshake = weight_valid_pipe && weight_ready_pipe;
    assign energy_handshake = energy_valid_o && energy_ready_i;
    assign weight_handshake_accum[0] = weight_handshake;
    assign energy_valid_o_pulse = energy_valid_o & ~energy_valid_o_d;
    //Might need to use spin_ready_o signal of the control unit
    assign accum_prev_energy_valid = spin_handshake && !first_operation_sampled && !standart_mode_i;
    generate
        for (i = 0; i < PIPESMID; i++) begin: gen_weight_handshake_accum
            `FFL(weight_handshake_accum[i+1], weight_handshake_accum[i], en_i, 1'b0, clk_i, rst_ni);
        end
    endgenerate

    // pipeline interfaces
    bp_pipe #(
        .DATAW(SPINIDX_BIT),
        .PIPES(PIPESINTF)
    ) u_pipe_config (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .data_i(config_counter_i),
        .data_o(config_counter_pipe),
        .valid_i(config_valid_i),
        .valid_o(config_valid_pipe),
        .ready_i(config_ready_pipe),
        .ready_o(config_ready_o)
    );
    bp_pipe #(
        .DATAW(DATASPIN),
        .PIPES(PIPESINTF)
    ) u_pipe_spin (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .data_i(spin_i),
        .data_o(spin_pipe),
        .valid_i(spin_valid_i),
        .valid_o(spin_valid_pipe),
        .ready_i(spin_ready_pipe),
        .ready_o(spin_ready_o)
    );
    // Mask only the weights at the fetched positions (using counter_q_diff and valid bits) before the bp_pipe
    logic [DATAJ-1:0] weight_i_masked;
    always_comb begin
        weight_i_masked = weight_i; // default: pass through
        if (!standart_mode_i && !first_operation_sampled) begin
            for (int i = 0; i < PARALLELISM; i++) begin
                if (!gen_find_all_ones[i].flipped_valid[counter_q_diff]) begin
                    // Mask all weights for this parallel unit
                    for (int j = 0; j < DATASPIN; j++) begin
                        weight_i_masked[i*BITJ*DATASPIN + j*BITJ +: BITJ] = '0;
                    end
                end else begin
                    // Pass through all weights for this parallel unit
                    for (int j = 0; j < DATASPIN; j++) begin
                        weight_i_masked[i*BITJ*DATASPIN + j*BITJ +: BITJ] = weight_i[i*BITJ*DATASPIN + j*BITJ +: BITJ];
                    end
                end
            end
        end
    end
    bp_pipe #(
        .DATAW(DATAJ + DATAH + DATASCALING),
        .PIPES(PIPESINTF)
    ) u_pipe_weight (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .data_i({weight_i_masked, hbias_i, hscaling_i}),
        .data_o({weight_pipe, hbias_pipe, hscaling_pipe}),
        .valid_i(weight_valid_i),
        .valid_o(weight_valid_pipe),
        .ready_i(weight_ready_pipe),
        .ready_o(weight_ready_o)
    );
    `FF(spin_valid_pipe_sampled, spin_valid_pipe, 1'b0, clk_i, rst_ni)
    // Logic FSM
    logic_ctrl #(
        .PIPESMID(PIPESMID)
    ) u_logic_ctrl (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .config_valid_i(config_valid_pipe),
        .config_ready_o(config_ready_pipe),
        .spin_valid_i((standart_mode_i | first_operation_sampled) ? spin_valid_pipe : spin_valid_pipe_sampled),
        .spin_ready_o(spin_ready_pipe),
        .weight_valid_i(weight_valid_pipe),
        .weight_ready_o(weight_ready_pipe),
        .counter_ready_i((standart_mode_i | first_operation_sampled) ? counter_ready : counter_ready_diff),
        .cmpt_done_i((standart_mode_i | first_operation_sampled) ? cmpt_done : cmpt_done_diff),
        .energy_valid_o(energy_valid_o),
        .energy_ready_i(energy_ready_i),
        .debug_en_i(1'b0) // disable debug_en_i
    );

    // Counter path
    step_counter #(
        .COUNTER_BITWIDTH(SPINIDX_BIT),
        .PARALLELISM(PARALLELISM)
    ) u_step_counter (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i ),
        .load_i(config_valid_pipe && config_ready_pipe),
        .d_i(config_counter_pipe),
        .recount_en_i(spin_handshake),
        .step_en_i(weight_handshake),
        .q_o(counter_q),
        .overflow_o(counter_ready)
    );
    //Todo: need to ensure  the connections of the new counter;config_valid
      // Counter path for energy difference calculation
    step_counter #(
        .COUNTER_BITWIDTH(SPINIDX_BIT),
        .PARALLELISM(1) // Always 1 
    ) u_step_counter_diff (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i && !standart_mode_i && !first_operation_sampled),
        .load_i(max_flipped_count_valid),
        .d_i(max_flipped_count),
        .recount_en_i(spin_handshake),
        .step_en_i(weight_handshake),
        .q_o(counter_q_diff),
        .overflow_o(counter_ready_diff)
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

    // Generate flipped/unflipped spin vectors
    spin_flip_detector #(
        .DATAWIDTH(DATASPIN)
    ) u_spin_flipped (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .data_valid_i(spin_handshake),
        .spin_previous_i(spin_cached_reg),
        .spin_i(spin_pipe),
        .spin_flipped_o(spin_flipped),
        .spin_unflipped_o(spin_unflipped)
    );

    // Count number of flipped bits using parallel population counters
    // when spin_handshake goes from 1 to 0, spin_flipped is generated based on previous and current spins
    // Each counter processes interleaved bits: counter[i] gets bits i, i+PARALLELISM, i+2*PARALLELISM, ...
    generate
        for (i = 0; i < PARALLELISM; i++) begin: gen_popcount_parallel
            localparam int BITS_PER_TREE = DATASPIN / PARALLELISM;
            logic [BITS_PER_TREE-1:0] spin_flipped_interleaved;
            
            // Extract interleaved bits for this tree
            for (genvar j = 0; j < BITS_PER_TREE; j++) begin
                assign spin_flipped_interleaved[j] = spin_flipped[j * PARALLELISM + i];
            end
            
            adder_tree_unsigned #(
                .N(BITS_PER_TREE),
                .DATAW(1),
                .PIPES(0)
            ) u_popcount_flipped (
                .clk_i(clk_i),
                .rst_ni(rst_ni),
                .en_i(en_i),
                .data_valid_i(spin_handshake),
                .data_i(spin_flipped_interleaved),
                .sum_o(flipped_count[i]),
                .data_valid_o(spin_handshake_sampled) // 
            );
        end
    endgenerate
   
    // Find maximum flipped count
    find_max #(
        .N(PARALLELISM),
        .DATAW(DATASPIN/PARALLELISM)
    ) u_find_max (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .valid_i(spin_handshake_sampled),
        .data_i(flipped_count),
        .valid_o(max_flipped_count_valid),
        .max_o(max_flipped_count)
    );
    // Find all '1' positions in flipped spin vector
    generate
    for (i = 0; i < PARALLELISM; i++) begin: gen_find_all_ones
        localparam int BITS_PER_CHUNK = DATASPIN / PARALLELISM;
        logic [BITS_PER_CHUNK-1:0] spin_flipped_interleaved;
        logic [BITS_PER_CHUNK-1:0][`LOG2UP(BITS_PER_CHUNK)-1:0] flipped_positions;
        logic [BITS_PER_CHUNK-1:0] flipped_valid;

        // Extract interleaved bits for this chunk
        for (genvar j = 0; j < BITS_PER_CHUNK; j++) begin
            assign spin_flipped_interleaved[j] = spin_flipped[j * PARALLELISM + i];
        end

        find_all_ones_iterative #(
            .N(BITS_PER_CHUNK)
        ) u_find_all_ones (
            .clk_i(clk_i),
            .rst_ni(rst_ni),
            .start_i(spin_handshake_sampled), // or another suitable handshake
            .data_i(spin_flipped_interleaved),
            .positions(flipped_positions),
            .valid_o(flipped_valid),
            .count(), // connect if needed
            .done(),  // connect if needed
            .empty_o() // connect if needed
        );
    end
endgenerate

    // ToDo: I can sort the flipped spins bank by bank to reduce conflict misses

    // Mask weights with spin_unflipped bits
    // For each parallel unit, mask its weight array based on flipped spins
    // Mask all weights for a spin if that spin is flipped
    generate
        for (int j = 0; j < DATASPIN; j++) begin: mask_weights_by_spin
            for (int i = 0; i < PARALLELISM; i++) begin
                assign weight_masked[i*BITJ*DATASPIN + j*BITJ +: BITJ] = 
                    spin_unflipped[j] ? weight_pipe[i*BITJ*DATASPIN + j*BITJ +: BITJ] : '0;
            end
        end
    endgenerate

    // Select between masked and unmasked weights based on first_operation_i
    assign weight_selected = (first_operation_sampled | standart_mode_i) ? weight_pipe : weight_masked;
    // Todo : For nonstandart mode; need to do correct mapping of spin_cached and counter_q_diff
    // N-to-PARALLELISM mux for a vector
    generate
        for (genvar i = 0; i < PARALLELISM; i++) begin: gen_current_spin_raw
            if (LITTLE_ENDIAN == `True) begin
                always_comb begin
                    if (first_operation_sampled | standart_mode_i) begin
                        current_spin_raw[i] = en_i ? spin_cached[counter_q + i] : 1'b0;
                    end else begin
                        current_spin_raw[i] = en_i ? spin_cached[PARALLELISM * gen_find_all_ones[i].flipped_positions[counter_q_diff] + i] : 1'b0;
                    end
                end
            end else begin
                always_comb begin
                    if (first_operation_sampled | standart_mode_i) begin
                        current_spin_raw[i] = en_i ? spin_cached[DATASPIN - 1 - counter_q - i] : 1'b0;
                    end else begin
                        current_spin_raw[i] = en_i ? spin_cached[DATASPIN - 1 - (PARALLELISM * gen_find_all_ones[i].flipped_positions[counter_q_diff] + i)] : 1'b0;
                    end
                end
            end
        end
    endgenerate

    // map raw bits to current_spin
    generate
        for (i = 0; i < PARALLELISM; i = i + 1) begin: map_current_spin
            if (LITTLE_ENDIAN == `True) begin
                assign current_spin[i] = current_spin_raw[i];
            end else begin
                assign current_spin[i] = current_spin_raw[PARALLELISM - 1 - i];
            end
        end
    endgenerate

    // Energy calculation and accumulation
    // Conditionally zero hbias if not first_operation or standart_mode
    always_comb begin
        if (first_operation_sampled || standart_mode_i) begin
            hbias_conditional = hbias_pipe;
        end else begin
            hbias_conditional = '0;
        end
    end
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
                .weight_i(weight_selected[i*BITJ*DATASPIN +: BITJ*DATASPIN]),
                .hbias_i(hbias_conditional[i*BITH +: BITH]),
                .hscaling_i(hscaling_pipe[i*SCALING_BIT +: SCALING_BIT]),
                .energy_o(local_energy[i*LOCAL_ENERGY_BIT +: LOCAL_ENERGY_BIT])
            );
        end
    endgenerate

    // Sum the parallel local energy
    always_comb begin
        local_energy_parallel = '0;
        for (int i = 0; i < PARALLELISM; i++) begin
            local_energy_parallel += $signed(local_energy[i*LOCAL_ENERGY_BIT +: LOCAL_ENERGY_BIT]);
        end
    end
    assign accum_data_in = accum_prev_energy_valid ? energy_o_stored : local_energy_parallel;
    assign accum_valid_in = accum_prev_energy_valid ? accum_prev_energy_valid : weight_handshake_accum[PIPESMID];
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
    // sets to 1 on  first_operation_i, clears on energy_handshake
    `FFLARNC(first_operation_sampled, 1'b1, first_operation_i, energy_handshake, 1'b0, clk_i, rst_ni)
    // Generate a one-cycle pulse on energy_valid_o to load energy_o using a register
    `FF(energy_valid_o_d, energy_valid_o, 1'b0, clk_i, rst_ni)
   

    // Assign weight_raddr_em_o for each parallel unit (at end of module)
    generate
        for (i_weight_raddr = 0; i_weight_raddr < PARALLELISM; i_weight_raddr = i_weight_raddr + 1) begin : gen_weight_raddr_em_o
            always_comb begin
                if (first_operation_sampled || standart_mode_i) begin
                    weight_raddr_em_o[i_weight_raddr] = counter_q / PARALLELISM;
                end else begin
                    weight_raddr_em_o[i_weight_raddr] = PARALLELISM * gen_find_all_ones[i_weight_raddr].flipped_positions[counter_q_diff] + i_weight_raddr;
                end
            end
        end
    endgenerate

endmodule
