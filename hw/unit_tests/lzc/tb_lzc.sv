`timescale 1ns/1ps

module tb_lzc;

// Parameters
parameter N = 16;
localparam LOGN = $clog2(N);

// Clock and reset
logic clk;
logic rst_n;

// DUT signals
    logic start;
    logic [N-1:0] data_in;
    logic [N-1:0][LOGN-1:0] positions;
    logic [N-1:0] valid_o;
    logic [LOGN:0] count;
    logic done;
    logic empty;

// Clock generation
initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 10ns period (100MHz)
end

// Print positions and valid_o every cycle
always @(posedge clk) begin
    $write("[Cycle %0t] positions: ", $time);
    for (int i = 0; i < N; i++) $write("%0d ", positions[i]);
    $display("");
    $write("[Cycle %0t] valid_o:   ", $time);
    for (int i = 0; i < N; i++) $write("%0b ", valid_o[i]);
    $display("");
end

// DUT instantiation
find_all_ones_iterative #(
    .N(N)
) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .start_i(start),
    .data_i(data_in),
    .positions(positions),
        .valid_o(valid_o),
    .count(count),
    .done(done),
    .empty_o(empty)
);

// Task to apply test and wait for completion
task automatic test_pattern(input [N-1:0] pattern, input string description);
    integer i;
    integer expected_count;
    logic [N-1:0][LOGN-1:0] expected_positions;
    integer pos_idx;
    integer cycle_count;
    integer first_one_cycle;
    logic first_one_found;
    
    $display("\n=== Test: %s ===", description);
    $display("Input: 0x%04h (%016b)", pattern, pattern);
    
    // Calculate expected count
    expected_count = 0;
    pos_idx = 0;
    for (i = 0; i < N; i++) begin
        if (pattern[i]) begin
            expected_positions[pos_idx] = i;
            pos_idx++;
            expected_count++;
        end
    end
    
    // Start the search
    data_in = pattern;
    start = 1;
    cycle_count = 0;
    first_one_found = 0;
    first_one_cycle = 0;
    @(posedge clk);
    start = 0;
    
    // Wait for completion and count cycles to first one
    while (!done) begin
        @(posedge clk);
        cycle_count++;
        if (!first_one_found && count > 0) begin
            first_one_found = 1;
            first_one_cycle = cycle_count;
        end
    end
    @(posedge clk);
    
    // Display results
    $display("Found %0d ones (Expected: %0d), Empty flag: %0b", count, expected_count, empty);
    $display("Total cycles to completion: %0d", cycle_count);
    if (first_one_found) begin
        $display("Cycles to find first '1': %0d", first_one_cycle);
    end else begin
        $display("No '1' bits found in input");
    end
    
    if (count == expected_count) begin
        $display("✓ Count matches!");
    end else begin
        $display("✗ Count mismatch!");
    end
    
    // Check empty flag
    if (expected_count == 0 && empty) begin
        $display("✓ Empty flag correctly set (no ones found)!");
    end else if (expected_count > 0 && !empty) begin
        $display("✓ Empty flag correctly cleared (ones found)!");
    end else begin
        $display("✗ Empty flag incorrect! Expected: %0b, Got: %0b", (expected_count == 0), empty);
    end
    
    // Display positions
    $display("Positions found:");
    for (i = 0; i < count; i++) begin
        $display("  [%0d] = %0d", i, positions[i]);
    end
    
    // Verify positions
    if (count == expected_count) begin
        automatic logic positions_match = 1;
        for (i = 0; i < count; i++) begin
            if (positions[i] !== expected_positions[i]) begin
                positions_match = 0;
                $display("✗ Position mismatch at index %0d: got %0d, expected %0d", 
                         i, positions[i], expected_positions[i]);
            end
        end
        if (positions_match) begin
            $display("✓ All positions correct!");
        end
    end
    
    // Wait a bit before next test
    repeat(2) @(posedge clk);
endtask

// Test sequence
initial begin
    // Initialize
    rst_n = 0;
    start = 0;
    data_in = 0;
    
    // Reset
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);
    
    $display("=================================================");
    $display("  Testing find_all_ones_iterative (N=%0d)", N);
    $display("=================================================");
    
    // Test 1: All zeros
    test_pattern(16'b0000000000000000, "All zeros");
    
    // Test 2: Single bit at position 0
    test_pattern(16'b0000000000000001, "Single bit at position 0");
    
    // Test 3: Single bit at position 7
    test_pattern(16'b0000000010000000, "Single bit at position 7");
    
    // Test 4: Single bit at position 15
    test_pattern(16'b1000000000000000, "Single bit at position 15");
    
    // Test 5: Two consecutive bits
    test_pattern(16'b0000000000000011, "Two consecutive bits (0,1)");
    
    // Test 6: Multiple scattered bits
    test_pattern(16'b0001000100010001, "Multiple scattered bits");
    
    // Test 7: Half bits set (even positions)
    test_pattern(16'b0101010101010101, "Even positions set");
    
    // Test 8: Half bits set (odd positions)
    test_pattern(16'b1010101010101010, "Odd positions set");
    
    // Test 9: First half set
    test_pattern(16'b0000000011111111, "First 8 bits set");
    
    // Test 10: Second half set
    test_pattern(16'b1111111100000000, "Last 8 bits set");
    
    // Test 11: All ones
    test_pattern(16'b1111111111111111, "All ones");
    
    // Test 12: Random pattern 1
    test_pattern(16'b1001011010110010, "Random pattern 1");
    
    // Test 13: Random pattern 2
    test_pattern(16'b0110110101001101, "Random pattern 2");
    
    $display("\n=================================================");
    $display("  All tests completed!");
    $display("=================================================\n");
    
    $finish;
end

// Timeout watchdog
initial begin
    #100000;  // 100us timeout
    $display("\n*** ERROR: Simulation timeout! ***");
    $finish;
end

 // Optional: Waveform dumping
initial begin
    $dumpfile("tb_lzc.vcd");
    $dumpvars(0, tb_lzc);
end

endmodule
