// Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Author: Jiacong Sun <jiacong.sun@kuleuven.be>
//
// Module description:
// Energy monitor Testbench.

`timescale 1ns / 1ps

`ifndef DBG
`define DBG 0
`endif

`ifndef VCD_FILE
`define VCD_FILE "tb_energy_monitor.vcd"
`endif

`define S1W1H1_TEST 'b000 // spins: +1, weights: +1, hbias: +1, hscaling: +1
`define S0W1H1_TEST 'b001 // spins: -1, weights: +1, hbias: +1, hscaling: +1
`define S0W0H0_TEST 'b010 // spins: -1, weights: -1, hbias: -1, hscaling: +1
`define S1W0H0_TEST 'b011 // spins: +1, weights: -1, hbias: -1, hscaling: +1
`define MaxPosValue_TEST 'b100 // spins: +1, weights: max positive, hbias: max positive, hscaling: max positive
`define MaxNegValue_TEST 'b101 // spins: -1, weights: max negative, hbias: max negative, hscaling: max positive
`define RANDOM_TEST 'b110

`define True 1'b1
`define False 1'b0

`ifndef test_mode // select test mode
`define test_mode `RANDOM_TEST
`endif

`ifndef NUM_TESTS // number of test cases
`define NUM_TESTS 1
`endif

`ifndef PIPESINTF // number of pipeline stages at the input interface
`define PIPESINTF 1
`endif

`ifndef PIPESMID // number of pipeline stages at mid adder tree
`define PIPESMID 1
`endif

module tb_energy_monitor;
   // Pseudo memory banks: PARALLELISM banks, each with 256 addresses, each address holds 1024 bits (256 x 4)
    // Use a macro for PARALLELISM so it is always defined
`ifndef PARALLELISM
`define PARALLELISM 4
`endif

    // Testbench parameters
    localparam int CLKCYCLE = 2; // clock cycle in ns
    localparam int MEM_LATENCY = 0; // latency of memories in cycles
    localparam int SPIN_LATENCY = 10; // latency of spin input in cycles
    localparam int MEM_LATENCY_RANDOM = `False;
    localparam int SPIN_LATENCY_RANDOM = `False;

    // Module parameters
    localparam int BITJ = 4; // J precision, min: 2 (including sign bit)
    localparam int BITH = 4; // bias precision, min: 2 (including sign bit)
    localparam int DATASPIN = 256; // number of spins
    localparam int SCALING_BIT = 5; // bit width of scaling factor
    localparam int PARALLELISM = 4; // number of parallel energy calculation units, min: 1
    localparam int LOCAL_ENERGY_BIT = $clog2(DATASPIN) + BITH + SCALING_BIT - 1; // bit width of local energy
    localparam int ENERGY_TOTAL_BIT = 32; // bit width of total energy
    localparam int LITTLE_ENDIAN = `True; // endianness of spin and weight storage

    // Testbench internal signals
    logic clk_i;
    logic rst_ni;
    logic en_i;
    logic config_valid_i;
    // Additional signals after modification for differential testing
    logic standard_mode_i;
    logic first_operation_i;
    logic [ $clog2(DATASPIN)-1 : 0 ] config_counter_i;
    logic config_ready_o;
    logic spin_valid_i;
    logic [DATASPIN-1:0] spin_i;
    logic spin_ready_o;
    logic weight_valid_i;
    logic [DATASPIN*BITJ*PARALLELISM-1:0] weight_i;
    logic signed [BITH*PARALLELISM-1:0] hbias_i;
    logic unsigned [SCALING_BIT*PARALLELISM-1:0] hscaling_i;
    logic weight_ready_o;
    logic energy_valid_o;
    logic energy_ready_i;
    logic signed [ENERGY_TOTAL_BIT-1:0] energy_o;
    logic [$clog2(DATASPIN)-1:0] counter_spin_o;
    // Addresses from DUT for each parallel bank
    wire [PARALLELISM-1:0][$clog2(DATASPIN / PARALLELISM)-1:0] weight_raddr_em_o;

    logic unsigned [31:0] spin_reg_valid_int;
    logic [`NUM_TESTS-1:0] spin_reg_valid;
    logic [DATASPIN-1:0] spin_reg [0:`NUM_TESTS-1];
    logic [`PIPESINTF-1:0] pipe_valid;
    logic unsigned [31:0] pipe_valid_int;
    logic [DATASPIN*BITJ*PARALLELISM-1:0] weight_pipe [0:`PIPESINTF-1];
    logic signed [BITH*PARALLELISM-1:0] hbias_pipe [0:`PIPESINTF-1];
    logic unsigned [SCALING_BIT*PARALLELISM-1:0] hscaling_pipe [0:`PIPESINTF-1];
    logic unsigned [ $clog2(DATASPIN) : 0 ] expected_spin_counter;
    // expected_local_energy removed; we compute total energy from memory directly
    logic signed [ENERGY_TOTAL_BIT-1:0] expected_energy;
    logic unsigned [31:0] testcase_counter;
    logic unsigned [ $clog2(DATASPIN)-1 : 0 ] transaction_count;
    // Per-test print counters to limit debug output
    logic unsigned [31:0] weight_print_count [0:`NUM_TESTS-1];
    // Store first/last 5 transaction metadata per testcase
    logic unsigned [31:0] first_saved_count [0:`NUM_TESTS-1];
    logic unsigned [31:0] last_saved_count [0:`NUM_TESTS-1];
    int last_idx [0:`NUM_TESTS-1]; // circular index for last entries
    // saved column indices (col = addr*PARALLELISM + bank)
    int saved_first_cols [0:`NUM_TESTS-1][0:4][0:PARALLELISM-1];
    int saved_last_cols  [0:`NUM_TESTS-1][0:4][0:PARALLELISM-1];
    // saved local energies per transaction (sum across banks)
    logic signed [ENERGY_TOTAL_BIT-1:0] saved_first_locals [0:`NUM_TESTS-1][0:4];
    logic signed [ENERGY_TOTAL_BIT-1:0] saved_last_locals  [0:`NUM_TESTS-1][0:4];
    // saved spin chunks per transaction
    logic [DATASPIN-1:0] saved_first_spins [0:`NUM_TESTS-1][0:4];
    logic [DATASPIN-1:0] saved_last_spins  [0:`NUM_TESTS-1][0:4];

    integer spin_idx;
    integer correct_count;
    integer error_count;
    integer weight_mismatch_count;
    integer total_count;
    integer total_cycles;
    integer transaction_cycles;
    integer total_time;
    integer transaction_time;
    integer start_time;
    integer end_time;

    initial begin
        transaction_count = 0;
    end

    initial begin
        testcase_counter = 1;
        $display("Starting energy monitor testbench. Total cases: 'd%0d. Test mode: 'b%3b, Little endian: %0d", `NUM_TESTS, `test_mode, LITTLE_ENDIAN);
        forever begin
            wait (energy_valid_o && energy_ready_i);
            // Wait for the handshake to complete (energy_ready_i to go low)
            wait(!energy_ready_i);
            if (testcase_counter < `NUM_TESTS) begin
                testcase_counter = testcase_counter + 1;
                // $display("Running %0d/%0d tests...", testcase_counter, `NUM_TESTS);
            end else begin
                #(2*CLKCYCLE);
                $finish;
            end
            @(posedge clk_i); // Wait for next clock edge before checking again
        end
    end

    // Module instantiation
    energy_monitor #(
        .BITJ(BITJ),
        .BITH(BITH),
        .DATASPIN(DATASPIN),
        .SCALING_BIT(SCALING_BIT),
        .PARALLELISM(PARALLELISM),
        .ENERGY_TOTAL_BIT(ENERGY_TOTAL_BIT),
        .LITTLE_ENDIAN(LITTLE_ENDIAN),
        .PIPESINTF(`PIPESINTF),
        .PIPESMID(`PIPESMID)
    ) dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .en_i(en_i),
        .config_valid_i(config_valid_i),
        .config_counter_i(config_counter_i),
        .config_ready_o(config_ready_o),
        .spin_valid_i(spin_valid_i),
        .spin_i(spin_i),
        .spin_ready_o(spin_ready_o),
        .weight_valid_i(weight_valid_i),
        .weight_i(weight_i),
        .hbias_i(hbias_i),
        .hscaling_i(hscaling_i),
        .weight_ready_o(weight_ready_o),
        .counter_spin_o(counter_spin_o),
        .weight_raddr_em_o(weight_raddr_em_o),
        .energy_valid_o(energy_valid_o),
        .energy_ready_i(energy_ready_i),
        .standard_mode_i(standard_mode_i),
        .first_operation_i(first_operation_i),
        .energy_o(energy_o)
    );
    // ------------------------------------------------------------------------
    // Pseudo memory banks for weight matrix
    // j_mem_bank[bank][addr] stores one column of the J-matrix packed as
    // DATASPIN words of BITJ bits -> total width DATASPIN*BITJ
    // Mapping: column `col` -> bank = col % PARALLELISM, addr = col / PARALLELISM
    // ------------------------------------------------------------------------
    localparam int MEM_DEPTH = DATASPIN / PARALLELISM;
    logic [DATASPIN*BITJ-1:0] j_mem_bank [0:PARALLELISM-1][0:MEM_DEPTH-1];

    // Initialize weight matrix and pack into pseudo memory banks
    // Step 1: build a 2D weight_matrix[row][col]
    logic signed [BITJ-1:0] weight_matrix [0:DATASPIN-1][0:DATASPIN-1];

    initial begin
        // Fill weight_matrix according to test mode and enforce symmetry
        for (int r = 0; r < DATASPIN; r++) begin
            for (int c = r; c < DATASPIN; c++) begin
                logic signed [BITJ-1:0] tmp_w;
                if (r == c) begin
                    // diagonal elements typically zero in Ising coupling matrices
                    tmp_w = 'd0;
                end else begin
                    case(`test_mode)
                        `S1W1H1_TEST: tmp_w = {{(BITJ-1){1'b0}},1'b1};
                        `S0W1H1_TEST: tmp_w = {{(BITJ-1){1'b0}},1'b1};
                        `S0W0H0_TEST: tmp_w = {(BITJ){1'b1}}; // -1
                        `S1W0H0_TEST: tmp_w = {(BITJ){1'b1}}; // -1
                        `MaxPosValue_TEST: tmp_w = (1 << (BITJ-1)) - 1;
                        `MaxNegValue_TEST: tmp_w = -(1 << (BITJ-1));
                        `RANDOM_TEST: tmp_w = $urandom();
                        default: tmp_w = 'd0;
                    endcase
                end
                weight_matrix[r][c] = tmp_w;
                weight_matrix[c][r] = tmp_w; // mirror to enforce symmetry
            end
        end

        // Step 2: pack columns of weight_matrix into j_mem_bank[bank][addr]
        for (int col = 0; col < DATASPIN; col++) begin
            int bank;
            int addr;
            bank = col % PARALLELISM;
            addr = col / PARALLELISM;
            j_mem_bank[bank][addr] = '0;
            for (int row = 0; row < DATASPIN; row++) begin
                j_mem_bank[bank][addr][row*BITJ +: BITJ] = weight_matrix[row][col];
            end
        end
    end

   
  
    
    // Clock generation
    initial begin
        clk_i = 0;
        forever #(CLKCYCLE/2) clk_i = ~clk_i;
    end
    // Reset generation
    initial begin
        rst_ni = 0;
        #(10 * CLKCYCLE);
        rst_ni = 1;
    end

    // Config channel stimulus
    initial begin
        en_i = 0;
        config_valid_i = 0;
        config_counter_i = 'd0;
        standard_mode_i = 1;
        first_operation_i = 1; 
        #(10 * CLKCYCLE);
        first_operation_i = 1; 
        en_i = 1;
        config_valid_i = 1;
        config_counter_i = 'd0;
        #(10 * CLKCYCLE);
        first_operation_i = 0; 
        config_valid_i = 1;      
        config_counter_i = 'd255;
        #CLKCYCLE;
        config_valid_i = 0;
    end

    // Run tests
    initial begin
        if (`DBG) begin
            $display("Debug mode enabled. Generating VCD waveform.");
            $dumpfile(`VCD_FILE);
            $dumpvars(2, tb_energy_monitor);
            #(200 * CLKCYCLE); // To avoid generating too large VCD files
            $fatal(1, "Testbench timeout reached. Ending simulation.");
        end
        else begin
            // #(200000 * CLKCYCLE);
            // $display("Testbench timeout reached. Ending simulation.");
            // $finish;
        end
    end

    // ========================================================================
    // Reference behavior model
    // ========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin: spin_record
        if (!rst_ni) begin
            spin_reg_valid_int <= 0;
            for (int pi = 0; pi < `NUM_TESTS; pi++) begin
                weight_print_count[pi] <= 0;
                first_saved_count[pi] <= 0;
                last_saved_count[pi] <= 0;
                last_idx[pi] <= 0;
                for (int k = 0; k < 5; k++) begin
                    for (int b = 0; b < PARALLELISM; b++) begin
                        saved_first_cols[pi][k][b] <= 0;
                        saved_last_cols[pi][k][b] <= 0;
                    end
                    saved_first_locals[pi][k] <= 0;
                    saved_last_locals[pi][k] <= 0;
                    saved_first_spins[pi][k] <= 0;
                    saved_last_spins[pi][k] <= 0;
                end
            end
            for (int i = 0; i < `NUM_TESTS; i++) begin
                spin_reg[i] <= 0;
                spin_reg_valid[i] <= 0;
            end
        end
        else begin
            if (spin_valid_i && spin_ready_o) begin
                assert (spin_reg_valid_int < `NUM_TESTS) else $fatal("Spin register overflow: spin_reg_valid_int exceeded `NUM_TESTS");
                spin_reg[spin_reg_valid_int] <= spin_i;
                spin_reg_valid[spin_reg_valid_int] <= 1'b1;
                spin_reg_valid_int <= spin_reg_valid_int + 1;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin: pipeline_fill
        if (!rst_ni) begin
            pipe_valid_int <= 0;
            pipe_valid <= 0;
            for (int p = 0; p < `PIPESINTF; p++) begin
                weight_pipe[p] <= 0;
                hbias_pipe[p] <= 0;
                hscaling_pipe[p] <= 0;
            end
        end else begin
            if (weight_valid_i && weight_ready_o) begin
                if (`PIPESINTF == 0) begin: no_pipeline_mode
                    // Do nothing in no pipeline mode
                end else begin: pipeline_mode
                    if (energy_ready_i) begin
                        if (testcase_counter >= `NUM_TESTS) begin
                            // Do nothing, all tests completed
                        end else begin: pipeline_next_spin
                            pipe_valid[pipe_valid_int] <= 1; // Mark this stage as valid
                            weight_pipe[pipe_valid_int] <= weight_i;
                            hbias_pipe[pipe_valid_int] <= hbias_i;
                            hscaling_pipe[pipe_valid_int] <= hscaling_i;
                            pipe_valid_int <= pipe_valid_int + 1;
                        //    assert (pipe_valid_int <= `PIPESINTF) else $fatal("Pipeline overflow: pipe_valid_int exceeded `PIPESINTF");
                        end
                    end else begin
                        if (spin_reg_valid[testcase_counter-1] == 1'b0) begin: pipeline_current_spin
                            pipe_valid[pipe_valid_int] <= 1;
                            weight_pipe[pipe_valid_int] <= weight_i;
                            hbias_pipe[pipe_valid_int] <= hbias_i;
                            hscaling_pipe[pipe_valid_int] <= hscaling_i;
                            pipe_valid_int <= pipe_valid_int + 1;
                          //  assert (pipe_valid_int <= `PIPESINTF) else $fatal("Pipeline overflow [time %0d ns]: pipe_valid_int exceeded `PIPESINTF",
                          //  $time);
                        end else begin: pipeline_flush
                            for (int p = 0; p < pipe_valid_int; p++) begin
                                if (pipe_valid[p]) begin
                                    pipe_valid[p] <= 0;
                                end
                            end
                            pipe_valid_int <= 0;
                        end
                    end
                end
            end
        end
    end

    // Simplified expected-energy handling: compute total energy directly from memory
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            energy_ready_i <= 0;
            expected_spin_counter <= 0;
            expected_energy <= 0;
        end else begin
            if (energy_valid_o && energy_ready_i) begin: new_testcase_start
                energy_ready_i <= 0;
                expected_spin_counter <= 0;
                expected_energy <= 0;
            end else if (weight_valid_i && weight_ready_o) begin: calc_total_energy
                // Compute reference total energy for current testcase in one pass
                expected_energy <= compute_total_energy_from_mem(spin_reg[testcase_counter-1]);
                expected_spin_counter <= DATASPIN;
                energy_ready_i <= 1;
            end
        end
    end

    // ========================================================================
    // Tasks and functions
    // ========================================================================
    // compute_local_energy removed — tests use compute_total_energy_from_mem()

    // Task for timer
    task automatic timer();
        begin
            total_cycles = 0;
            transaction_cycles = 0;
            total_time = 0;
            transaction_time = 0;
            start_time = 0;
            end_time = 0;
            wait(rst_ni);
            wait(spin_valid_i && spin_ready_o);
            start_time = $time;
            wait(testcase_counter == `NUM_TESTS && energy_valid_o && energy_ready_i);
            end_time = $time;
            total_time = end_time - start_time;
            total_cycles = total_time / CLKCYCLE;
            transaction_cycles = total_cycles / `NUM_TESTS;
            transaction_time = transaction_cycles * CLKCYCLE;
            $display("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
            $display("Timer [Time %0d ns]: start time: %0d ns, end time: %0d ns, duration: %0d ns, transactions: %0d",
                $time, start_time, end_time, total_time, `NUM_TESTS);
            $display("Timer [Time %0d ns]: Total cycles: %0d cc [%0d ns], Cycles/transaction: %0d cc [%0d ns]",
                $time, total_cycles, total_time, transaction_cycles, transaction_time);
            $display("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
        end
    endtask

    // Task for scoreboard
    task automatic check_energy();
        begin
            // local variables must be declared before any statements
            int tc_print;
            int nf;
            int nl;
            int start;
            int ii;
            int idx;
            int ff;
            int pb;
            int pb2;
            int pb3;
            int pb4;

            correct_count = 0;
            error_count = 0;
            total_count = 0;
            wait(rst_ni);
            do begin
                // wait for energy handshake
                wait(energy_valid_o && energy_ready_i);
                if (energy_o !== expected_energy) begin
                    $error("Time: %0d ns, Testcase [%0d] Energy mismatch: received 'd%0d, expected 'd%0d",
                        $time, testcase_counter, energy_o, expected_energy);
                    error_count = error_count + 1;
                end else begin
                    $display("Time: %0d ns, Testcase [%0d] Energy match: 'd%0d", $time, testcase_counter, energy_o);
                    correct_count = correct_count + 1;
                end
                // Print first 5 and last 5 saved transactions for this testcase
                tc_print = (testcase_counter == 0) ? 0 : testcase_counter - 1;
                if (tc_print >= 0 && tc_print < `NUM_TESTS) begin
                    $display("[TB] --- Transactions summary for testcase %0d ---", testcase_counter);
                    // First entries
                    nf = first_saved_count[tc_print];
                    $display("[TB] First %0d transactions (up to 5):", nf);
                    for (ff = 0; ff < nf; ff++) begin
                        $write("[TB]  trans %0d cols:", ff);
                        for (pb = 0; pb < PARALLELISM; pb++) begin
                            $write(" %0d", saved_first_cols[tc_print][ff][pb]);
                        end
                        $write("  locals: %0d", saved_first_locals[tc_print][ff]);
                        $write("  spin_chunk: ");
                        for (pb2 = 0; pb2 < PARALLELISM; pb2++) begin
                            logic spin_bit_summary;
                            int col_summary;
                            col_summary = saved_first_cols[tc_print][ff][pb2];
                            if (LITTLE_ENDIAN == `True)
                                spin_bit_summary = saved_first_spins[tc_print][ff][col_summary];
                            else
                                spin_bit_summary = saved_first_spins[tc_print][ff][DATASPIN - 1 - col_summary];
                            $write("%0d", spin_bit_summary);
                        end
                        $display("");
                    end
                    // Last entries (print in chronological order)
                    nl = last_saved_count[tc_print];
                    $display("[TB] Last %0d transactions (up to 5):", nl);
                    start = (last_idx[tc_print]) % 5;
                    for (ii = 0; ii < nl; ii++) begin
                        idx = (start + ii) % 5;
                        $write("[TB]  trans %0d cols:", ii);
                        for (pb3 = 0; pb3 < PARALLELISM; pb3++) begin
                            $write(" %0d", saved_last_cols[tc_print][idx][pb3]);
                        end
                        $write("  locals: %0d", saved_last_locals[tc_print][idx]);
                        $write("  spin_chunk: ");
                        for (pb4 = 0; pb4 < PARALLELISM; pb4++) begin
                            logic spin_bit_summary_last;
                            int col_summary_last;
                            col_summary_last = saved_last_cols[tc_print][idx][pb4];
                            if (LITTLE_ENDIAN == `True)
                                spin_bit_summary_last = saved_last_spins[tc_print][idx][col_summary_last];
                            else
                                spin_bit_summary_last = saved_last_spins[tc_print][idx][DATASPIN - 1 - col_summary_last];
                            $write("%0d", spin_bit_summary_last);
                        end
                        $display("");
                    end
                    $display("[TB] --- end summary for testcase %0d ---", testcase_counter);
                end
                total_count = total_count + 1;
                if (total_count == `NUM_TESTS) begin
                    @(posedge clk_i);
                    $display("----------------------------------------");
                    $display("Scoreboard [Time %0d ns]: %0d/%0d correct, %0d/%0d errors",
                        $time, correct_count, total_count, error_count, total_count);
                    $display("----------------------------------------");
                end
                @(posedge clk_i);
            end
            while (total_count <= `NUM_TESTS);
        end
    endtask

    // Task to handle spin input
    task automatic spin_interface();
        begin
            spin_valid_i = 0;
            spin_i = 'd0;
            // Wait for reset to be released
            wait(rst_ni);
            do begin
                // Wait for config to complete if it's active
                if (config_valid_i) begin
                    wait (!config_valid_i);
                    @(posedge clk_i); // Wait one more cycle after config
                end

                // Generate and send spin data
                spin_valid_i = 1;
                for (int i = 0; i < DATASPIN; i++) begin
                    case(`test_mode)
                        `S1W1H1_TEST: spin_i[i] = 1'b1;
                        `S0W1H1_TEST: spin_i[i] = 1'b0;
                        `S0W0H0_TEST: spin_i[i] = 1'b0;
                        `S1W0H0_TEST: spin_i[i] = 1'b1;
                        `MaxPosValue_TEST: spin_i[i] = 1'b1;
                        `MaxNegValue_TEST: spin_i[i] = 1'b0;
                        `RANDOM_TEST: spin_i[i] = $urandom() % 2;
                        default: spin_i[i] = 1'b0;
                    endcase
                end

                // Wait for handshake
                wait(spin_ready_o);
                @(posedge clk_i);
                spin_valid_i = 0;

                // Wait before next spin operation
                if (SPIN_LATENCY_RANDOM == `True) begin
                    repeat($urandom_range(0, SPIN_LATENCY)) @(posedge clk_i);
                end else begin
                    repeat(SPIN_LATENCY) @(posedge clk_i);
                end
            end
            while (spin_reg_valid_int < `NUM_TESTS);
        end
    endtask

    // Compute total energy from j_mem_bank using full spin vector
    function automatic signed [ENERGY_TOTAL_BIT-1:0] compute_total_energy_from_mem(
        input logic [DATASPIN-1:0] spin_vec
    );
        // Use a wider accumulator to avoid overflow during accumulation
        logic signed [ENERGY_TOTAL_BIT+BITJ+8:0] accum;
        logic signed [BITJ-1:0] weight_temp;
        logic spin_val_col;
        logic spin_val_row;
        int col;
        int row;
        int bank;
        int addr;
        logic [DATASPIN*BITJ-1:0] column_data;
        begin
            accum = 0;
            for (col = 0; col < DATASPIN; col++) begin
                if (LITTLE_ENDIAN == `True) begin
                    spin_val_col = spin_vec[col];
                end else begin
                    spin_val_col = spin_vec[DATASPIN - 1 - col];
                end
                bank = col % PARALLELISM;
                addr = col / PARALLELISM;
                column_data = j_mem_bank[bank][addr];
                for (row = 0; row < DATASPIN; row++) begin
                    if (row == col) begin
                        // skip diagonal
                    end else begin
                        if (LITTLE_ENDIAN == `True) begin
                            spin_val_row = spin_vec[row];
                        end else begin
                            spin_val_row = spin_vec[DATASPIN - 1 - row];
                        end
                        weight_temp = $signed(column_data[row*BITJ +: BITJ]);
                        // contribution = s_row * s_col * J[row][col]
                        // s bit: 1 => +1, 0 => -1
                        if (spin_val_row) begin
                            if (spin_val_col) accum += weight_temp;
                            else accum -= weight_temp;
                        end else begin
                            if (spin_val_col) accum -= weight_temp;
                            else accum += weight_temp;
                        end
                    end
                end
            end
            // matrix is symmetric and we summed both (i,j) and (j,i), so divide by 2
            compute_total_energy_from_mem = accum; // arithmetic shift for division by 2
        end
    endfunction
    // Compute local energy for one parallel unit from the packed weight_i signal
function automatic signed [ENERGY_TOTAL_BIT-1:0] compute_local_energy_from_weight_input(
    input logic [DATASPIN-1:0] spin_vec,
    input logic [DATASPIN*BITJ-1:0] weight_column,  // One column from weight_i
    input int col  // Column index for this unit
);
    logic signed [ENERGY_TOTAL_BIT+BITJ+4:0] accum_col;
    logic signed [BITJ-1:0] weight_temp;
    logic spin_val_col;
    logic spin_val_row;
    int row;
    begin
        accum_col = 0;
        
        // Get spin value for this column
        if (LITTLE_ENDIAN == `True) 
            spin_val_col = spin_vec[col];
        else 
            spin_val_col = spin_vec[DATASPIN - 1 - col];
        
        // Iterate through all rows in this column
        for (row = 0; row < DATASPIN; row++) begin
            if (row == col) begin
                // Skip diagonal
            end else begin
                // Get spin value for this row
                if (LITTLE_ENDIAN == `True) 
                    spin_val_row = spin_vec[row];
                else 
                    spin_val_row = spin_vec[DATASPIN - 1 - row];
                
                // Extract weight from packed column data
                weight_temp = $signed(weight_column[row*BITJ +: BITJ]);
                
                // Calculate energy contribution: s_row * s_col * J[row][col]
                if (spin_val_row) begin
                    if (spin_val_col) accum_col += weight_temp;
                    else accum_col -= weight_temp;
                end else begin
                    if (spin_val_col) accum_col -= weight_temp;
                    else accum_col += weight_temp;
                end
            end
        end
        
        compute_local_energy_from_weight_input = accum_col;
    end
endfunction

    // Compute local energy for a single column from j_mem_bank and a spin vector
    function automatic signed [ENERGY_TOTAL_BIT-1:0] compute_local_energy_from_mem_col(
        input logic [DATASPIN-1:0] spin_vec,
        input int col
    );
        logic signed [ENERGY_TOTAL_BIT+BITJ+4:0] accum_col;
        logic signed [BITJ-1:0] weight_temp_col;
        logic spin_val_col_c;
        logic spin_val_row_c;
        int row_c;
        int bank_c;
        int addr_c;
        logic [DATASPIN*BITJ-1:0] column_data_c;
        begin
            accum_col = 0;
            if (col < 0 || col >= DATASPIN) begin
                compute_local_energy_from_mem_col = '0;
            end else begin
                bank_c = col % PARALLELISM;
                addr_c = col / PARALLELISM;
                column_data_c = j_mem_bank[bank_c][addr_c];
                if (LITTLE_ENDIAN == `True) spin_val_col_c = spin_vec[col];
                else spin_val_col_c = spin_vec[DATASPIN - 1 - col];
                for (row_c = 0; row_c < DATASPIN; row_c++) begin
                    if (row_c == col) begin
                        // skip diagonal
                    end else begin
                        if (LITTLE_ENDIAN == `True) spin_val_row_c = spin_vec[row_c];
                        else spin_val_row_c = spin_vec[DATASPIN - 1 - row_c];
                        weight_temp_col = $signed(column_data_c[row_c*BITJ +: BITJ]);
                        if (spin_val_row_c) begin
                            if (spin_val_col_c) accum_col += weight_temp_col;
                            else accum_col -= weight_temp_col;
                        end else begin
                            if (spin_val_col_c) accum_col -= weight_temp_col;
                            else accum_col += weight_temp_col;
                        end
                    end
                end
                compute_local_energy_from_mem_col = accum_col;
            end
        end
    endfunction

    // Task to handle weight input
    task automatic weight_interface();
        begin
            // Declare all variables at the beginning
            logic signed [BITJ-1:0] weight_temp;
            logic signed [BITH-1:0] hbias_temp;
            logic unsigned [SCALING_BIT-1:0] hscaling_temp;
            int tc_idx;
            logic [DATASPIN-1:0] current_spin;
            logic signed [ENERGY_TOTAL_BIT-1:0] local_energies [0:PARALLELISM-1];
            logic signed [ENERGY_TOTAL_BIT-1:0] total_local_sum;
            int current_cols [0:PARALLELISM-1];
            int b_idx;
            int addr_idx;
            int fi, li, bb;
            logic [DATASPIN*BITJ-1:0] weight_col;
            spin_idx = 0;

            weight_valid_i = 0;
            weight_i = 'd0;
            hbias_i = 'd0;
            hscaling_i = 'd0;
            wait(rst_ni);

            forever begin
                // Wait for config to complete
                if (config_valid_i) begin
                    wait (!config_valid_i);
                    @(posedge clk_i);
                end

                // Load weight vector from pseudo memory banks using DUT-provided addresses
                // Each bank provides an address `weight_raddr_em_o[bank]` selecting a column
                // Pack columns from bank 0..PARALLELISM-1 into `weight_i` in the same order
                for (int b = 0; b < PARALLELISM; b++) begin
                    // read address from DUT (address width = $clog2(DATASPIN/PARALLELISM))
                    int addr = weight_raddr_em_o[b];
                    // guard: if addr out-of-range, clamp
                    if (addr < 0 || addr >= MEM_DEPTH) begin
                        addr = 0;
                    end
                    // j_mem_bank[b][addr] holds DATASPIN*BITJ bits for this column
                    weight_i[b*DATASPIN*BITJ +: DATASPIN*BITJ] =  j_mem_bank[b][addr];
                end

                // ====================================================================
                // Calculate and display local energies for each unit every weight change
                // ====================================================================
                tc_idx = (testcase_counter == 0) ? 0 : testcase_counter - 1;
                
                // Get current spin vector
                if (spin_reg_valid_int == 0) 
                    current_spin = spin_reg[0];
                else 
                    current_spin = spin_reg[spin_reg_valid_int - 1];
                
                // Calculate local energy for each unit/bank
                // Calculate local energy for each unit/bank
total_local_sum = 'd0;
for (b_idx = 0; b_idx < PARALLELISM; b_idx++) begin
    addr_idx = weight_raddr_em_o[b_idx];
    if (addr_idx < 0 || addr_idx >= MEM_DEPTH) addr_idx = 0;
    
    // Column index for this bank
    current_cols[b_idx] = addr_idx * PARALLELISM + b_idx;
    
    // Extract this unit's weight column from packed weight_i
  
    weight_col = weight_i[b_idx*DATASPIN*BITJ +: DATASPIN*BITJ];
    
    // Compute local energy directly from weight_i (not from memory)
    local_energies[b_idx] = compute_local_energy_from_weight_input(
        current_spin, 
        weight_col, 
        current_cols[b_idx]
    );
    total_local_sum += local_energies[b_idx];
end
                
                // Display local energies only for first and last 5 transactions per testcase
                if (tc_idx >= 0 && tc_idx < `NUM_TESTS) begin
                    if (first_saved_count[tc_idx] < 5 || 
                        (transaction_count >= (DATASPIN/PARALLELISM - 5))) begin
                        $display("========================================================");
                        $display("[TB] Time %0t ns | Test %0d | Transaction %0d", 
                                 $time, testcase_counter, transaction_count);
                        $display("--------------------------------------------------------");
                        // Display spin chunk for the 4 columns being processed
                        $write("[TB]   Spin Chunk (4 cols): ");
                        for (b_idx = 0; b_idx < PARALLELISM; b_idx++) begin
                            logic spin_bit;
                            int col_idx;
                            col_idx = current_cols[b_idx];
                            if (LITTLE_ENDIAN == `True)
                                spin_bit = current_spin[col_idx];
                            else
                                spin_bit = current_spin[DATASPIN - 1 - col_idx];
                            $write("col[%0d]=%0d ", col_idx, spin_bit);
                        end
                        $display("");
                        $display("--------------------------------------------------------");
                        // Display each unit's calculation details
                        for (b_idx = 0; b_idx < PARALLELISM; b_idx++) begin
                            logic spin_bit_unit;
                            logic [DATASPIN*BITJ-1:0] weight_col_unit;
                            int col_idx_unit;
                            col_idx_unit = current_cols[b_idx];
                            weight_col_unit = weight_i[b_idx*DATASPIN*BITJ +: DATASPIN*BITJ];
                            if (LITTLE_ENDIAN == `True)
                                spin_bit_unit = current_spin[col_idx_unit];
                            else
                                spin_bit_unit = current_spin[DATASPIN - 1 - col_idx_unit];
                            
                            $display("[TB]   Unit %0d | Col %3d | s[%0d]=%0d | Weights[1023:0]=0x%0256x | LocalE=%0d", 
                                     b_idx, col_idx_unit, col_idx_unit, spin_bit_unit, 
                                     weight_col_unit, local_energies[b_idx]);
                        end
                        $display("--------------------------------------------------------");
                        $display("[TB]   TOTAL LOCAL SUM = %0d", total_local_sum);
                        $display("========================================================");
                    end
                end
                
                // Save data for first 5 and last 5 transactions
                if (tc_idx >= 0 && tc_idx < `NUM_TESTS) begin
                    // Save first 5 entries
                    fi = first_saved_count[tc_idx];
                    if (fi < 5) begin
                        for (bb = 0; bb < PARALLELISM; bb++) begin
                            saved_first_cols[tc_idx][fi][bb] = current_cols[bb];
                        end
                        saved_first_locals[tc_idx][fi] = total_local_sum;
                        saved_first_spins[tc_idx][fi] = current_spin;
                        first_saved_count[tc_idx] = first_saved_count[tc_idx] + 1;
                    end
                    
                    // Save last 5 entries (circular buffer)
                    li = last_idx[tc_idx] % 5;
                    for (bb = 0; bb < PARALLELISM; bb++) begin
                        saved_last_cols[tc_idx][li][bb] = current_cols[bb];
                    end
                    saved_last_locals[tc_idx][li] = total_local_sum;
                    saved_last_spins[tc_idx][li] = current_spin;
                    last_idx[tc_idx] = (last_idx[tc_idx] + 1) % 5;
                    if (last_saved_count[tc_idx] < 5) 
                        last_saved_count[tc_idx] = last_saved_count[tc_idx] + 1;
                end

                // Zero-out the positions corresponding to the current spin (masking)
               

                // Force hbias to zero (bias disabled / removed)
                for (int i = 0; i < PARALLELISM; i++) begin
                    hbias_i[i*BITH +: BITH] = 'd0;
                end

                // Force hscaling to zero (scaling disabled)
                for (int i = 0; i < PARALLELISM; i++) begin
                    hscaling_i[i*SCALING_BIT +: SCALING_BIT] = 'd0;
                end

                // Now assert valid and wait for a handshake
                weight_valid_i = 1;
                do @(posedge clk_i);
                while (!(weight_valid_i && weight_ready_o));
            
                // Handshake occurred here - safe to update data next cycle
                spin_idx = (spin_idx + PARALLELISM) % DATASPIN;
                transaction_count++;
            
                // Deassert valid if you want to insert latency
                if (MEM_LATENCY > 0) begin
                    weight_valid_i = 0;
                    if (MEM_LATENCY_RANDOM == `True) begin
                        repeat($urandom_range(0, MEM_LATENCY)) @(posedge clk_i);
                    end else begin
                        repeat(MEM_LATENCY) @(posedge clk_i);
                    end
                end
            end
        end
    endtask

    // ========================================================================
    // Testbench task and timer setup
    // ========================================================================
    // Spin interface
    initial begin
        fork
            spin_interface();
            weight_interface();
            check_energy();
            timer();
        join_none
    end

    // Runtime check: compare DUT internal weight array with TB's packed `weight_i`
    // Triggered on weight handshake (weight_valid && weight_ready)
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            weight_mismatch_count <= 0;
        end else begin
            if (weight_valid_i && weight_ready_o) begin
                int b;
                int r;
                logic signed [BITJ-1:0] tb_w;
                logic signed [BITJ-1:0] dut_w;
                for (b = 0; b < PARALLELISM; b++) begin
                    for (r = 0; r < DATASPIN; r++) begin
                        tb_w = $signed(weight_i[b*DATASPIN*BITJ + r*BITJ +: BITJ]);
                        dut_w = dut.weight_i_array[b][r];
                        if (tb_w !== dut_w) begin
                            weight_mismatch_count <= weight_mismatch_count + 1;
                            if (weight_mismatch_count <= 20) begin
                                $error("[TB] Time %0t: weight mismatch bank %0d row %0d TB=%0d DUT=%0d", $time, b, r, tb_w, dut_w);
                            end
                        end
                    end
                end
            end
        end
    end


endmodule
