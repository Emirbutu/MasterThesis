`timescale 1ns/1ps
`include "tb_functions.svh"

module tb_compute_unit;

// Parameters
parameter int VECTOR_SIZE = 256;
parameter int COL_PER_CC = 4;
parameter int DATA_WIDTH = 4;
parameter int ACCUM_WIDTH = DATA_WIDTH + $clog2(VECTOR_SIZE * VECTOR_SIZE) + 1;

// Clock and reset
int pos ;
 int num_flips_to_make;
 int cols_sent;
 int flip_positions[4];
logic clk;
logic rst_n;
// DUT signals
logic [DATA_WIDTH-1:0] j_matrix [0:COL_PER_CC-1][0:VECTOR_SIZE-1];
logic [1:0] sigma_c [0:VECTOR_SIZE-1];
logic [1:0] sigma_r [0:VECTOR_SIZE-1];
logic  sigma_c_in  [0:COL_PER_CC-1];
logic [COL_PER_CC-1:0] valid_i;
logic [COL_PER_CC-1:0] final_flag_i;
logic rst_accum_i;
logic signed [ACCUM_WIDTH-1:0] accum_out_o;
logic final_flag_o;
longint signed hamiltonian_delta;
longint signed dut_scaled;
// Test variables
logic [DATA_WIDTH-1:0] J_full_matrix [0:VECTOR_SIZE-1][0:VECTOR_SIZE-1];
logic [VECTOR_SIZE-1:0] sigma_old;
logic [VECTOR_SIZE-1:0] sigma_new;
logic [VECTOR_SIZE-1:0] sigma_f;
logic [VECTOR_SIZE-1:0] sigma_f_inv;
int flip_count;
int i, j, row, col;
int flipped_cols[256];
int num_flipped;
int num_cycles;
int cols_in_this_cycle;
int global_col_idx;
int timeout;
int wait_cycles;
int actual_col;
longint signed cycle_expected;
longint signed total_expected;
int num_edge_tests;      // Edge case tests
int num_random_tests ;   // Random tests
int num_tests ;
int num_passed ;
int num_failed ;
int edge_flip_counts[6];  // Edge cases: 0, 1, 2, 4, half, all
int target_flips; 
int flip_pos;
// Clock generation
initial begin
  clk = 0;
  forever #5 clk = ~clk;
end

// DUT instantiation
compute_unit #(
  .VECTOR_SIZE(VECTOR_SIZE),
  .COL_PER_CC(COL_PER_CC),
  .DATA_WIDTH(DATA_WIDTH)
) dut (
  .clk(clk),
  .rst_n(rst_n),
  .j_cols(j_matrix),
  .sigma_r(sigma_r),
  .sigma_c(sigma_c_in),
  .valid_i(valid_i),
  .final_flag_i(final_flag_i),
  .clear(rst_accum_i),
  .accum_out(accum_out_o),
  .final_flag_o(final_flag_o)
);

// Test sequence
initial begin
  num_edge_tests = 6;      // Edge case tests
  num_random_tests = 1000;   // Random tests
  num_tests = num_edge_tests + num_random_tests;
  num_passed = 0;
  num_failed = 0;
  edge_flip_counts = '{0, 1, 2, 4, 128, 256};  // Edge cases: 0, 1, 2, 4, half, all
  
  $display("========================================");
  $display("=== COMPUTE UNIT TEST SUITE ===");
  $display("=== COL_PER_CC = %0d ===", COL_PER_CC);
  $display("=== %0d edge cases + %0d random tests ===", num_edge_tests, num_random_tests);
  $display("========================================\n");
  
  for (int test_num = 0; test_num < num_tests; test_num++) begin
    $display("\n--- Test %0d/%0d ---", test_num+1, num_tests);

  // STEP 1: Initialize all signals
  //$display("STEP 1: Initialize signals");
  rst_n = 0;
  valid_i = '0;
  final_flag_i = '0;
  rst_accum_i = 0;
  sigma_c_in[0] = '0;
  sigma_c_in[1] = '0;
  sigma_c_in[2] = '0;
  sigma_c_in[3] = '0;

  for (int i = 0; i < COL_PER_CC; i++) begin
    for (int j = 0; j < VECTOR_SIZE; j++) begin
      j_matrix[i][j] = '0;
    end
  end
  #10;
  
  // STEP 2: Reset DUT
  //$display("STEP 2: Reset DUT");
  @(posedge clk);
  rst_n = 1;
  @(posedge clk);
  //$display("  Reset complete\n");

  // STEP 3: Generate test vectors
  //$display("STEP 3: Generate test vectors");
  
  // Generate random sigma_old
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_old[i] = $urandom_range(0, 1);
  end
  
  // Edge case tests vs random tests
  if (test_num < num_edge_tests) begin
    // Edge case: flip specific number of bits
    target_flips = edge_flip_counts[test_num];
    sigma_new = sigma_old;  // Start identical
    
    // Flip exactly target_flips bits at random positions
    for (int i = 0; i < target_flips; i++) begin
      flip_pos = $urandom_range(0, VECTOR_SIZE-1);
      // Ensure we don't flip the same bit twice
      while (sigma_new[flip_pos] != sigma_old[flip_pos]) begin
        flip_pos = $urandom_range(0, VECTOR_SIZE-1);
      end
      sigma_new[flip_pos] = ~sigma_old[flip_pos];
    end
    $display("  [EDGE CASE: %0d bit(s) flipped]", target_flips);
  end else begin
    sigma_new = sigma_old;  // Start identical
    // Random test: generate completely random sigma_new
    for (int i = 0; i < VECTOR_SIZE; i++) begin
      sigma_new[i % 15] = $urandom_range(0, 1);
    end
  end

  // Generate sigma_f and sigma_f_inv
  generate_sigma_f(sigma_old, sigma_new, sigma_f, sigma_f_inv);
  generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r);
  //$display("  Generated sigma_f (should have exactly 4 flipped bits) and sigma_r");
  
  //$display("STEP 4: Package flipped columns for DUT");
  
  // First, identify which columns are flipped
  num_flipped = 0;
  
  for (i = 0; i < VECTOR_SIZE; i++) begin
    if (sigma_f[i]) begin
      flipped_cols[num_flipped] = i;
      num_flipped++;
    end
  end
  
  // Generate J matrix (symmetric)
  generate_j_matrix(VECTOR_SIZE, DATA_WIDTH, 0, 5, J_full_matrix);
  
  // Verify J matrix is symmetric (J[i][j] == J[j][i])
  //for (int i = 0; i < 10; i++) begin
  //  for (int j = 0; j < 10; j++) begin
  //    if (J_full_matrix[i][j] != J_full_matrix[j][i]) begin
  //      $error("J matrix not symmetric at [%0d][%0d]: J[i][j]=%0d, J[j][i]=%0d",
  //             i, j, J_full_matrix[i][j], J_full_matrix[j][i]);
  //    end
  //  end
  //end
 
  //$display("\n========================================");
  //$display("Initialization complete. Ready for next steps.");
  //$display("========================================\n");
  //$display("\nSTEP 4 complete.\n");
  
  // STEP 5: Clear accumulator
  //$display("STEP 5: Clear accumulator");
  @(posedge clk);
  rst_accum_i = 1;
  @(posedge clk);
  rst_accum_i = 0;
  @(posedge clk);
  //$display("  Accumulator cleared\n");
  
  // STEP 6: Feed columns to DUT using task
  //$display("STEP 6: Feed columns to DUT using apply_compute_inputs task");
  
 
  
  apply_compute_inputs(
    VECTOR_SIZE,
    DATA_WIDTH,
    sigma_old,
    sigma_new,
    J_full_matrix,
    sigma_c_in,
    sigma_r,
    j_matrix,
    valid_i,
    final_flag_i,
    clk,
    cols_sent
  );
  
  //$display("  Task completed. Columns sent: %0d", cols_sent);
  
  // STEP 7: Wait for DUT final flag
  //$display("\nSTEP 7: Wait for DUT to complete");
  
  timeout = 500;  // Increased for tests with many flipped bits
  wait_cycles = 0;
  
  while (!final_flag_o && wait_cycles < timeout) begin
    @(posedge clk);
    wait_cycles++;
  end
  
  if (final_flag_o) begin
    //$display("  Final flag received after %0d cycles", wait_cycles);
  //  $display("  DUT output: %0d", accum_out_o);
  end else begin
    $error("Timeout waiting for final_flag_o");
  end
  
  // STEP 8: Verify result
  //$display("\nSTEP 8: Verify against Hamiltonian energy difference");
  
  hamiltonian_delta = calculate_energy_difference(VECTOR_SIZE, DATA_WIDTH, sigma_old, sigma_new, J_full_matrix);
  dut_scaled = longint'(accum_out_o) * 4;
  
  $display("  Flipped: %0d, delta_E: %0d, DUT×4: %0d", num_flipped, hamiltonian_delta, dut_scaled);
  
  if (hamiltonian_delta == dut_scaled) begin
    $display("  Result: PASS ✓");
    num_passed++;
  end else begin
    $display("  Result: FAIL ✗ (Expected: %0d, Got: %0d)", hamiltonian_delta, dut_scaled);
    num_failed++;
  end
  
  end // for test_num
  
  $display("\n========================================");
  $display("=== TEST SUITE SUMMARY ===");
  $display("========================================");
  $display("Total tests:  %0d", num_tests);
  $display("Passed:       %0d", num_passed);
  $display("Failed:       %0d", num_failed);
  $display("Success rate: %0d%%", (num_passed * 100) / num_tests);
  
  if (num_failed == 0) begin
    $display("\n╔════════════════════════════════╗");
    $display("║  ✓✓✓ ALL TESTS PASSED ✓✓✓     ║");
    $display("╚════════════════════════════════╝");
  end else begin
    $display("\n╔════════════════════════════════╗");
    $display("║  ✗✗✗ SOME TESTS FAILED ✗✗✗    ║");
    $display("╚════════════════════════════════╝");
  end
  
  $display("\n========================================\n");
  $finish;
end
 // === VCD ===
  initial begin
    $dumpfile("compute_unit_tb.vcd");
    $dumpvars(0, tb_compute_unit);
  end

endmodule