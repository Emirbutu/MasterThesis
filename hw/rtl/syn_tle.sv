// Copyright 2026 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef True
`define True 1'b1
`endif

// Synthesis wrapper placing energy_monitor between an input and output elastic buffer.
module syn_tle #(
    parameter int BITJ = 4,
    parameter int BITH = 4,
    parameter int DATASPIN = 256,
    parameter int SCALING_BIT = 4,
    parameter int PARALLELISM = 4,
    parameter int ENERGY_TOTAL_BIT = 32,
    parameter int LITTLE_ENDIAN = `True,
    parameter int PIPESINTF = 1,
    parameter int PIPESMID = 1,
    parameter int INPUT_PASSTHRU = 0,
    parameter int OUTPUT_PASSTHRU = 0,
    parameter int SPINIDX_BIT = $clog2(DATASPIN),
    parameter int DATAJ = DATASPIN * BITJ * PARALLELISM,
    parameter int DATAH = BITH * PARALLELISM,
    parameter int DATASCALING = SCALING_BIT * PARALLELISM,
    parameter int WEIGHT_ADDRW = $clog2(DATASPIN / PARALLELISM),
    parameter int WEIGHT_ADDR_BUSW = PARALLELISM * WEIGHT_ADDRW,
    parameter int IN_DATAW = 1 + 1 + 1 + 1 + SPINIDX_BIT + 1 + DATASPIN + 1 + DATAJ + DATAH + DATASCALING,
    parameter int OUT_DATAW = 1 + 1 + 1 + SPINIDX_BIT + WEIGHT_ADDR_BUSW + ENERGY_TOTAL_BIT
) (
    input  wire                 clk,
    input  wire                 reset,
    input  wire                 valid_in,
    output wire                 ready_in,
    input  wire [IN_DATAW-1:0]  data_in,
    output wire                 valid_out,
    input  wire                 ready_out,
    output wire [OUT_DATAW-1:0] data_out
);
    wire [IN_DATAW-1:0] ib_data_out;
    wire ib_valid_out;
    wire ib_ready_in;

    VX_pipe_buffer #(
        .DATAW(IN_DATAW),
        .PASSTHRU(INPUT_PASSTHRU)
    ) input_buffer (
        .clk      (clk),
        .reset    (reset),
        .valid_in (valid_in),
        .ready_in (ready_in),
        .data_in  (data_in),
        .data_out (ib_data_out),
        .ready_out(ib_ready_in),
        .valid_out(ib_valid_out)
    );

    localparam int IN_LSB_EN = 0;
    localparam int IN_LSB_STD_MODE = IN_LSB_EN + 1;
    localparam int IN_LSB_FIRST_OP = IN_LSB_STD_MODE + 1;
    localparam int IN_LSB_CFG_VALID = IN_LSB_FIRST_OP + 1;
    localparam int IN_LSB_CFG_COUNTER = IN_LSB_CFG_VALID + 1;
    localparam int IN_LSB_SPIN_VALID = IN_LSB_CFG_COUNTER + SPINIDX_BIT;
    localparam int IN_LSB_SPIN = IN_LSB_SPIN_VALID + 1;
    localparam int IN_LSB_WEIGHT_VALID = IN_LSB_SPIN + DATASPIN;
    localparam int IN_LSB_WEIGHT = IN_LSB_WEIGHT_VALID + 1;
    localparam int IN_LSB_HBIAS = IN_LSB_WEIGHT + DATAJ;
    localparam int IN_LSB_HSCALING = IN_LSB_HBIAS + DATAH;

    wire in_en;
    wire in_standard_mode;
    wire in_first_operation;
    wire in_config_valid;
    wire [SPINIDX_BIT-1:0] in_config_counter;
    wire in_spin_valid;
    wire [DATASPIN-1:0] in_spin;
    wire in_weight_valid;
    wire [DATAJ-1:0] in_weight;
    wire [DATAH-1:0] in_hbias;
    wire [DATASCALING-1:0] in_hscaling;

    assign in_en = ib_data_out[IN_LSB_EN +: 1];
    assign in_standard_mode = ib_data_out[IN_LSB_STD_MODE +: 1];
    assign in_first_operation = ib_data_out[IN_LSB_FIRST_OP +: 1];
    assign in_config_valid = ib_data_out[IN_LSB_CFG_VALID +: 1];
    assign in_config_counter = ib_data_out[IN_LSB_CFG_COUNTER +: SPINIDX_BIT];
    assign in_spin_valid = ib_data_out[IN_LSB_SPIN_VALID +: 1];
    assign in_spin = ib_data_out[IN_LSB_SPIN +: DATASPIN];
    assign in_weight_valid = ib_data_out[IN_LSB_WEIGHT_VALID +: 1];
    assign in_weight = ib_data_out[IN_LSB_WEIGHT +: DATAJ];
    assign in_hbias = ib_data_out[IN_LSB_HBIAS +: DATAH];
    assign in_hscaling = ib_data_out[IN_LSB_HSCALING +: DATASCALING];

    wire dut_config_ready;
    wire dut_spin_ready;
    wire dut_weight_ready;
    wire [SPINIDX_BIT-1:0] dut_counter_spin;
    wire [PARALLELISM-1:0][WEIGHT_ADDRW-1:0] dut_weight_raddr;
    wire dut_energy_valid;
    wire dut_energy_ready;
    wire signed [ENERGY_TOTAL_BIT-1:0] dut_energy;

    wire ib_cfg_fire;
    wire ib_spin_fire;
    wire ib_weight_fire;

    assign ib_cfg_fire = (~(ib_valid_out && in_config_valid)) || dut_config_ready;
    assign ib_spin_fire = (~(ib_valid_out && in_spin_valid)) || dut_spin_ready;
    assign ib_weight_fire = (~(ib_valid_out && in_weight_valid)) || dut_weight_ready;
    assign ib_ready_in = ib_cfg_fire && ib_spin_fire && ib_weight_fire;

    energy_monitor #(
        .BITJ(BITJ),
        .BITH(BITH),
        .DATASPIN(DATASPIN),
        .SCALING_BIT(SCALING_BIT),
        .PARALLELISM(PARALLELISM),
        .ENERGY_TOTAL_BIT(ENERGY_TOTAL_BIT),
        .LITTLE_ENDIAN(LITTLE_ENDIAN),
        .PIPESINTF(PIPESINTF),
        .PIPESMID(PIPESMID)
    ) DUS (
        .clk_i(clk),
        .rst_ni(~reset),
        .en_i(ib_valid_out && in_en),
        .standard_mode_i(in_standard_mode),
        .first_operation_i(in_first_operation),
        .config_valid_i(ib_valid_out && in_config_valid),
        .config_counter_i(in_config_counter),
        .config_ready_o(dut_config_ready),
        .spin_valid_i(ib_valid_out && in_spin_valid),
        .spin_i(in_spin),
        .spin_ready_o(dut_spin_ready),
        .weight_valid_i(ib_valid_out && in_weight_valid),
        .weight_i(in_weight),
        .hbias_i(in_hbias),
        .hscaling_i(in_hscaling),
        .weight_ready_o(dut_weight_ready),
        .counter_spin_o(dut_counter_spin),
        .weight_raddr_em_o(dut_weight_raddr),
        .weight_raddr_valid_em_o(),
        .energy_valid_o(dut_energy_valid),
        .energy_ready_i(dut_energy_ready),
        .energy_o(dut_energy)
    );

    wire [OUT_DATAW-1:0] ob_data_in;
    assign ob_data_in = {
        dut_energy,
        dut_weight_raddr,
        dut_counter_spin,
        dut_weight_ready,
        dut_spin_ready,
        dut_config_ready
    };

    VX_pipe_buffer #(
        .DATAW(OUT_DATAW),
        .PASSTHRU(OUTPUT_PASSTHRU)
    ) output_buffer (
        .clk      (clk),
        .reset    (reset),
        .valid_in (dut_energy_valid),
        .ready_in (dut_energy_ready),
        .data_in  (ob_data_in),
        .data_out (data_out),
        .ready_out(ready_out),
        .valid_out(valid_out)
    );

endmodule
