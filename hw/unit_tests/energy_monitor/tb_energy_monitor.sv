
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
`define HALF_SPLIT_ALT_TEST 'b111 // spins alternate per iteration: [first half=1, second half=0] then [first half=0, second half=1]
`define SPARSE_FLIP_TEST 'd8 // start from a base vector and toggle only a few bits per test iteration

`define True 1'b1
`define False 1'b0

`ifndef test_mode // select test mode
`define test_mode `RANDOM_TEST 
`endif

`ifndef SPARSE_FLIP_BASE // number of bit flips in the first sparse iteration
`define SPARSE_FLIP_BASE 0
`endif

`ifndef SPARSE_FLIP_LEVELS // cycles flips as BASE x [1..LEVELS] => e.g. 10,20,30
`define SPARSE_FLIP_LEVELS 1
`endif

`ifndef NUM_TESTS // number of test cases
`define NUM_TESTS 10000
`endif

`ifndef PIPESINTF // number of pipeline stages at the input interface
`define PIPESINTF 1
`endif

`ifndef PIPESMID // number of pipeline stages at mid adder tree
`define PIPESMID 1
`endif

`ifndef SRAM_READ_COMB // 1: combinational read, 0: posedge read
`define SRAM_READ_COMB 0
`endif

`ifndef SRAM_RD_LATENCY // valid only when SRAM_READ_COMB=0
`define SRAM_RD_LATENCY 1
`endif

module tb_energy_monitor;
   // Pseudo memory banks: PARALLELISM banks, each with 256 addresses, each address holds 1024 bits (256 x 4)
    // Use a macro for PARALLELISM so it is always defined
`ifndef PARALLELISM
`define PARALLELISM 4
`endif

    // Testbench parameters
    localparam int CLKCYCLE = 2; // clock cycle in ns
    localparam int MEM_LATENCY = `SRAM_RD_LATENCY; // latency of memories in cycles (sync mode)
    localparam bit MEM_READ_COMB = `SRAM_READ_COMB;
    localparam int SPIN_LATENCY = 10; // latency of spin input in cycles
    localparam int MEM_LATENCY_RANDOM = `False;
    localparam int SPIN_LATENCY_RANDOM = `False;

    // Module parameters
    localparam int BITJ = 4; // J precision, min: 2 (including sign bit)
    localparam int BITH = 4; // bias precision, signed range now covers 0..255
    localparam int DATASPIN = 256; // number of spins
    localparam int SCALING_BIT = 5; // bit width of scaling factor
    localparam int PARALLELISM = 4; // number of parallel energy calculation units, min: 1
    localparam int LOCAL_ENERGY_BIT = $clog2(DATASPIN) + BITH + SCALING_BIT - 1; // bit width of local energy
    localparam int ENERGY_TOTAL_BIT = 32; // bit width of total energy
    localparam int LITTLE_ENDIAN = `True; // endianness of spin and weight storage
    // SRAM parameters
    localparam int SRAM_DEPTH = 64;
    localparam int SRAM_WEIGHT_DWIDTH = DATASPIN * BITJ;
    localparam int SRAM_DWIDTH = SRAM_WEIGHT_DWIDTH + BITH + SCALING_BIT;
    localparam int SRAM_AWIDTH = $clog2(SRAM_DEPTH);
    localparam int SRAM_DWIDTHB = (SRAM_DWIDTH + 7) / 8;
    localparam int SRAM_HBIAS_LSB = SRAM_WEIGHT_DWIDTH;
    localparam int SRAM_HSCALING_LSB = SRAM_WEIGHT_DWIDTH + BITH;

    // Testbench internal signals
    // Utility tasks, reference checker variables, and functions.
    // Included here (after localparams) so that all identifiers are in scope.
  

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
    wire  [PARALLELISM-1:0][$clog2(DATASPIN/PARALLELISM)-1:0] weight_raddr_em_o;

    // SRAM signals for each PARALLELISM bank
    logic [PARALLELISM-1:0][SRAM_AWIDTH-1:0] sram_addr;
    logic [PARALLELISM-1:0][SRAM_DWIDTH-1:0] sram_rdata;
    logic [PARALLELISM-1:0][SRAM_DWIDTH-1:0] sram_wdata;
    logic [PARALLELISM-1:0][SRAM_DWIDTHB-1:0] sram_be;
    logic [PARALLELISM-1:0] sram_cs;
    logic [PARALLELISM-1:0] sram_we;
    logic [PARALLELISM-1:0] sram_valid;
    logic [PARALLELISM-1:0] sram_read_req;
    localparam int SRAM_VALID_LAT = MEM_READ_COMB ? 0 : ((MEM_LATENCY > 0) ? MEM_LATENCY : 1);
    logic [PARALLELISM-1:0][SRAM_VALID_LAT-1:0] sram_valid_pipe;
     `include "tb_utils.svh"
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

    // SRAM instantiations - one per PARALLELISM bank
    genvar i;
    generate
        for (i = 0; i < PARALLELISM; i++) begin : sram_banks
            logic [0:0] req_1p;
            logic [0:0] we_1p;
            logic [0:0][SRAM_AWIDTH-1:0] addr_1p;
            logic [0:0][SRAM_DWIDTH-1:0] wdata_1p;
            logic [0:0][SRAM_DWIDTHB-1:0] be_1p;
            logic [0:0][SRAM_DWIDTH-1:0] rdata_1p;

            assign req_1p[0] = sram_cs[i];
            assign we_1p[0] = sram_we[i];
            assign addr_1p[0] = sram_addr[i];
            assign wdata_1p[0] = sram_wdata[i];
            assign be_1p[0] = sram_be[i];
            assign sram_rdata[i] = rdata_1p[0];

            tc_sram_eth #(
                .NumWords(SRAM_DEPTH),
                .DataWidth(SRAM_DWIDTH),
                .ByteWidth(8),
                .NumPorts(1),
                .Latency(MEM_READ_COMB ? 0 : MEM_LATENCY),
                .SimInit("none")
            ) u_sram (
                .clk_i(clk_i),
                .rst_ni(rst_ni),
                .req_i(req_1p),
                .we_i(we_1p),
                .addr_i(addr_1p),
                .wdata_i(wdata_1p),
                .be_i(be_1p),
                .rdata_o(rdata_1p)
            );
        end
    endgenerate

    // Connect DUT weight address output to SRAM address input
    // Connect DUT weight_ready_o to SRAM chip select (read enable)
    generate
        for (i = 0; i < PARALLELISM; i++) begin : sram_addr_connect
            assign sram_addr[i] = weight_raddr_em_o[i];
            assign sram_cs[i] = weight_ready_o;
            assign sram_we[i] = 1'b0;            // Read-only mode
            assign sram_be[i] = '1;              // All bytes enabled
            assign sram_wdata[i] = '0;           // Not writing
        end
    endgenerate

    // Connect SRAM read data to DUT inputs
    // Each SRAM bank provides {hscaling, hbias, weight_column}
    generate
        for (i = 0; i < PARALLELISM; i++) begin : weight_data_connect
            assign weight_i[i*SRAM_WEIGHT_DWIDTH +: SRAM_WEIGHT_DWIDTH] =
                sram_rdata[i][0 +: SRAM_WEIGHT_DWIDTH];
            assign hbias_i[i*BITH +: BITH] =
                sram_rdata[i][SRAM_HBIAS_LSB +: BITH];
            assign hscaling_i[i*SCALING_BIT +: SCALING_BIT] =
                sram_rdata[i][SRAM_HSCALING_LSB +: SCALING_BIT];
        end
    endgenerate

    // Recreate valid_o behavior locally for tc_sram_eth
    generate
        if (MEM_READ_COMB) begin : gen_sram_valid_comb
            for (i = 0; i < PARALLELISM; i++) begin : gen_sram_valid_comb_bank
                assign sram_valid[i] = sram_cs[i] && ~sram_we[i];
            end
        end else begin : gen_sram_valid_sync
            for (i = 0; i < PARALLELISM; i++) begin : gen_sram_valid_sync_bank
                assign sram_read_req[i] = sram_cs[i] && ~sram_we[i];
                always_ff @(posedge clk_i or negedge rst_ni) begin
                    if (!rst_ni) begin
                        sram_valid_pipe[i] <= '0;
                    end else begin
                        sram_valid_pipe[i][0] <= sram_read_req[i];
                        for (int d = 1; d < SRAM_VALID_LAT; d++) begin
                            sram_valid_pipe[i][d] <= sram_valid_pipe[i][d-1];
                        end
                    end
                end
                assign sram_valid[i] = sram_valid_pipe[i][SRAM_VALID_LAT-1];
            end
        end
    endgenerate

    // Connect SRAM valid output to DUT weight_valid_i
    // All banks should be valid simultaneously, so AND them for safety
    assign weight_valid_i = &sram_valid; // All banks must be valid
    
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

    // SRAM initialization
    // Without this, tc_sram memory array remains X and propagates unknowns.
    initial begin
        #1;
        $display("[TB] SRAM mode: READ_COMB=%0d, RD_LATENCY=%0d", MEM_READ_COMB, MEM_LATENCY);
        init_all_srams(INIT_RANDOM); // Initialize all SRAMs to a known state (e.g., all ones)
    end

    // Config channel stimulus
    initial begin
        en_i = 0;
        config_valid_i = 0;
        config_counter_i = 'd0;
        standard_mode_i = 0 ; // Start in non-standard mode to test the first operation logic
        first_operation_i = 1; 
        energy_ready_i = 0;
        spin_valid_i = 0;
        spin_i = '0;
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
            #(350 * CLKCYCLE); // To avoid generating too large VCD files
            $fatal(1, "Testbench timeout reached. Ending simulation.");
        end
        else begin
            // Timeout guard: prevents the simulation from hanging indefinitely
           //  #(500000 * CLKCYCLE);
           //  $fatal(1, "[TB] Timeout: simulation exceeded limit.");
        end
    end

    // Spin stimulus: sends NUM_TESTS spin vectors after reset & config complete
    initial begin
        bit split_first_half_one;
        bit [DATASPIN-1:0] flipped_mask;
        bit [DATASPIN-1:0] prev_spin;
        int flips_this_test;
        int flips_done;
        int changed_bits;
        int idx;
        wait (rst_ni);
        wait (!config_valid_i); // wait for config phase to finish
        @(posedge clk_i);
        prev_spin = '0;
        for (int t = 0; t < `NUM_TESTS; t++) begin
            split_first_half_one = (t % 2 == 0);
            spin_valid_i = 1;
            if (`test_mode == `SPARSE_FLIP_TEST) begin
                if (t == 0) begin
                    spin_i = '0;
                end

                flips_this_test = `SPARSE_FLIP_BASE * ((t % `SPARSE_FLIP_LEVELS) + 1);
                if (flips_this_test > DATASPIN)
                    flips_this_test = DATASPIN;

                flipped_mask = '0;
                flips_done = 0;
                while (flips_done < flips_this_test) begin
                    idx = $urandom_range(DATASPIN-1, 0);
                    if (!flipped_mask[idx]) begin
                        flipped_mask[idx] = 1'b1;
                        spin_i[idx] = ~spin_i[idx];
                        flips_done++;
                    end
                end
            end
            else begin
                for (int s = 0; s < DATASPIN; s++) begin
                    case (`test_mode)
                        `S1W1H1_TEST:      spin_i[s] = 1'b1;
                        `S0W1H1_TEST:      spin_i[s] = 1'b0;
                        `S0W0H0_TEST:      spin_i[s] = 1'b0;
                        `S1W0H0_TEST:      spin_i[s] = 1'b1;
                        `MaxPosValue_TEST: spin_i[s] = 1'b1;
                        `MaxNegValue_TEST: spin_i[s] = 1'b0;
                        `RANDOM_TEST:      spin_i[s] = $urandom() % 2;
                        `HALF_SPLIT_ALT_TEST: begin
                            if (split_first_half_one)
                                spin_i[s] = (s < (DATASPIN/2)) ? 1'b1 : 1'b0;
                            else
                                spin_i[s] = (s < (DATASPIN/2)) ? 1'b0 : 1'b1;
                        end
                        default:           spin_i[s] = 1'b0;
                    endcase
                end
            end
            changed_bits = 0;
            for (int s = 0; s < DATASPIN; s++) begin
                if (spin_i[s] != prev_spin[s]) changed_bits++;
            end
            $display("[TB][SPIN] iter=%0d changed_bits=%0d", t, changed_bits);
            prev_spin = spin_i;
            wait (spin_ready_o);
            @(posedge clk_i);
            spin_valid_i = 0;
            repeat (SPIN_LATENCY) @(posedge clk_i);
        end
    end

    // Reference energy checker: runs once per test, then finishes
    initial begin
        wait (rst_ni);
        repeat (`NUM_TESTS) check_energy_vs_ref();
        // Keep simulation alive for a few cycles so wave viewers can sample
        // local_energy_col_ref/local_energy_col_ref_flat cleanly.
        repeat (20) @(posedge clk_i);
        $display("[TB] All %0d test(s) complete.", `NUM_TESTS);
        $finish;
    end


endmodule 