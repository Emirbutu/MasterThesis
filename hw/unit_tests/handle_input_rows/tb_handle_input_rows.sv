`timescale 1ns/1ps

module tb_handle_input_rows;

  // ========== Parameters ==========
  localparam int NUM_ROWS    = 4;
  localparam int VECTOR_SIZE = 8;
  localparam int DATA_WIDTH  = 4;
  localparam bit PIPED       = 1;
  localparam int LEVELS      = (NUM_ROWS > 1) ? $clog2(NUM_ROWS) : 0;
  localparam logic [LEVELS:0] PIPE_STAGE_MASK = '1;

  localparam int MUX_OUT_WIDTH     = DATA_WIDTH + 1;
  localparam int WIDTH_BEFORE_TREE = MUX_OUT_WIDTH + 1;
  localparam int OUTPUT_WIDTH      = DATA_WIDTH + 1 + LEVELS + 1;

  // ========== Signals ==========
  logic clk;
  logic rst_n;
  logic signed [DATA_WIDTH-1:0] j_rows [0:NUM_ROWS-1][0:VECTOR_SIZE-1];
  logic [NUM_ROWS-1:0] j_rows_valid;
  logic [NUM_ROWS-1:0] sigma_bits;
  logic signed [OUTPUT_WIDTH-1:0] column_sums [0:VECTOR_SIZE-1];
  logic done;

  // ========== Test Variables ==========
  int passed, failed;
  logic signed [OUTPUT_WIDTH-1:0] expected_sum;
  logic signed [OUTPUT_WIDTH-1:0] captured_sum;

  // ========== Clock Generation ==========
  initial clk = 0;
  always #5 clk = ~clk;

  // ========== DUT ==========
  handle_input_rows #(
    .NUM_ROWS       (NUM_ROWS),
    .VECTOR_SIZE    (VECTOR_SIZE),
    .DATA_WIDTH     (DATA_WIDTH),
    .PIPED          (PIPED),
    .LEVELS         (LEVELS),
    .PIPE_STAGE_MASK(PIPE_STAGE_MASK)
  ) dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .j_rows      (j_rows),
    .j_rows_valid(j_rows_valid),
    .sigma_bits  (sigma_bits),
    .column_sums (column_sums),
    .done        (done)
  );

  // ========== Helper Functions ==========

  // Calculate expected sum
  function automatic logic signed [OUTPUT_WIDTH-1:0] calc_expected(
    input logic signed [DATA_WIDTH-1:0] row_values [0:NUM_ROWS-1],
    input logic [NUM_ROWS-1:0] valid,
    input logic [NUM_ROWS-1:0] sigma
  );
    logic signed [OUTPUT_WIDTH-1:0] sum;
    logic signed [WIDTH_BEFORE_TREE-1:0] term;
    logic signed [MUX_OUT_WIDTH-1:0] shifted;
    
    sum = 0;
    for (int r = 0; r < NUM_ROWS; r++) begin
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

  // ========== Main Test ==========
  initial begin
    logic signed [DATA_WIDTH-1:0] test_row_values [0:NUM_ROWS-1];
    
    passed = 0;
    failed = 0;

    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════╗");
    $display("║           Handle Input Rows Testbench                        ║");
    $display("╠══════════════════════════════════════════════════════════════╣");
    $display("║  NUM_ROWS       = %0d                                         ║", NUM_ROWS);
    $display("║  VECTOR_SIZE    = %0d                                         ║", VECTOR_SIZE);
    $display("║  DATA_WIDTH     = %0d                                         ║", DATA_WIDTH);
    $display("║  OUTPUT_WIDTH   = %0d                                         ║", OUTPUT_WIDTH);
    $display("╚══════════════════════════════════════════════════════════════╝\n");

    // Initialize
    rst_n = 0;
    j_rows_valid = '0;
    sigma_bits = '1;
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = 0;

    @(posedge clk);
    @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    // ════════════════════════════════════════════════════════════════
    // Test 1: All rows = 1, all valid, all sigma = 1 (positive)
    // Expected: 4 rows × 1 × 2 = 8
    // ════════════════════════════════════════════════════════════════
    $display("Test 1: All rows = 1, all valid, all sigma = 1");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 1;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1111);
    
    // Apply inputs
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1111;
    
    // Valid for 1 cycle only
    @(posedge clk);
    j_rows_valid = '0;
    
    // Wait for done
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 2: All rows = 1, all valid, all sigma = 0 (negative)
    // Expected: -8
    // ════════════════════════════════════════════════════════════════
    $display("Test 2: All rows = 1, all valid, all sigma = 0");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 1;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b0000);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b0000;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 3: Rows = 1, 2, 3, 4, all valid, all sigma = 1
    // Expected: (1+2+3+4) × 2 = 20
    // ════════════════════════════════════════════════════════════════
    $display("Test 3: Rows = 1,2,3,4, all valid, all sigma = 1");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 4: Only row 0 valid
    // Expected: 1 × 2 = 2
    // ════════════════════════════════════════════════════════════════
    $display("Test 4: Only row 0 valid");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b0001, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0001;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 5: Only row 1 valid
    // Expected: 2 × 2 = 4
    // ════════════════════════════════════════════════════════════════
    $display("Test 5: Only row 1 valid");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b0010, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0010;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 6: Only row 2 valid
    // Expected: 3 × 2 = 6
    // ════════════════════════════════════════════════════════════════
    $display("Test 6: Only row 2 valid");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b0100, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0100;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 7: Only row 3 valid
    // Expected: 4 × 2 = 8
    // ════════════════════════════════════════════════════════════════
    $display("Test 7: Only row 3 valid");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b1000, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1000;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 8: Rows 0 and 2 valid
    // Expected: (1 + 3) × 2 = 8
    // ════════════════════════════════════════════════════════════════
    $display("Test 8: Rows 0 and 2 valid");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = r + 1;
    expected_sum = calc_expected(test_row_values, 4'b0101, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0101;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 9: Mixed sigma (row0 pos, row1 neg)
    // Rows = 2, 2, 2, 2, valid = 0011
    // Expected: 2×2×(+1) + 2×2×(-1) = 4 - 4 = 0
    // ════════════════════════════════════════════════════════════════
    $display("Test 9: Mixed sigma (row0 pos, row1 neg)");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 2;
    expected_sum = calc_expected(test_row_values, 4'b0011, 4'b0001);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0011;
    sigma_bits = 4'b0001;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 10: Alternating sigma
    // Rows = 1, 1, 1, 1, valid = 1111, sigma = 1010
    // Expected: -2 + 2 - 2 + 2 = 0
    // ════════════════════════════════════════════════════════════════
    $display("Test 10: Alternating sigma");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 1;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1010);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1010;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 11: Negative row values
    // Rows = -1, -2, -3, -4, valid = 1111, sigma = 1111
    // Expected: (-1-2-3-4) × 2 = -20
    // ════════════════════════════════════════════════════════════════
    $display("Test 11: Negative row values");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = -(r + 1);
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 12: Negative rows with sigma = 0 (double negative)
    // Expected: +20
    // ════════════════════════════════════════════════════════════════
    $display("Test 12: Negative rows with sigma = 0");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = -(r + 1);
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b0000);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b0000;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 13: Max positive (7)
    // Expected: 4 × 7 × 2 = 56
    // ════════════════════════════════════════════════════════════════
    $display("Test 13: Max positive (7)");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 7;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 14: Max negative (-8)
    // Expected: 4 × (-8) × 2 = -64
    // ════════════════════════════════════════════════════════════════
    $display("Test 14: Max negative (-8)");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = -8;
    expected_sum = calc_expected(test_row_values, 4'b1111, 4'b1111);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b1111;
    sigma_bits = 4'b1111;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
    end

    // ════════════════════════════════════════════════════════════════
    // Test 15: Single row valid with negative sigma
    // Rows = 5, valid = 0100, sigma = 0000
    // Expected: -5 × 2 = -10
    // ════════════════════════════════════════════════════════════════
    $display("Test 15: Single row valid with negative sigma");
    for (int r = 0; r < NUM_ROWS; r++) test_row_values[r] = 5;
    expected_sum = calc_expected(test_row_values, 4'b0100, 4'b0000);
    
    @(posedge clk);
    for (int r = 0; r < NUM_ROWS; r++)
      for (int c = 0; c < VECTOR_SIZE; c++)
        j_rows[r][c] = test_row_values[r];
    j_rows_valid = 4'b0100;
    sigma_bits = 4'b0000;
    
    @(posedge clk);
    j_rows_valid = '0;
    
    @(posedge done);
    @(posedge clk);
    captured_sum = column_sums[0];
    
    if (captured_sum === expected_sum) begin
      $display("  PASS: got %0d, expected %0d", captured_sum, expected_sum);
      passed += VECTOR_SIZE;
    end else begin
      $display("  FAIL: got %0d, expected %0d", captured_sum, expected_sum);
      failed += VECTOR_SIZE;
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
  $dumpfile("tb_handle_input_rows.vcd");
  $dumpvars(0, tb_handle_input_rows);
 
end
endmodule