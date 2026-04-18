`timescale 1ns / 1ps

`ifndef DBG
`define DBG 0
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
`define NUM_TESTS 513
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

module tb_syn_tle_with_sram #(
    parameter bit TB_STANDARD_MODE = 1'b1
);
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
    localparam bit USE_SPIN_FILE = 1'b1;
    localparam string SPIN_FILE_PATH = "/users/students/r1024900/MasterThesis/default/states_out_1";

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

    integer csv_fd;
    string csv_path;
    logic [DATASPIN-1:0] spin_fifo [0:`NUM_TESTS-1];
    integer test_id_fifo [0:`NUM_TESTS-1];
    integer fifo_wr;
    integer fifo_rd;
    integer fifo_sent_wr;
    integer tx_count;
    integer rx_count;
    longint cycle_count;
    longint spin_send_cycle_fifo [0:`NUM_TESTS-1];
    integer spin_file_fd;
    string spin_file_path;

    `include "tb_utils.svh"

`ifdef POST_SYN_SIM
    syn_tle_with_sram dut (
        .clk(clk_i),
        .reset_n(rst_ni),
        .valid_in(valid_in),
        .ready_in(ready_in),
        .data_in(data_in),
        .valid_out(valid_out),
        .ready_out(ready_out),
        .data_out(data_out)
    );
`else
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
`endif

    initial begin
        clk_i = 1'b0;
        forever #(CLKCYCLE/2) clk_i = ~clk_i;
    end

    initial begin
        rst_ni = 1'b0;
        valid_in = 1'b0;
        data_in = '0;
        data_in[IN_LSB_EN +: 1] = 1'b1;
        data_in[IN_LSB_STD_MODE +: 1] = TB_STANDARD_MODE;
        spin_valid_i = 1'b0;
        spin_i = '0;
        first_operation_i = 1'b1;
        energy_ready_i = 1'b1;
        fifo_wr = 0;
        fifo_rd = 0;
        fifo_sent_wr = 0;
        tx_count = 0;
        rx_count = 0;
        cycle_count = 0;

        csv_path = "spin_energy_log.csv";
        void'($value$plusargs("TB_LOG_CSV=%s", csv_path));
        csv_fd = $fopen(csv_path, "w");
        if (csv_fd == 0) begin
            $fatal(1, "[TB] Failed to open CSV log: %0s", csv_path);
        end
        $fdisplay(csv_fd, "time_ns,cycle,test_id,spin_hex,spin_ones,energy,energy_valid_cycle");
        #(10 * CLKCYCLE);
        rst_ni = 1'b1;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            cycle_count <= 0;
        end else begin
            cycle_count <= cycle_count + 1;
        end
    end

    // Capture the exact cycle when a spin payload handshake occurs at DUT input.
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            fifo_sent_wr <= 0;
        end else if (valid_in && ready_in && data_in[IN_LSB_SPIN_VALID +: 1]) begin
            if (fifo_sent_wr >= `NUM_TESTS) begin
                $fatal(1, "[TB] Sent-cycle FIFO overflow");
            end
            spin_send_cycle_fifo[fifo_sent_wr] <= cycle_count;
            fifo_sent_wr <= fifo_sent_wr + 1;
        end
    end

    // Config and sequential spin sending in initial block
    initial begin
        integer vectors_loaded;
        integer file_fd_local;
        integer scan_result;
        integer sent_idx;
        string line;
        logic [DATASPIN-1:0] spin_vec_from_file;
        bit success;

        wait (rst_ni);
        send_cfg('d0);
        send_cfg(DATASPIN-1);

        // Load or generate test vectors and populate FIFO
        if (USE_SPIN_FILE) begin
            // Load vectors from file and enqueue using the same enqueue path
            // as generated vectors to keep behavior identical across modes.
            spin_file_path = SPIN_FILE_PATH;
            vectors_loaded = 0;
            file_fd_local = $fopen(spin_file_path, "r");
            if (file_fd_local == 0) begin
                $fatal(1, "[TB] Failed to open spin file: %0s", spin_file_path);
            end

            while ((vectors_loaded < `NUM_TESTS) && (!$feof(file_fd_local))) begin
                line = "";
                void'($fgets(line, file_fd_local));
                scan_result = $sscanf(line, "%b", spin_vec_from_file);
                if (scan_result != 1) begin
                    scan_result = $sscanf(line, "%h", spin_vec_from_file);
                end
                if (scan_result == 1) begin
                    success = enqueue_vector(
                        .vector(spin_vec_from_file),
                        .test_id(vectors_loaded),
                        .vector_fifo(spin_fifo),
                        .test_id_fifo(test_id_fifo),
                        .fifo_write_ptr(fifo_wr),
                        .fifo_count(tx_count)
                    );
                    if (!success) begin
                        $fatal(1, "[TB] Failed to enqueue vector from file at index %0d", vectors_loaded);
                    end
                    vectors_loaded = vectors_loaded + 1;
                end
            end
            $fclose(file_fd_local);

            if (vectors_loaded == 0 || tx_count == 0) begin
                $fatal(1, "[TB] No valid vectors loaded from %0s", spin_file_path);
            end
            $display("[TB] Loaded and queued %0d vectors from file %0s", tx_count, spin_file_path);
        end else begin
            // Generate and enqueue test vectors programmatically
            $display("[TB] Generating %0d test vectors programmatically", `NUM_TESTS);
            for (int t = 0; t < `NUM_TESTS; t++) begin
                logic [DATASPIN-1:0] spin_vec;
                spin_vec = build_spin(t);

                success = enqueue_vector(
                    .vector(spin_vec),
                    .test_id(t),
                    .vector_fifo(spin_fifo),
                    .test_id_fifo(test_id_fifo),
                    .fifo_write_ptr(fifo_wr),
                    .fifo_count(tx_count)
                );

                if (!success) begin
                    $fatal(1, "[TB] Failed to enqueue vector at test %0d", t);
                end
            end
            $display("[TB] Generated and queued %0d test vectors", tx_count);
        end

        // Old-style pacing: send one spin, then wait until one energy is received.
        // This prevents issuing spins back-to-back without output correlation.
        for (sent_idx = 0; sent_idx < tx_count; sent_idx++) begin
            send_spin(spin_fifo[sent_idx], (sent_idx == 0));
            wait (rx_count == (sent_idx + 1));
        end

        // Wait for all energies to be logged
        wait (rx_count == tx_count);

        $display("[TB] Completed %0d tests.", tx_count);
        $fclose(csv_fd);
        $finish;
    end

    always @(posedge clk_i) begin
        logic [DATASPIN-1:0] spin_logged;
        integer test_id_logged;
        longint latency_cycles;
        longint energy_valid_cycle;
        if (rst_ni && energy_valid_o ) begin
            if (rx_count >= tx_count) begin
                $fatal(1, "[TB] RX without matching TX (rx_count=%0d tx_count=%0d)", rx_count, tx_count);
            end

            energy_valid_cycle = cycle_count;
            latency_cycles = energy_valid_cycle - spin_send_cycle_fifo[fifo_rd];

            spin_logged = spin_fifo[fifo_rd];
            test_id_logged = test_id_fifo[fifo_rd];
            fifo_rd = (fifo_rd + 1) % `NUM_TESTS;
            rx_count = rx_count + 1;

            $display("[TB][IO] t=%0d latency=%0d test=%0d spin_ones=%0d energy=%0d done_cycle=%0d",
                     $time, latency_cycles, test_id_logged, $countones(spin_logged), $signed(energy_o), energy_valid_cycle);
            $fdisplay(csv_fd, "%0t,%0d,%0d,%0h,%0d,%0d,%0d",
                      $time, latency_cycles, test_id_logged, spin_logged,
                      $countones(spin_logged), $signed(energy_o), energy_valid_cycle);
        end
    end

    initial begin
        if (`DBG) begin
            // When DBG is enabled, logging is handled by Questa's -log or waveform recording
            // VCD dumping is disabled in favor of Questa's native WLF format
            #(400 * CLKCYCLE);
            $fatal(1, "[TB] Timeout reached.");
        end
    end

    initial begin
        #(30000 * CLKCYCLE);
        $fatal(1, "[TB] Timeout reached.");
    end
endmodule
