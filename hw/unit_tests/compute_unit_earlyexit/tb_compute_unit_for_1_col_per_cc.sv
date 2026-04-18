`timescale 1ns / 1ps
`include "tb_functions.svh"
module tb_compute_unit;

  // ========== Parameters ==========
  parameter int VECTOR_SIZE = 256;
  parameter int DATA_WIDTH = 4;
  parameter int COL_PER_CC = 1;  // Process one column per cycle
  parameter int ACCUM_WIDTH = DATA_WIDTH + $clog2(VECTOR_SIZE * VECTOR_SIZE) + 1;
  
  // ========== Clock and Reset ==========
  logic clk;
  logic rst_n;
  int  total_tests = 1000;
  // ========== DUT Signals ==========
  logic sigma_c [0:COL_PER_CC-1];
  logic [1:0] sigma_r [0:VECTOR_SIZE-1];
  logic [DATA_WIDTH-1:0] j_cols [0:COL_PER_CC-1][0:VECTOR_SIZE-1];
  logic [COL_PER_CC-1:0] valid_i;
  logic [COL_PER_CC-1:0] final_flag_i;
  logic clear;
  logic signed [ACCUM_WIDTH-1:0] accum_out;
  logic final_flag_o;
  
  // ========== Test Variables ==========
  logic [255:0] sigma_old;
  logic [255:0] sigma_new;
  logic [3:0] J_matrix [0:255][0:255];
  longint signed expected_energy;
  longint signed dut_energy;
  int num_cols_sent;
  
  // ========== Clock Generation ==========
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100 MHz clock
  end
  
  // ========== DUT Instantiation ==========
  compute_unit #(
    .VECTOR_SIZE(VECTOR_SIZE),
    .DATA_WIDTH(DATA_WIDTH),
    .COL_PER_CC(COL_PER_CC),
    .PIPED_FIRST_TREE(0),  // No pipelining for now
    .PIPED_SECOND_TREE(0)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .sigma_c(sigma_c),
    .sigma_r(sigma_r),
    .j_cols(j_cols),
    .valid_i(valid_i),
    .final_flag_i(final_flag_i),
    .clear(clear),
    .accum_out(accum_out),
    .final_flag_o(final_flag_o)
  );
  
  // ========== Test Procedure ==========
  initial begin
    logic [255:0] sigma_f, sigma_f_inv;
    int num_flips;
    longint signed full_hamiltonian_diff;
    int test_num, num_tests_passed, num_cols_sent;
    logic temp_valid, temp_final;
    logic [1:0] sigma_c_2bit [0:255];
    logic [1:0] sigma_r_2bit [0:255];
    int total_changed_cols;
    
    num_tests_passed = 0;
    
    // === Initialize ===
    $display("\n========================================");
    $display("Initialize Hardware");
    $display("========================================");
    
    rst_n = 0;
    clear = 0;
    valid_i = 0;
    final_flag_i = 0;
    
    for (int i = 0; i < COL_PER_CC; i++) sigma_c[i] = 0;
    for (int i = 0; i < VECTOR_SIZE; i++) sigma_r[i] = 2'b00;
    for (int col = 0; col < COL_PER_CC; col++)
      for (int row = 0; row < VECTOR_SIZE; row++)
        j_cols[col][row] = '0;
    
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);
    $display("Reset released\n");
    
    // Run multiple tests
    for (test_num = 1; test_num <= total_tests; test_num++) begin
      $display("\n████████████████████████████████████████");
      $display("█  TEST %0d / 5                         █", test_num);
      $display("████████████████████████████████████████\n");
    
      // Generate test case
      generate_j_matrix(VECTOR_SIZE, DATA_WIDTH, 0, 0, J_matrix);
      sigma_old = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom};
      sigma_new = {$urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom, $urandom};
      
      num_flips = 0;
      for (int i = 0; i < VECTOR_SIZE; i++)
        if (sigma_old[i] != sigma_new[i]) num_flips++;
      
      $display("Generated symmetric J matrix (random 4-bit)");
      $display("Number of flipped spins: %0d", num_flips);
      
      // Calculate full Hamiltonian energy difference
      full_hamiltonian_diff = calculate_energy_difference(VECTOR_SIZE, DATA_WIDTH, sigma_old, sigma_new, J_matrix);
      $display("Full Hamiltonian ΔE: %0d\n", full_hamiltonian_diff);
      
      // Clear accumulator
      @(posedge clk);
      clear = 1;
      @(posedge clk);
      clear = 0;
      @(posedge clk);
      
      // Feed all columns to DUT
      $display("Feeding inputs to DUT...");
      
      // Generate control signals
      generate_sigma_f(sigma_old, sigma_new, sigma_f, sigma_f_inv);
      
      // Prepare inputs: get sigma_r, sigma_c, and count columns
      total_changed_cols = 0;
      
      generate_sigma_c(VECTOR_SIZE, sigma_f, sigma_new, sigma_c_2bit);
      generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r_2bit);
      
      // Copy sigma_r (same for all columns)
      for (int i = 0; i < VECTOR_SIZE; i++)
        sigma_r[i] = sigma_r_2bit[i];
      
      // Count columns to send
      for (int col = 0; col < VECTOR_SIZE; col++)
        if (sigma_c_2bit[col] != 2'b00) total_changed_cols++;
      
      $display("Total columns to process: %0d", total_changed_cols);
      
      // Send columns one by one
      num_cols_sent = 0;
      for (int col = 0; col < VECTOR_SIZE; col++) begin
        if (sigma_c_2bit[col] != 2'b00) begin
          // Load J column
          for (int row = 0; row < VECTOR_SIZE; row++)
            j_cols[0][row] = J_matrix[col][row];
          
          // Convert sigma_c: 01→1, 10→0
          sigma_c[0] = (sigma_c_2bit[col] == 2'b01) ? 1'b1 : 1'b0;
          
          // Set control signals
          valid_i[0] = 1'b1;
          num_cols_sent++;
          final_flag_i[0] = (num_cols_sent == total_changed_cols) ? 1'b1 : 1'b0;
          
          @(posedge clk);
        end
      end
      
      // Deassert valid
      valid_i[0] = 1'b0;
      
      // Wait for DUT to respond with final_flag_o
      while (!final_flag_o) @(posedge clk);
      @(posedge clk);
      
      // Deassert final_flag
      final_flag_i[0] = 1'b0;
      
      // Compare results
      $display("\n=== RESULTS ===");
      $display("Columns sent:         %0d", num_cols_sent);
      $display("DUT output:           %0d", accum_out);
      $display("4 × DUT:              %0d", 4 * accum_out);
      $display("Hamiltonian ΔE:       %0d", full_hamiltonian_diff);
      $display("Match:                %s", (4 * accum_out == full_hamiltonian_diff) ? "YES ✓" : "NO ✗");
      
      if (4 * accum_out == full_hamiltonian_diff) begin
        $display("\n╔════════════════════════════════╗");
        $display("║   ✓✓✓ TEST %0d PASSED ✓✓✓      ║", test_num);
        $display("╚════════════════════════════════╝");
        num_tests_passed++;
      end else begin
        $display("\n╔════════════════════════════════╗");
        $display("║   ✗✗✗ TEST %0d FAILED ✗✗✗      ║", test_num);
        $display("╚════════════════════════════════╝");
        $display("Diff: %0d", (4 * accum_out) - full_hamiltonian_diff);
        $error("Test %0d failed!", test_num);
      end
    end  // End of test loop
    
    // === FINAL SUMMARY ===
    repeat(10) @(posedge clk);
    $display("");
    $display("████████████████████████████████████████");
    $display("█  FINAL SUMMARY                       █");
    $display("████████████████████████████████████████");
    $display("");
    $display("Total tests run:    5");
    $display("Tests passed:       %0d", num_tests_passed);
    $display("Tests failed:       %0d", 5 - num_tests_passed);
    $display("");
    
    if (num_tests_passed == total_tests) begin
      $display("╔════════════════════════════════════════╗");
      $display("║  ★★★ ALL TESTS PASSED ★★★             ║");
      $display("║  Hardware verification complete!       ║");
      $display("╚════════════════════════════════════════╝");
    end else begin
      $display("╔════════════════════════════════════════╗");
      $display("║  ⚠⚠⚠ SOME TESTS FAILED ⚠⚠⚠           ║");
      $display("║  %0d/%0d tests passed                     ║", num_tests_passed,  total_tests);
      $display("╚════════════════════════════════════════╝");
      $error("%0d test(s) failed!", 5 - num_tests_passed);
    end
    
    $display("");
    $finish;
  end
 // === VCD ===
 // initial begin
 //   $dumpfile("compute_unit_tb.vcd");
 //   $dumpvars(0, tb_compute_unit);
 // end
endmodule
