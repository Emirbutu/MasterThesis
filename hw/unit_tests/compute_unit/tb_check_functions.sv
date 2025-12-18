`include "tb_functions.svh"

module tb_check_funtions;
  localparam int VECTOR_SIZE = 256;
  localparam int DATA_WIDTH  = 4;

  logic [255:0] sigma_old, sigma_new, sigma_f, sigma_f_inv;
  logic [3:0]   J_square [0:255][0:255];
  longint iter_result, ham_result;
  int cols_processed;
  int mismatches;
  bit match;
  int seed = 1231521;   
  initial begin
    // Local autos for this initial block
    automatic int const_val = 3;
    automatic longint signed expected_energy;
    automatic longint signed ham_energy;
    automatic longint signed ham_energy_old;
    automatic longint signed ham_energy_new;
    automatic longint signed delta_energy;
    automatic longint signed expected_delta;
    automatic logic [1:0] sigma_r_test [0:255];
    automatic logic [1:0] sigma_c_test [0:255];
    automatic logic [3:0] j_column [0:255];
    automatic longint signed hw_accumulated_output;
    automatic longint signed column_output;
    automatic int columns_processed_hw;
    automatic logic sigma_c_bit;

    // TEST 1: Verify calculate_hamiltonian with constant J
    $display("\n=== TEST 1: Constant J Hamiltonian ===");
    
    // 1. Generate J matrix with constant value
    // mode=1 is constant value
    generate_j_matrix(VECTOR_SIZE, VECTOR_SIZE, DATA_WIDTH, 1, const_val, J_square);

    // 2. Set sigma_old to all 1s (spin +1)
    // '1 fills all bits with 1. Since we iterate up to VECTOR_SIZE, this effectively sets all spins to +1.
    sigma_old = '1; 

    // 3. Calculate expected energy: sum(s_i * J_ij * s_j) = sum(1 * C * 1) = N*N*C
    expected_energy = longint'(VECTOR_SIZE) * longint'(VECTOR_SIZE) * longint'(const_val);

    // 4. Calculate Hamiltonian using function
    ham_energy = calculate_hamiltonian(VECTOR_SIZE, DATA_WIDTH, sigma_old, J_square);

    $display("Configuration: J_ij = %0d, all spins = +1, VECTOR_SIZE = %0d", const_val, VECTOR_SIZE);
    $display("Expected Energy (N*N*C) : %0d", expected_energy);
    $display("Calculated Hamiltonian  : %0d", ham_energy);
    
    if (expected_energy == ham_energy)
        $display("Result: PASS\n");
    else
        $display("Result: FAIL\n");

    // TEST 2: Verify calculate_energy_difference with global flip
    $display("=== TEST 2: Energy Difference - Global Flip ===");
    
    // sigma_old = all +1, sigma_new = all -1 (global flip)
    sigma_old = '1;  // all +1
    sigma_new = '0;  // all -1
    
    // For constant J, H(+1,+1,...) = N*N*C and H(-1,-1,...) = N*N*C
    // So delta = 0
    expected_delta = 0;
    
    delta_energy = calculate_energy_difference(VECTOR_SIZE, DATA_WIDTH, sigma_old, sigma_new, J_square);
    
    $display("Configuration: J_ij = %0d, sigma_old = all +1, sigma_new = all -1", const_val);
    $display("Expected Delta (should be 0): %0d", expected_delta);
    $display("Calculated Delta            : %0d", delta_energy);
    
    if (expected_delta == delta_energy)
        $display("Result: PASS\n");
    else
        $display("Result: FAIL\n");

    // TEST 3: Verify energy difference with single spin flip
    $display("=== TEST 3: Energy Difference - Single Flip ===");
    
    // sigma_old = all +1, flip one spin to -1
    sigma_old = '1;
    sigma_new = '1;
     // or any value
    void'($urandom(seed));
    for (int i = 0; i < 127; i++) begin
    sigma_new[i] = $urandom_range(0, 1);
    end // Flip two spins from +1 to -1
    
    ham_energy_old = calculate_hamiltonian(VECTOR_SIZE, DATA_WIDTH, sigma_old, J_square);
    ham_energy_new = calculate_hamiltonian(VECTOR_SIZE, DATA_WIDTH, sigma_new, J_square);
    $display("Hamiltonian Old: %0d, New: %0d", ham_energy_old, ham_energy_new);
    delta_energy = calculate_energy_difference(VECTOR_SIZE, DATA_WIDTH, sigma_old, sigma_new, J_square);
    
    $display("Configuration: J_ij = %0d, flipped spins[2] and [5]", const_val);
    $display("Calculated Delta: %0d\n", delta_energy);

    // TEST 4: Verify calculate_expected_output (hardware model - iterative column processing)
    $display("=== TEST 4: Hardware Model - calculate_expected_output ===");
    
    // Use same sigma_old and sigma_new from TEST 3
    // Generate sigma_f and sigma_f_inv
    generate_sigma_f(sigma_old, sigma_new, sigma_f, sigma_f_inv);
    
    // Generate sigma_r and sigma_c for hardware model
    generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r_test);
    generate_sigma_c(VECTOR_SIZE, sigma_f, sigma_new, sigma_c_test);
    
    // Display sigma vectors for debugging
    $display("sigma_old[7:0]: %b", sigma_old[255:0]);
    $display("sigma_new[7:0]: %b", sigma_new[255:0]);
    $display("sigma_f[7:0]:   %b", sigma_f[255:0]);
    
    // Initialize accumulator
    hw_accumulated_output = 0;
    columns_processed_hw = 0;
    
    // Iterate through all columns, process only changing columns (sigma_c != 00)
    for (int col = 0; col < VECTOR_SIZE; col++) begin
      if (sigma_c_test[col] != 2'b00) begin
        // Extract this column from J matrix
        for (int row = 0; row < VECTOR_SIZE; row++) begin
          j_column[row] = J_square[col][row];
        end
        
        // Convert 2-bit sigma_c to 1-bit: 01→1 (positive), 10→0 (negative)
        sigma_c_bit = (sigma_c_test[col] == 2'b01) ? 1'b1 : 1'b0;
        
        // Call calculate_expected_output for this column
        column_output = calculate_expected_output(
          1,              // COL_PER_CC = 1 (process one column per call)
          VECTOR_SIZE,    // VECTOR_SIZE
          DATA_WIDTH,     // DATA_WIDTH
          sigma_r_test,   // sigma_r array
          sigma_c_bit,    // sigma_c for this column
          j_column        // J column
        );
        
        // Accumulate
        hw_accumulated_output += column_output;
        columns_processed_hw++;
        
        $display("Col[%0d]: sigma_c=%b, column_output=%0d, accumulated=%0d", 
                 col, sigma_c_test[col], column_output, hw_accumulated_output);
      end
    end
    
    $display("\n--- Hardware Model Summary ---");
    $display("Columns processed: %0d", columns_processed_hw);
    $display("Accumulated hardware output: %0d", 4*hw_accumulated_output);
    $display("Energy difference from TEST 3: %0d", delta_energy);
    $display("Match: %s\n", (4*hw_accumulated_output == delta_energy) ? "PASS ✓" : "FAIL ✗");

    $finish;
  end
endmodule