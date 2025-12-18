// tb_functions.svh
// Testbench utility functions for compute_unit

// Generate sigma_f and sigma_f_inv from sigma_previous and sigma_new
// sigma_f = sigma_previous XOR sigma_new (flipped bits)
// sigma_f_inv = NOT sigma_f (non-flipped bits)
function automatic void generate_sigma_f(
  input logic [255:0] sigma_previous,
  input logic [255:0] sigma_new,
  output logic [255:0] sigma_f,
  output logic [255:0] sigma_f_inv
);
  sigma_f = sigma_previous ^ sigma_new;  // XOR to find flipped bits
  sigma_f_inv = ~sigma_f;                // Invert to get non-flipped bits
endfunction

// Generate sigma_c from sigma_f and sigma_new
// sigma_c encoding: 00 = zero, 01 = +element, 10 = -element
function automatic void generate_sigma_c(
  input int VECTOR_SIZE,
  input logic [255:0] sigma_f,
  input logic [255:0] sigma_new,
  output logic [1:0] sigma_c [0:255]
);
  // Initialize all to zero first
  for (int i = 0; i < 256; i++) begin
    sigma_c[i] = 2'b00;
  end
  
  // Fill only the active region
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_c[i] = sigma_f[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00;
  end
endfunction

// Generate sigma_r from sigma_f_inv and sigma_new
// sigma_f_inv = ~sigma_f (bitwise NOT, equivalent to 1 - sigma_f for binary)
// sigma_r encoding: 00 = zero, 01 = +element, 10 = -element
function automatic void generate_sigma_r(
  input int VECTOR_SIZE,
  input logic [255:0] sigma_f_inv,
  input logic [255:0] sigma_new,
  output logic [1:0] sigma_r [0:255]
);
  // Initialize all to zero first
  for (int i = 0; i < 256; i++) begin
    sigma_r[i] = 2'b00;
  end
  
  // Fill only the active region
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_r[i] = sigma_f_inv[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00;
  end
endfunction


function automatic void generate_j_matrix(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input int mode,
  input int const_val,
  output logic [3:0] j_matrix [0:255][0:255]  // Fixed size, max 16-bit data
);
  int max_val;
  logic [3:0] temp_val;
  
  // Calculate max for unsigned DATA_WIDTH
  max_val = (2**DATA_WIDTH) - 1;
  
  // Initialize entire array to 0 first (to avoid X's in uninitialized locations)
  for (int i = 0; i < 256; i++) begin
    for (int j = 0; j < 256; j++) begin
      j_matrix[i][j] = '0;
    end
  end
  
  // Fill the specified region with SYMMETRIC values
  // Only fill upper triangle, then mirror to lower triangle
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    for (int j = i; j < VECTOR_SIZE; j++) begin
      case (mode)
        0: begin // Random
          temp_val = $urandom() % (max_val + 1);
        end
        1: begin // Constant
          temp_val = const_val;
        end
        2: begin // Sequential
          temp_val = (i + j) % (max_val + 1);
        end
        default: temp_val = '0;
      endcase
      
      // Set both J[i][j] and J[j][i] to ensure symmetry
      j_matrix[i][j] = temp_val;
      j_matrix[j][i] = temp_val;
    end
  end
endfunction

// Calculate Hamiltonian energy: H = sigma * J * sigma^T
// sigma: binary vector [0:VECTOR_SIZE-1] where 0→-1, 1→+1 (Ising spins)
// J: full square matrix [row][col]
// Returns: scalar energy value
function automatic longint signed calculate_hamiltonian(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma,
  input logic [3:0] J [0:255][0:255]  // Fixed size, max 16-bit data
);
  logic signed [23:0] energy;
  logic  signed [4:0] term;
  int signed spin_i, spin_j;
  logic [3:0] j_val;
  
  energy = 0;
  
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    // Convert binary to spin: 0→-1, 1→+1
    spin_i = sigma[i] ? 1 : -1;
    
    for (int j = 0; j < VECTOR_SIZE; j++) begin
      // Convert binary to spin: 0→-1, 1→+1
      spin_j = sigma[j] ? 1 : -1;
      
        // Cast J element to a signed int before arithmetic to avoid width/overflow quirks
        j_val = (J[i][j]);
        term = spin_i * j_val * spin_j;
        energy += term;
    end
  end
  
  return energy;
endfunction

// Calculate energy difference: delta_H = H_new - H_old
// Uses calculate_hamiltonian to compute energy for both states
function automatic longint signed calculate_energy_difference(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma_old,
  input logic [255:0] sigma_new,
  ref logic [3:0] J [0:255][0:255]  // Fixed size, max 16-bit data
);
  longint signed energy_old, energy_new, delta_energy;
  
  // Calculate energy for old sigma state
  energy_old = calculate_hamiltonian(VECTOR_SIZE, DATA_WIDTH, sigma_old, J);
  
  // Calculate energy for new sigma state
  energy_new = calculate_hamiltonian(VECTOR_SIZE, DATA_WIDTH, sigma_new, J);
  
  // Return the difference
  delta_energy = energy_new - energy_old;
  
  return delta_energy;
endfunction

// Calculate expected output from compute_unit (software model)
// Models the hardware computation: sigma_r * J * sigma_c, scaled by 4
// sigma_r: 2-bit encoding (00=0, 01=+1, 10=-1) per row
// sigma_c: 1-bit per column (1=positive, 0=negative)
// Returns: expected energy difference * 4
function automatic longint signed calculate_expected_output_4cols(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [1:0] sigma_r [0:255],         // sigma_r encoding for all rows
  input logic sigma_c_in [0:3],              // sigma_c for 4 columns (1-bit each)
  input logic [0:3] valid,                   // valid bits for 4 columns
  ref logic [3:0] j_cols [0:3][0:255]       // 4 J columns
);
  longint signed total_sum;
  longint signed column_sum;
  int signed sigma_r_val;
  int signed j_val;
  
  total_sum = 0;
  
  // Process each of the 4 columns
  for (int col = 0; col < 4; col++) begin
    if (valid[col]) begin
      column_sum = 0;
      
      // Compute dot product for this column: sum(sigma_r[row] * J[col][row])
      for (int row = 0; row < VECTOR_SIZE; row++) begin
        // Decode sigma_r: 00→0, 01→+1, 10→-1
        case (sigma_r[row])
          2'b00: sigma_r_val = 0;
          2'b01: sigma_r_val = 1;
          2'b10: sigma_r_val = -1;
          default: sigma_r_val = 0;
        endcase
        
        // Accumulate: sigma_r_val * J[col][row]
        j_val = $signed(j_cols[col][row]);
        column_sum += sigma_r_val * j_val;
      end
      
      // Apply sigma_c sign selection
      // sigma_c=1 → keep positive, sigma_c=0 → negate
      if (sigma_c_in[col]) begin
        total_sum += column_sum;
      end else begin
        total_sum += (-column_sum);
      end
    end
  end
  
  return total_sum;
endfunction

// Prepare inputs for compute_unit DUT
// Extracts only the changing columns (where sigma_f[i] == 1) and prepares them for hardware
// Returns the number of columns prepared
function automatic int prepare_compute_unit_inputs(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma_old,
  input logic [255:0] sigma_new,
  input logic [255:0] sigma_f,
  input logic [255:0] sigma_f_inv,
  ref logic [3:0] J_full [0:255][0:255],     // Full J matrix
  output logic [1:0] sigma_r_out [0:255],    // sigma_r for DUT
  output logic sigma_c_out [0:255],          // sigma_c (1-bit) for DUT
  output logic [3:0] j_cols_out [0:255][0:255], // Extracted J columns for DUT
  output int column_indices [0:255]          // Original column indices
);
  logic [1:0] sigma_r_full [0:255];
  logic [1:0] sigma_c_full [0:255];
  int num_changing_cols;
  
  // Generate sigma_r and sigma_c using existing functions
  generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r_full);
  generate_sigma_c(VECTOR_SIZE, sigma_f, sigma_new, sigma_c_full);
  
  // Copy sigma_r directly (same for all columns)
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_r_out[i] = sigma_r_full[i];
  end
  
  // Extract only changing columns (where sigma_c != 00)
  num_changing_cols = 0;
  for (int col = 0; col < VECTOR_SIZE; col++) begin
    if (sigma_c_full[col] != 2'b00) begin
      // Store original column index
      column_indices[num_changing_cols] = col;
      
      // Convert 2-bit sigma_c to 1-bit: 01→1 (positive), 10→0 (negative)
      sigma_c_out[num_changing_cols] = (sigma_c_full[col] == 2'b01) ? 1'b1 : 1'b0;
      
      // Extract this column from J matrix
      for (int row = 0; row < VECTOR_SIZE; row++) begin
        j_cols_out[num_changing_cols][row] = J_full[col][row];
      end
      
      num_changing_cols++;
    end
  end
  
  // Zero out unused entries
  for (int i = num_changing_cols; i < 256; i++) begin
    sigma_c_out[i] = 1'b0;
    column_indices[i] = -1;
    for (int row = 0; row < 256; row++) begin
      j_cols_out[i][row] = '0;
    end
  end
  
  return num_changing_cols;
endfunction

// Compute full energy for a given sigma vector using column-wise accumulation.
// sigma_bits encodes spins: 01 → +1, 10 → -1. No pruning; includes all interactions.
function automatic longint signed energy_from_columns_full(
  input int COL_PER_CC,
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [1:0] sigma_bits [0:255],
  ref logic [3:0] J [0:255][0:255],
  output int active_computations
);
  longint signed total_energy;
  longint signed column_contribution;
  int signed sigma_r_val, sigma_c_val;
  int signed j_val;
  
  total_energy = 0;
  active_computations = 0;
  
  // Process each column, all rows
  for (int col = 0; col < COL_PER_CC; col++) begin
    column_contribution = 0;
    sigma_c_val = (sigma_bits[col] == 2'b01) ? 1 : -1;
    
    for (int row = 0; row < VECTOR_SIZE; row++) begin
      sigma_r_val = (sigma_bits[row] == 2'b01) ? 1 : -1;
      j_val = int'(J[col][row]);
      column_contribution += sigma_r_val * j_val;
      active_computations++;
    end
    
    total_energy += sigma_c_val * column_contribution;
  end
  
  return total_energy;
endfunction

// Verify iterative column processing matches full Hamiltonian energy difference
// Uses verify_energy_from_columns (optimized hardware model)
// Compares with calculate_energy_difference using full J matrix
function automatic bit verify_iterative_vs_hamiltonian(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma_old,
  input logic [255:0] sigma_new,
  input logic [255:0] sigma_f,
  input logic [255:0] sigma_f_inv,
  ref logic [3:0] J_square [0:255][0:255],  // Full square J matrix, fixed size
  output longint iterative_result,
  output longint hamiltonian_result,
  output int columns_processed
);
  logic [1:0] sigma_bits_old [0:255];
  logic [1:0] sigma_bits_new [0:255];
  int active_computations_new;
  int active_computations_old;
  longint signed energy_new_cols;
  longint signed energy_old_cols;
  
  // Build 2-bit spin encodings for old and new sigma: 1 -> 01 (+1), 0 -> 10 (-1)
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_bits_old[i] = sigma_old[i] ? 2'b01 : 2'b10;
    sigma_bits_new[i] = sigma_new[i] ? 2'b01 : 2'b10;
  end
  
  // Column-wise energies for new and old states
  energy_new_cols = energy_from_columns_full(
    VECTOR_SIZE, VECTOR_SIZE, DATA_WIDTH,
    sigma_bits_new,
    J_square,
    active_computations_new
  );
  energy_old_cols = energy_from_columns_full(
    VECTOR_SIZE, VECTOR_SIZE, DATA_WIDTH,
    sigma_bits_old,
    J_square,
    active_computations_old
  );
  iterative_result = energy_new_cols - energy_old_cols;
  
  // Calculate full Hamiltonian energy difference for reference
  hamiltonian_result = calculate_energy_difference(
    VECTOR_SIZE,
    DATA_WIDTH,
    sigma_old,
    sigma_new,
    J_square
  );
  
  columns_processed = VECTOR_SIZE;
  
  // Compare results
  
  // Compare results
  $display("\n=== Verification Results ===");
  $display("Iterative (hardware model): %0d", iterative_result);
  $display("Hamiltonian (full matrix):  %0d", hamiltonian_result);
  $display("Columns processed: %0d/%0d", columns_processed, VECTOR_SIZE);
  $display("Active computations (new/old): %0d / %0d", active_computations_new, active_computations_old);
  $display("Match: %s", (iterative_result == hamiltonian_result) ? "PASS ✓" : "FAIL ✗");
  
  return (iterative_result == hamiltonian_result);
endfunction

// ========== Control Tasks ==========

// Task: Feed compute_unit with full J matrix, automatically handles 4 columns per cycle
// Takes full J matrix and sigma vectors, packages columns properly with sync
task automatic apply_compute_inputs(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma_old,
  input logic [255:0] sigma_new,
  ref logic [3:0] J_full [0:255][0:255],
  ref logic sigma_c_out [0:3],
  ref logic [1:0] sigma_r_out [0:255],
  ref logic [3:0] j_cols_out [0:3][0:255],
  ref logic [3:0] valid_out,
  ref logic [3:0] final_flag_out,
  ref logic clk,
  output int total_cols_sent
);
  logic [255:0] sigma_f, sigma_f_inv;
  logic [1:0] sigma_c_2bit [0:255];
  logic [1:0] sigma_r_2bit [0:255];
  int flipped_cols[256];
  int num_flipped;
  int num_cycles;
  int cols_this_cycle;
  int col_idx;
  longint signed accumulated_sum;
  longint signed cycle_contributions[4];
  
  // Generate control signals
  generate_sigma_f(sigma_old, sigma_new, sigma_f, sigma_f_inv);
  generate_sigma_c(VECTOR_SIZE, sigma_f, sigma_new, sigma_c_2bit);
  generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r_2bit);
  
  // Copy sigma_r to output (same for all cycles)
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_r_out[i] = sigma_r_2bit[i];
  end
  
  // Identify flipped columns
  num_flipped = 0;
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    if (sigma_c_2bit[i] != 2'b00) begin
      flipped_cols[num_flipped] = i;
      num_flipped++;
    end
  end
  
  // Calculate number of cycles needed
  num_cycles = (num_flipped + 3) / 4; // Ceiling division for 4 columns per cycle
  total_cols_sent = 0;
  accumulated_sum = 0;
  
  $display("  Flipped columns: %0d, Will send in %0d cycles", num_flipped, num_cycles);
  
  // Send columns in groups of 4
  for (int cycle = 0; cycle < num_cycles; cycle++) begin
      valid_out = '0;
  final_flag_out = '0;
    cols_this_cycle = ((num_flipped - total_cols_sent) >= 4) ? 4 : (num_flipped - total_cols_sent);
    
   // $display("\n  Cycle %0d: Sending %0d columns", cycle, cols_this_cycle);
    
    // Initialize cycle contributions
    for (int i = 0; i < 4; i++) begin
      cycle_contributions[i] = 0;
    end
    
    // Load 4 slots
    for (int slot = 0; slot < 4; slot++) begin
      col_idx = total_cols_sent + slot;
      
      if (slot < cols_this_cycle) begin
        int actual_col = flipped_cols[col_idx];
        longint signed dot_product;
        int signed sigma_r_val, j_val;
        
        // Load J column
        for (int row = 0; row < VECTOR_SIZE; row++) begin
          j_cols_out[slot][row] = J_full[actual_col][row];
        end
        
        // Calculate expected dot product for this column
        dot_product = 0;
        //$display("    Column %0d J elements where sigma_r != 0:", actual_col);
        for (int row = 0; row < VECTOR_SIZE; row++) begin
          // Decode sigma_r
          case (sigma_r_2bit[row])
            2'b00: sigma_r_val = 0;
            2'b01: sigma_r_val = 1;
            2'b10: sigma_r_val = -1;
            default: sigma_r_val = 0;
          endcase
          
          j_val = $unsigned(J_full[actual_col][row]);
          
          // Display non-zero contributions
          
          
          dot_product += sigma_r_val * j_val;
        end
        
        // Set sigma_c: convert 2-bit to 1-bit (01→1, 10→0)
        // sigma_c_2bit: 01 = +1 (positive spin) → sigma_c=1 (select +dot_product)
        // sigma_c_2bit: 10 = -1 (negative spin) → sigma_c=0 (select -dot_product)
        sigma_c_out[slot] = (sigma_c_2bit[actual_col] == 2'b01) ? 1'b1 : 1'b0;
        //$display("\n  sigma_c_2bit %0b:", sigma_c_2bit[actual_col]);
        // Store contribution for this slot (with sigma_c sign applied)
        cycle_contributions[slot] = sigma_c_out[slot] ? dot_product : -dot_product;
        
        // Mark valid
        valid_out[slot] = 1'b1;
        
        // Set final flag on last column of last cycle
        if (cycle == num_cycles - 1 && slot == cols_this_cycle - 1) begin
          final_flag_out[slot] = 1'b1;
          //$display("    Slot %0d: Column %0d, sigma_c=%b, dot_product=%0d, signed=%0d, valid=1, FINAL",
          //         slot, actual_col, sigma_c_out[slot], dot_product, cycle_contributions[slot]);
        end else begin
          final_flag_out[slot] = 1'b0;
          //$display("    Slot %0d: Column %0d, sigma_c=%b, dot_product=%0d, signed=%0d, valid=1", 
          //         slot, actual_col, sigma_c_out[slot], dot_product, cycle_contributions[slot]);
        end
      end else begin
        // Empty slot
        valid_out[slot] = 1'b0;
        final_flag_out[slot] = 1'b0;
        sigma_c_out[slot] = 1'b0;
        //$display("    Slot %0d: (empty), valid=0", slot);
      end
    end
    
    // Apply inputs on clock edge
    @(posedge clk);
    
    // Accumulate this cycle's contributions
    for (int slot = 0; slot < cols_this_cycle; slot++) begin
      accumulated_sum += cycle_contributions[slot];
    end
    
    //$display("  Inputs applied, total sent: %0d", total_cols_sent + cols_this_cycle);
    //$display("  Cycle %0d sum: %0d (slots: %0d + %0d + %0d + %0d)", 
    //         cycle, 
    //         cycle_contributions[0] + cycle_contributions[1] + cycle_contributions[2] + cycle_contributions[3],
    //         cycle_contributions[0], cycle_contributions[1], 
    //         cycle_contributions[2], cycle_contributions[3]);
    //$display("  *** Accumulated sum after cycle %0d: %0d ***\n", cycle, accumulated_sum);
    
    total_cols_sent += cols_this_cycle;
  end
  // Deassert signals after sending
  valid_out = '0;
  final_flag_out = '0;
  sigma_c_out[0] = '0;
  sigma_c_out[1] = '0;
  sigma_c_out[2] = '0;
  sigma_c_out[3] = '0;
  
endtask

// Task: Clear the accumulator
task automatic clear_accumulator(
  ref logic clear_signal,
  ref logic clk
);
  @(posedge clk);
  clear_signal = 1'b1;
  @(posedge clk);
  clear_signal = 1'b0;
  @(posedge clk);
endtask

// Task: Wait for final flag and capture output
// Returns the accumulator output when final_flag goes high
task automatic wait_and_capture_output(
  ref logic final_flag,
  input int ACCUM_WIDTH,
  ref logic signed [63:0] accum_out,  // Fixed size for max width
  output logic signed [63:0] captured_value,
  ref logic clk,
  input int timeout_cycles
);
  int cycle_count;
  cycle_count = 0;
  
  while (!final_flag && cycle_count < timeout_cycles) begin
    @(posedge clk);
    cycle_count++;
  end
  
  if (cycle_count >= timeout_cycles) begin
    $error("Timeout waiting for final_flag_o");
    captured_value = 'x;
  end else begin
    // Capture output when flag is high
    captured_value = accum_out;
    $display("Captured accum_out = %0d at cycle %0d", captured_value, cycle_count);
  end
endtask

// Task: Reset the DUT
task automatic reset_dut(
  ref logic rst_n,
  ref logic clk,
  input int reset_cycles
);
  rst_n = 1'b0;
  repeat(reset_cycles) @(posedge clk);
  rst_n = 1'b1;
  @(posedge clk);
endtask

// Task: Prepare and feed inputs to compute_unit iteratively
// Processes only changed columns (where sigma_c != 00)
task automatic feed_compute_unit_inputs(
  input int VECTOR_SIZE,
  input int DATA_WIDTH,
  input logic [255:0] sigma_old,
  input logic [255:0] sigma_new,
  ref logic [3:0] J_matrix [0:255][0:255],
  ref logic sigma_c_out,
  ref logic [1:0] sigma_r_out [0:256-1],
  ref logic [4-1:0] j_col_out [0:256-1],
  ref logic valid_out,
  ref logic final_flag_out,
  ref logic clk,
  output int columns_sent,
  output longint signed expected_output
);
  logic [255:0] sigma_f, sigma_f_inv;
  logic [1:0] sigma_c [0:255];
  logic [1:0] sigma_r [0:255];
  int total_changed_columns;
  int col_index;
  longint signed column_sum;
  int signed sigma_r_val, j_val;
  
  // Generate sigma_f and sigma_f_inv
  generate_sigma_f(sigma_old, sigma_new, sigma_f, sigma_f_inv);
  
  // Generate sigma_c and sigma_r
  generate_sigma_c(VECTOR_SIZE, sigma_f, sigma_new, sigma_c);
  generate_sigma_r(VECTOR_SIZE, sigma_f_inv, sigma_new, sigma_r);
  
  // Copy sigma_r to output (same for all columns)
  for (int i = 0; i < VECTOR_SIZE; i++) begin
    sigma_r_out[i] = sigma_r[i];
  end
  
  // Count total changed columns
  total_changed_columns = 0;
  for (int col = 0; col < VECTOR_SIZE; col++) begin
    if (sigma_c[col] != 2'b00) begin
      total_changed_columns++;
    end
  end
  
  $display("Total columns to process: %0d", total_changed_columns);
  
  // Iterate through all columns, send only changed ones
  columns_sent = 0;
  col_index = 0;
  expected_output = 0;
  
  for (int col = 0; col < VECTOR_SIZE; col++) begin
    if (sigma_c[col] != 2'b00) begin
      // Extract this column from J matrix
      for (int row = 0; row < VECTOR_SIZE; row++) begin
        j_col_out[row] = J_matrix[col][row];
      end
      
      // Convert 2-bit sigma_c to 1-bit: 01→1 (positive), 10→0 (negative)
      sigma_c_out = (sigma_c[col] == 2'b01) ? 1'b1 : 1'b0;
      
      // Calculate expected contribution for this column
      column_sum = 0;
      for (int row = 0; row < VECTOR_SIZE; row++) begin
        // Decode sigma_r
        case (sigma_r[row])
          2'b00: sigma_r_val = 0;
          2'b01: sigma_r_val = 1;
          2'b10: sigma_r_val = -1;
          default: sigma_r_val = 0;
        endcase
        
        j_val = $unsigned(J_matrix[col][row]);
        column_sum += sigma_r_val * j_val;
      end
      
      // Apply sigma_c sign
      if (sigma_c_out) begin
        expected_output += column_sum;
      end else begin
        expected_output += (-column_sum);
      end
      
      // Set valid signal
      valid_out = 1'b1;
      
      // Set final flag on last column
      columns_sent++;
      if (columns_sent == total_changed_columns) begin
        final_flag_out = 1'b1;
      end else begin
        final_flag_out = 1'b0;
      end
      
      // Display info
      $display("Cycle %0d: Sending column %0d, sigma_c=%b, contribution=%0d, accumulated=%0d, final=%b", 
               col_index, col, sigma_c[col], (sigma_c_out ? column_sum : -column_sum), expected_output, final_flag_out);
      
      // Wait for clock edge
      @(posedge clk);
      
      col_index++;
    end
  end
  
  // Deassert valid after all columns sent
  // Keep final_flag asserted so DUT can process and respond
  valid_out = 1'b0;
  
endtask
