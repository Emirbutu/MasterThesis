`timescale 1ns / 1ps

`ifndef DBG
`define DBG 0
`endif

`ifndef VCD_FILE
`define VCD_FILE "tb_syn_tle_with_sram.vcd"
`endif

`define S1W1H1_TEST 'b000
`define S0W1H1_TEST 'b001
`define S0W0H0_TEST 'b010
`define S1W0H0_TEST 'b011
`define MaxPosValue_TEST 'b100
`define MaxNegValue_TEST 'b101
`define RANDOM_TEST 'b110

`ifndef test_mode
`define test_mode `RANDOM_TEST
`endif

`ifndef NUM_TESTS
`define NUM_TESTS 200
`endif

`ifndef True
`define True 1'b1
`endif

module VX_pipe_buffer #(
    parameter int DATAW = 1,
    parameter int PASSTHRU = 0
) (
    input  wire             clk,
    input  wire             reset,
    input  wire             valid_in,
    output wire             ready_in,
    input  wire [DATAW-1:0] data_in,
    output wire [DATAW-1:0] data_out,
    input  wire             ready_out,
    output wire             valid_out
);
    logic [DATAW-1:0] data_q;
    logic valid_q;

    always_ff @(posedge clk or posedge reset) begin
        if (reset) begin
            data_q <= '0;
            valid_q <= 1'b0;
        end else if (ready_in) begin
            data_q <= data_in;
            valid_q <= valid_in;
        end
    end

    assign ready_in = (~valid_q) || ready_out;
    assign data_out = PASSTHRU ? data_in : data_q;
    assign valid_out = PASSTHRU ? valid_in : valid_q;
endmodule

module tb_syn_tle_with_sram;
    localparam int CLKCYCLE = 2;
    localparam int BITJ = 4;
    localparam int BITH = 4;
    localparam int DATASPIN = 256;
    localparam int SCALING_BIT = 4;
    localparam int PARALLELISM = 4;
    localparam int ENERGY_TOTAL_BIT = 32;
    localparam int LITTLE_ENDIAN = `True;
    localparam int PIPESINTF = 1;
    localparam int PIPESMID = 1;
    localparam int INPUT_PASSTHRU = 0;
    localparam int OUTPUT_PASSTHRU = 0;

    localparam int SPINIDX_BIT = $clog2(DATASPIN);
    localparam int DATAJ = DATASPIN * BITJ * PARALLELISM;
    localparam int DATAH = BITH * PARALLELISM;
    localparam int DATASCALING = SCALING_BIT * PARALLELISM;
    localparam int WEIGHT_ADDRW = $clog2(DATASPIN / PARALLELISM);
    localparam int WEIGHT_ADDR_BUSW = PARALLELISM * WEIGHT_ADDRW;
    localparam int IN_DATAW = 1 + 1 + 1 + 1 + SPINIDX_BIT + 1 + DATASPIN + 1 + DATAJ + DATAH + DATASCALING;
    localparam int OUT_DATAW = 1 + 1 + 1 + SPINIDX_BIT + WEIGHT_ADDR_BUSW + ENERGY_TOTAL_BIT;

    localparam int SRAM_DEPTH = DATASPIN / PARALLELISM;
    localparam int SRAM_WEIGHT_DWIDTH = (DATASPIN / PARALLELISM) * BITJ;
    localparam int SRAM_DWIDTH = SRAM_WEIGHT_DWIDTH + BITH + SCALING_BIT;
    localparam int SRAM_HBIAS_LSB = SRAM_WEIGHT_DWIDTH;
    localparam int SRAM_HSCALING_LSB = SRAM_WEIGHT_DWIDTH + BITH;

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

    localparam int OUT_LSB_CFG_READY = 0;
    localparam int OUT_LSB_SPIN_READY = OUT_LSB_CFG_READY + 1;
    localparam int OUT_LSB_WEIGHT_READY = OUT_LSB_SPIN_READY + 1;
    localparam int OUT_LSB_COUNTER_SPIN = OUT_LSB_WEIGHT_READY + 1;
    localparam int OUT_LSB_WEIGHT_ADDR = OUT_LSB_COUNTER_SPIN + SPINIDX_BIT;
    localparam int OUT_LSB_ENERGY = OUT_LSB_WEIGHT_ADDR + WEIGHT_ADDR_BUSW;

    logic clk_i;
    logic rst_ni;
    logic valid_in;
    logic ready_in;
    logic [IN_DATAW-1:0] data_in;
    logic valid_out;
    logic ready_out;
    logic [OUT_DATAW-1:0] data_out;

    logic spin_valid_i;
    logic [DATASPIN-1:0] spin_i;
    logic spin_ready_o;
    logic first_operation_i;
    logic energy_valid_o;
    logic energy_ready_i;
    logic signed [ENERGY_TOTAL_BIT-1:0] energy_o;

    logic signed [BITJ-1:0] j_matrix [0:DATASPIN-1][0:DATASPIN-1];
    logic signed [BITH-1:0] hbias_shadow [0:DATASPIN-1];
    logic [SCALING_BIT-1:0] hscaling_shadow [0:DATASPIN-1];
    logic signed [BITH-1:0] hbias_const;
    logic [SCALING_BIT-1:0] hscaling_const;

    wire out_cfg_ready;
    wire out_spin_ready;
    wire out_weight_ready;
    wire [SPINIDX_BIT-1:0] out_counter_spin;
    wire [WEIGHT_ADDR_BUSW-1:0] out_weight_addr;

    assign out_cfg_ready = data_out[OUT_LSB_CFG_READY +: 1];
    assign out_spin_ready = data_out[OUT_LSB_SPIN_READY +: 1];
    assign out_weight_ready = data_out[OUT_LSB_WEIGHT_READY +: 1];
    assign out_counter_spin = data_out[OUT_LSB_COUNTER_SPIN +: SPINIDX_BIT];
    assign out_weight_addr = data_out[OUT_LSB_WEIGHT_ADDR +: WEIGHT_ADDR_BUSW];

    assign spin_ready_o = ready_in;
    assign energy_valid_o = valid_out;
    assign energy_o = $signed(data_out[OUT_LSB_ENERGY +: ENERGY_TOTAL_BIT]);
    assign ready_out = energy_ready_i;

    `include "tb_utils.svh"

    syn_tle_with_sram #(
        .BITJ(BITJ),
        .BITH(BITH),
        .DATASPIN(DATASPIN),
        .SCALING_BIT(SCALING_BIT),
        .PARALLELISM(PARALLELISM),
        .ENERGY_TOTAL_BIT(ENERGY_TOTAL_BIT),
        .LITTLE_ENDIAN(LITTLE_ENDIAN),
        .PIPESINTF(PIPESINTF),
        .PIPESMID(PIPESMID),
        .INPUT_PASSTHRU(INPUT_PASSTHRU),
        .OUTPUT_PASSTHRU(OUTPUT_PASSTHRU)
    ) dut (
        .clk(clk_i),
        .reset_n(rst_ni),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .ready_out(ready_out),
        .data_out(data_out)
    );

    initial begin
        clk_i = 1'b0;
        forever #(CLKCYCLE/2) clk_i = ~clk_i;
    end

    initial begin
        rst_ni = 1'b0;
        valid_in = 1'b0;
        data_in = '0;
        spin_valid_i = 1'b0;
        spin_i = '0;
        first_operation_i = 1'b0;
        energy_ready_i = 1'b0;
        #(10 * CLKCYCLE);
        rst_ni = 1'b1;
    end

    initial begin
        logic [DATASPIN-1:0] spin_vec;
        wait (rst_ni);

        $display("[TB] Initializing behavioral SRAM directly");
        build_and_init_sram_direct();

        send_cfg('d0);
        send_cfg(DATASPIN-1);

        for (int t = 0; t < `NUM_TESTS; t++) begin
            spin_vec = build_spin(t);
            send_spin(spin_vec, (t == 0));
            check_energy_vs_ref();
        end

        $display("[TB] Completed %0d tests.", `NUM_TESTS);
        $finish;
    end

    initial begin
        if (`DBG) begin
            $dumpfile(`VCD_FILE);
            $dumpvars(2, tb_syn_tle_with_sram);
        end
    end

    initial begin
        #(300000 * CLKCYCLE);
        $fatal(1, "[TB] Timeout reached.");
    end
endmodule
