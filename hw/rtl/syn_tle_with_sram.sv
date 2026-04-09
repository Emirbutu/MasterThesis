// Copyright 2026 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef True
`define True 1'b1
`endif

// Synthesis wrapper placing SRAM banks in front of energy_monitor.
//
// Input protocol:
// - config/spin fields feed the monitor exactly as in syn_tle.
// - weight/hbias/hscaling fields are interpreted as SRAM write data when
//   in_weight_valid is asserted. The write address is in_config_counter.
// - During compute, the monitor drives weight_raddr_em_o and this wrapper
//   performs SRAM reads and forwards read data back to the monitor.
module syn_tle_with_sram #(
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
    parameter int SRAM_NUM_WORDS = DATASPIN / PARALLELISM,
    parameter int SRAM_WEIGHT_DW_PER_LANE = (DATASPIN / PARALLELISM) * BITJ,
    parameter int SRAM_WORD_DW = SRAM_WEIGHT_DW_PER_LANE,
    parameter int SRAM_BYTEW = 8,
    parameter int SRAM_BEW = (SRAM_WORD_DW + SRAM_BYTEW - 1) / SRAM_BYTEW,
    parameter int IN_DATAW = 1 + 1 + 1 + 1 + SPINIDX_BIT + 1 + DATASPIN + 1 + DATAJ + DATAH + DATASCALING,
    parameter int OUT_DATAW = 1 + 1 + 1 + SPINIDX_BIT + WEIGHT_ADDR_BUSW + ENERGY_TOTAL_BIT
) (
    input  wire                 clk,
    input  wire                 reset_n,
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
        .reset    (~reset_n),
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
    assign in_weight_valid = ib_data_out[IN_LSB_WEIGHT_VALID +: 1]; //To write into SRAM.
    assign in_weight = ib_data_out[IN_LSB_WEIGHT +: DATAJ];
    assign in_hbias = ib_data_out[IN_LSB_HBIAS +: DATAH];
    assign in_hscaling = ib_data_out[IN_LSB_HSCALING +: DATASCALING];

    wire dut_config_ready;
    wire dut_spin_ready;
    wire dut_weight_ready;
    wire [SPINIDX_BIT-1:0] dut_counter_spin;
    wire [PARALLELISM-1:0][WEIGHT_ADDRW-1:0] dut_weight_raddr;
    wire [PARALLELISM-1:0] dut_weight_raddr_valid;
    wire dut_energy_valid;
    wire dut_energy_ready;
    wire signed [ENERGY_TOTAL_BIT-1:0] dut_energy;

    wire ib_cfg_fire;
    wire ib_spin_fire;

    assign ib_cfg_fire = (~(ib_valid_out && in_config_valid)) || dut_config_ready;
    assign ib_spin_fire = (~(ib_valid_out && in_spin_valid)) || dut_spin_ready;
    assign ib_ready_in = ib_cfg_fire && ib_spin_fire;

    wire [PARALLELISM-1:0] sram_read_req;
    wire any_read_req;
    reg  any_read_req_d;

    wire [DATAJ-1:0] sram_weight;
    wire [DATAH-1:0] sram_hbias;
    wire [DATASCALING-1:0] sram_hscaling;

    genvar i;
    generate
        for (i = 0; i < PARALLELISM; i++) begin : gen_weight_srams
            wire [0:0] sram_req_1p;
            wire [0:0] sram_we_1p;
            wire [0:0][WEIGHT_ADDRW-1:0] sram_addr_1p;
            wire [0:0][SRAM_WORD_DW-1:0] sram_wdata_1p;
            wire [0:0][SRAM_BEW-1:0] sram_be_1p;
            wire [0:0][SRAM_WORD_DW-1:0] sram_rdata_1p;
            wire [SRAM_WEIGHT_DW_PER_LANE-1:0] weight_col_i;
            reg [BITH-1:0] hbias_reg;
            reg [SCALING_BIT-1:0] hscaling_reg;

            assign sram_read_req[i] = dut_weight_ready && ib_valid_out && in_en && dut_weight_raddr_valid[i];

            assign sram_req_1p[0] = (ib_valid_out && in_weight_valid) || sram_read_req[i];
            assign sram_we_1p[0] = ib_valid_out && in_weight_valid;
            assign sram_addr_1p[0] = (ib_valid_out && in_weight_valid)
                ? in_config_counter[WEIGHT_ADDRW-1:0]
                : (dut_weight_raddr_valid[i] ? dut_weight_raddr[i] : '0);
            assign sram_wdata_1p[0] = in_weight[i*SRAM_WEIGHT_DW_PER_LANE +: SRAM_WEIGHT_DW_PER_LANE];
            assign sram_be_1p[0] = {SRAM_BEW{1'b1}};

            tc_sram_syn #(
                .NumWords(SRAM_NUM_WORDS),
                .DataWidth(SRAM_WORD_DW),
                .ByteWidth(SRAM_BYTEW),
                .NumPorts(1),
                .Latency(1)
            ) u_sram (
                .clk_i(clk),
                .rst_ni(reset_n),
                .req_i(sram_req_1p),
                .we_i(sram_we_1p),
                .addr_i(sram_addr_1p),
                .wdata_i(sram_wdata_1p),
                .be_i(sram_be_1p),
                .rdata_o(sram_rdata_1p)
            );

            always @(posedge clk or negedge reset_n) begin
                if (!reset_n) begin
                    hbias_reg <= '0;
                    hscaling_reg <= '0;
                end else if (ib_valid_out && in_weight_valid) begin
                    hbias_reg <= in_hbias[i*BITH +: BITH];
                    hscaling_reg <= in_hscaling[i*SCALING_BIT +: SCALING_BIT];
                end
            end

            assign weight_col_i = sram_rdata_1p[0][0 +: SRAM_WEIGHT_DW_PER_LANE];

            assign sram_weight[i*SRAM_WEIGHT_DW_PER_LANE +: SRAM_WEIGHT_DW_PER_LANE] = weight_col_i;
            assign sram_hbias[i*BITH +: BITH] = hbias_reg;
            assign sram_hscaling[i*SCALING_BIT +: SCALING_BIT] = hscaling_reg;
        end
    endgenerate

    assign any_read_req = |sram_read_req;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            any_read_req_d <= 1'b0;
        end else begin
            any_read_req_d <= any_read_req;
        end
    end

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
        .rst_ni(reset_n),
        .en_i(ib_valid_out && in_en),
        .standard_mode_i(in_standard_mode),
        .first_operation_i(in_first_operation),
        .config_valid_i(ib_valid_out && in_config_valid),
        .config_counter_i(in_config_counter),
        .config_ready_o(dut_config_ready),
        .spin_valid_i(ib_valid_out && in_spin_valid),
        .spin_i(in_spin),
        .spin_ready_o(dut_spin_ready),
        .weight_valid_i(any_read_req_d),
        .weight_i(sram_weight),
        .hbias_i(sram_hbias),
        .hscaling_i(sram_hscaling),
        .weight_ready_o(dut_weight_ready),
        .counter_spin_o(dut_counter_spin),
        .weight_raddr_em_o(dut_weight_raddr),
        .weight_raddr_valid_em_o(dut_weight_raddr_valid),
        .energy_valid_o(dut_energy_valid),
        .energy_ready_i(dut_energy_ready),
        .energy_o(dut_energy)
    );

    // Output payload from monitor wrapper
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
        .reset    (~reset_n),
        .valid_in (dut_energy_valid),
        .ready_in (dut_energy_ready),
        .data_in  (ob_data_in),
        .data_out (data_out),
        .ready_out(ready_out),
        .valid_out(valid_out)
    );

endmodule
