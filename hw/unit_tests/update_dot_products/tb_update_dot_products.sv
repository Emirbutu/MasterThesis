`timescale 1ns/1ps

module tb_update_dot_products;

  // ========== Parameters ==========
  localparam int NUM_ROWS_PER_CLK = 4;
  localparam int VECTOR_SIZE      = 8;
  localparam int DATA_WIDTH       = 4;
  localparam bit PIPED            = 1;
  localparam int LEVELS           = (NUM_ROWS_PER_CLK > 1) ? $clog2(NUM_ROWS_PER_CLK) : 0;
  localparam logic [LEVELS:0] PIPE_STAGE_MASK = '1;
  localparam int ACCUM_WIDTH      = 16;

  localparam int MUX_OUT_WIDTH     = DATA_WIDTH + 1;
  localparam int WIDTH_BEFORE_TREE = MUX_OUT_WIDTH + 1;
  localparam int COLUMN_SUM_WIDTH  = DATA_WIDTH + 1 + LEVELS + 1;

  // Number of random tests to run
  localparam int NUM_RANDOM_TESTS = 1000000;

  // ========== Signals ==========
  logic clk;
  logic rst_n;
  logic clear;
  logic signed [DATA_WIDTH-1:0] j_rows [0:NUM_ROWS_PER_CLK-1][0:VECTOR_SIZE-1];
  logic [NUM_ROWS_PER_CLK-1:0] j_rows_valid;
  logic [NUM_ROWS_PER_CLK-1:0] sigma_bits;
  logic signed [ACCUM_WIDTH-1:0] reset_values [0:VECTOR_SIZE-1];
  logic signed [ACCUM_WIDTH-1:0] accumulated_sums [0:VECTOR_SIZE-1];
  logic done;

  // ========== Test Variables ==========
  int passed, failed;
  logic signed [ACCUM_WIDTH-1:0] expected_accum [0:VECTOR_SIZE-1];
  logic signed [ACCUM_WIDTH-1:0] captured_accum;

  // ========== Clock Generation ==========
  initial clk = 0;
  always #5 clk = ~clk;

  // ========== DUT ==========
  update_dot_products #(
    .NUM_ROWS_PER_CLK (NUM_ROWS_PER_CLK),
    .VECTOR_SIZE      (VECTOR_SIZE),
    .DATA_WIDTH       (DATA_WIDTH),
    .PIPED            (PIPED),
    .LEVELS           (LEVELS),
    .PIPE_STAGE_MASK  (PIPE_STAGE_MASK),
    .ACCUM_WIDTH      (ACCUM_WIDTH)
  ) dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .clear           (clear),
    .j_rows          (j_rows),
    .j_rows_valid    (j_rows_valid),
    .sigma_bits      (sigma_bits),
    .reset_values    (reset_values),
    .accumulated_sums(accumulated_sums),
    .done            (done)
  );

 

  // ========== Helper Functions ==========

  // Calculate expected column sum for one operation
  function automatic logic signed [COLUMN_SUM_WIDTH-1:0] calc_column_sum(
    input logic signed [DATA_WIDTH-1:0] row_values [0:NUM_ROWS_PER_CLK-1],
    input logic [NUM_ROWS_PER_CLK-1:0] valid,
    input logic [NUM_ROWS_PER_CLK-1:0] sigma
  );
    logic signed [COLUMN_SUM_WIDTH-1:0] sum;
    logic signed [WIDTH_BEFORE_TREE-1:0] term;
    logic signed [MUX_OUT_WIDTH-1:0] shifted;
    
    sum = 0;
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++) begin
      if (valid[r]) begin
        shifted = {row_values[r], 1'b0};
      end else begin
        shifted = '0;
      end
      if (sigma[r]) begin
        term = WIDTH_BEFORE_TREE'(shifted);
      end else begin
        term = -WIDTH_BEFORE_TREE'(shifted);
      end
      sum = sum + term;
    end
    return sum;
  endfunction

  // ========== Test Tasks ==========

  // Task to perform one accumulation operation and check results
  task automatic run_accumulation_test(
    input string test_name,
    input logic signed [DATA_WIDTH-1:0] test_row_values [0:NUM_ROWS_PER_CLK-1][0:VECTOR_SIZE-1],
    input logic [NUM_ROWS_PER_CLK-1:0] test_valid,
    input logic [NUM_ROWS_PER_CLK-1:0] test_sigma,
    input logic verbose = 0
  );
    logic signed [COLUMN_SUM_WIDTH-1:0] column_sum [0:VECTOR_SIZE-1];
    int wait_cycles;
    int errors;
    
    errors = 0;
    
    // Calculate expected results for all columns
    for (int c = 0; c < VECTOR_SIZE; c++) begin
      logic signed [DATA_WIDTH-1:0] col_values [0:NUM_ROWS_PER_CLK-1];
      for (int r = 0; r < NUM_ROWS_PER_CLK; r++) begin
        col_values[r] = test_row_values[r][c];
      end
      column_sum[c] = calc_column_sum(col_values, test_valid, test_sigma);
      expected_accum[c] = expected_accum[c] + column_sum[c];
    end
    
    if (verbose) begin
      $display("%s", test_name);
      $display("  Expected accumulation for column 0: %0d", expected_accum[0]);
    end
    
    // Apply inputs
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r][c];
    j_rows_valid = test_valid;
    sigma_bits = test_sigma;
    
    // Deassert valid after one cycle
    @(posedge clk);
    j_rows_valid = '0;
    
    // Wait for done signal
    wait_cycles = 0;
    while (!done && wait_cycles < 100) begin
      @(posedge clk);
      wait_cycles++;
    end
    
    if (wait_cycles >= 100) begin
      $display("  ERROR: done signal never asserted!");
      failed++;
      return;
    end
    
    // Wait one more cycle after done, then capture results
    @(posedge clk);
    
    // Check all columns
    for (int c = 0; c < VECTOR_SIZE; c++) begin
      if (accumulated_sums[c] !== expected_accum[c]) begin
        if (verbose || errors < 3) begin
          $display("  FAIL column %0d: got %0d, expected %0d", c, accumulated_sums[c], expected_accum[c]);
        end
        errors++;
      end
    end
    
    if (errors == 0) begin
      if (verbose) $display("  PASS: All %0d columns correct", VECTOR_SIZE);
      passed++;
    end else begin
      if (verbose) $display("  FAIL: %0d/%0d columns incorrect", errors, VECTOR_SIZE);
      failed++;
    end
    
  endtask

  // ========== Main Test ==========
  initial begin
    logic signed [DATA_WIDTH-1:0] test_row_values [0:NUM_ROWS_PER_CLK-1][0:VECTOR_SIZE-1];
    int rand_valid, rand_sigma;
    
    passed = 0;
    failed = 0;

    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║           Update Dot Products Testbench                     ║");
    $display("╠══════════════════════════════════════════════════════════════╣");
    $display("║  NUM_ROWS_PER_CLK = %0d                                       ║", NUM_ROWS_PER_CLK);
    $display("║  VECTOR_SIZE      = %0d                                       ║", VECTOR_SIZE);
    $display("║  DATA_WIDTH       = %0d                                       ║", DATA_WIDTH);
    $display("║  ACCUM_WIDTH      = %0d                                      ║", ACCUM_WIDTH);
    $display("║  Random Tests     = %0d                                    ║", NUM_RANDOM_TESTS);
    $display("╚══════════════════════════════════════════════════════════════╝\n");

    // Initialize reset values to zero
    for (int i = 0; i < VECTOR_SIZE; i++) begin
      reset_values[i] = 16'sd0;
      expected_accum[i] = 16'sd0;
    end

    // Initialize
    rst_n = 0;
    clear = 0;
    j_rows_valid = '0;
    sigma_bits = '1;
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = 0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // ════════════════════════════════════════════════════════════════
    // Directed Tests
    // ════════════════════════════════════════════════════════════════
    
    $display("Running directed tests...\n");
    
    // Test 1: All ones, positive
    $display("Test 1: All 1s, all positive");
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        test_row_values[r][c] = 1;
    run_accumulation_test("Test 1", test_row_values, 4'b1111, 4'b1111, 1);

    // Test 2: Mixed values, all positive
    $display("Test 2: Mixed values, all positive");
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        test_row_values[r][c] = r + 1;
    run_accumulation_test("Test 2", test_row_values, 4'b1111, 4'b1111, 1);

    // Test 3: All negative
    $display("Test 3: All negative");
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        test_row_values[r][c] = 1;
    run_accumulation_test("Test 3", test_row_values, 4'b1111, 4'b0000, 1);

    // Test 4: Clear accumulator
    $display("Test 4: Clear accumulator");
    for (int i = 0; i < VECTOR_SIZE; i++) begin
      expected_accum[i] = 0;
    end
    @(posedge clk);
    clear = 1;
    @(posedge clk);
    clear = 0;
    @(posedge clk);
    
    if (accumulated_sums[0] === expected_accum[0]) begin
      $display("  PASS: Cleared to %0d", accumulated_sums[0]);
      passed++;
    end else begin
      $display("  FAIL: got %0d, expected %0d", accumulated_sums[0], expected_accum[0]);
      failed++;
    end

    // Test 5: Accumulate after clear
    $display("Test 5: Accumulate after clear");
    for (int r = 0; r < NUM_ROWS_PER_CLK; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        test_row_values[r][c] = r + c;
    run_accumulation_test("Test 5", test_row_values, 4'b1111, 4'b1111, 1);

    // ════════════════════════════════════════════════════════════════
    // Random Tests
    // ════════════════════════════════════════════════════════════════
    
    $display("\nRunning %0d random tests...", NUM_RANDOM_TESTS);
    
    for (int test_num = 0; test_num < NUM_RANDOM_TESTS; test_num++) begin
      // Generate random inputs
      for (int r = 0; r < NUM_ROWS_PER_CLK; r++) begin
        for (int c = 0; c < VECTOR_SIZE; c++) begin
          test_row_values[r][c] = $random() % (2**(DATA_WIDTH-1));
        end
      end
      
      // Generate random valid and sigma bits
      // Make sure at least one valid bit is set (otherwise done won't assert)
      rand_valid = $random() & ((1 << NUM_ROWS_PER_CLK) - 1);
      if (rand_valid == 0) rand_valid = 1;  // Ensure at least one bit is set
      
      rand_sigma = $random() & ((1 << NUM_ROWS_PER_CLK) - 1);
      
      // Display progress every 10 tests
      if (test_num % 10 == 0) begin
        $display("  Progress: %0d/%0d tests completed", test_num, NUM_RANDOM_TESTS);
      end
      
      run_accumulation_test($sformatf("Random test %0d", test_num), 
                           test_row_values, 
                           rand_valid[NUM_ROWS_PER_CLK-1:0], 
                           rand_sigma[NUM_ROWS_PER_CLK-1:0], 
                           0);
    end

    // ════════════════════════════════════════════════════════════════
    // Test with non-zero reset values
    // ════════════════════════════════════════════════════════════════
    
    $display("\nTest: Reset with non-zero reset values");
    
    // Set reset values to 100
    for (int i = 0; i < VECTOR_SIZE; i++) begin
      reset_values[i] = 16'sd100;
      expected_accum[i] = 16'sd100;
    end
    
    // Reset
    @(posedge clk);
    rst_n = 0;
    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    
    if (accumulated_sums[0] === expected_accum[0]) begin
      $display("  PASS: Reset to %0d", accumulated_sums[0]);
      passed++;
    end else begin
      $display("  FAIL: got %0d, expected %0d", accumulated_sums[0], expected_accum[0]);
      failed++;
    end

    // Run a few random tests from non-zero base
    $display("\nRunning 10 random tests from non-zero base...");
    for (int test_num = 0; test_num < 10; test_num++) begin
      for (int r = 0; r < NUM_ROWS_PER_CLK; r++) begin
        for (int c = 0; c < VECTOR_SIZE; c++) begin
          test_row_values[r][c] = $random() % (2**(DATA_WIDTH-1));
        end
      end
      
      // Ensure at least one valid bit is set
      rand_valid = $random() & ((1 << NUM_ROWS_PER_CLK) - 1);
      if (rand_valid == 0) rand_valid = 1;
      
      rand_sigma = $random() & ((1 << NUM_ROWS_PER_CLK) - 1);
      
      run_accumulation_test($sformatf("Non-zero base test %0d", test_num), 
                           test_row_values, 
                           rand_valid[NUM_ROWS_PER_CLK-1:0], 
                           rand_sigma[NUM_ROWS_PER_CLK-1:0], 
                           0);
    end

    // Test clear to non-zero reset value
    $display("\nTest: Clear back to reset value (100)");
    for (int i = 0; i < VECTOR_SIZE; i++) begin
      expected_accum[i] = 100;
    end
    
    @(posedge clk);
    clear = 1;
    @(posedge clk);
    clear = 0;
    @(posedge clk);
    
    if (accumulated_sums[0] === expected_accum[0]) begin
      $display("  PASS: Cleared to reset value %0d", accumulated_sums[0]);
      passed++;
    end else begin
      $display("  FAIL: got %0d, expected %0d", accumulated_sums[0], expected_accum[0]);
      failed++;
    end

    // ════════════════════════════════════════════════════════════════
    // Summary
    // ════════════════════════════════════════════════════════════════
    #20;
    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║                      TEST SUMMARY                            ║");
    $display("╠══════════════════════════════════════════════════════════════╣");
    $display("║  Passed: %5d                                               ║", passed);
    $display("║  Failed: %5d                                               ║", failed);
    $display("╠══════════════════════════════════════════════════════════════╣");
    if (failed == 0) begin
      $display("║  ✓ ALL TESTS PASSED                                          ║");
    end else begin
      $display("║  ✗ SOME TESTS FAILED                                         ║");
    end
    $display("╚══════════════════════════════════════════════════════════════╝\n");

    $finish;
  end

  initial begin
    $dumpfile("tb_update_dot_products.vcd");
    $dumpvars(0, tb_update_dot_products);
  end

endmodule