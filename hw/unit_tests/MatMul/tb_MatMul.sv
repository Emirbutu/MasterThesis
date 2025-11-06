`timescale 1ns/1ps

module tb_MatMul;

  // --- Match DUT params ---
  parameter int MEM_BANDWIDTH    = 4096;
  parameter int VECTOR_SIZE      = 256;
  parameter int J_ELEMENT_WIDTH  = 4;
  parameter int J_COLS_PER_READ  = MEM_BANDWIDTH / (VECTOR_SIZE * J_ELEMENT_WIDTH); // = 4
  parameter int J_COLS_PER_CLK   = J_COLS_PER_READ;
  parameter int NUM_J_CHUNKS     = VECTOR_SIZE / J_COLS_PER_READ;                   // = 64
  parameter int INT_RESULT_WIDTH = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH + 1;       // +1 headroom
  parameter int ENERGY_WIDTH     = J_ELEMENT_WIDTH + 2*$clog2(VECTOR_SIZE) + 1;     // = 21
  parameter int ACC_WIDTH = INT_RESULT_WIDTH + $clog2(J_COLS_PER_CLK) + 1; // +1 for sign
  // --- I/O ---
  logic clk, rst_n, start;
  logic [VECTOR_SIZE-1:0] sigma;        // 1=add, 0=sub
  logic [VECTOR_SIZE-1:0] sigma_dut;    // to DUT
  logic [J_ELEMENT_WIDTH-1:0] J_Matrix_chunk [0:VECTOR_SIZE-1][0:J_COLS_PER_READ-1];
  logic [ENERGY_WIDTH-1:0]    Energy_previous;

  assign sigma_dut = sigma;  // keep semantics aligned with golden

  // --- DUT ---
  MatMul #(
    .MEM_BANDWIDTH   (MEM_BANDWIDTH),
    .VECTOR_SIZE     (VECTOR_SIZE),
    .J_ELEMENT_WIDTH (J_ELEMENT_WIDTH)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (start),
    .sigma          (sigma_dut),
    .J_Matrix_chunk (J_Matrix_chunk),
    .Energy_previous(Energy_previous)
  );

  // --- Clock / Reset ---
  always #5 clk = ~clk; // 100 MHz
  initial begin
    clk = 0; rst_n = 0; start = 0;
    sigma = '0;
    Energy_previous = {0,{(ENERGY_WIDTH-1){1'b1}}}; // prevent early stop
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // === Full random J and streaming ===
  logic [J_ELEMENT_WIDTH-1:0] J_full [0:VECTOR_SIZE-1][0:VECTOR_SIZE-1];

  task automatic fill_J_full_random(input int seed);
    int i, j; void'($urandom(seed));
    for (i = 0; i < VECTOR_SIZE; i++)
      for (j = 0; j < VECTOR_SIZE; j++)
        J_full[i][j] = $urandom_range((1<<J_ELEMENT_WIDTH)-1, 0);
  endtask

  integer rr, cc, base_idx;
  always @* begin
    base_idx = dut.j_chunk_counter * J_COLS_PER_READ;
    for (rr = 0; rr < VECTOR_SIZE; rr++)
      for (cc = 0; cc < J_COLS_PER_READ; cc++)
        J_Matrix_chunk[rr][cc] = J_full[rr][base_idx + cc];
  end

  // === Sigma patterns ===
  task automatic set_sigma_all0(); sigma = '0; endtask
  task automatic set_sigma_all1(); sigma = {VECTOR_SIZE{1'b1}}; endtask
  task automatic set_sigma_1010();
    int i; for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = (i % 2 == 0);
  endtask
  task automatic set_sigma_random(input int seed);
    int i; void'($urandom(seed));
    for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = $urandom_range(1,0);
  endtask

  // === Golden for arbitrary unsigned J ===
  function automatic longint signed compute_energy_ref_random(
      input logic [VECTOR_SIZE-1:0] sig,
      input logic [J_ELEMENT_WIDTH-1:0] MAT [0:VECTOR_SIZE-1][0:VECTOR_SIZE-1]
  );
    longint signed energy, dot_acc;
    longint unsigned val;
    int c, r;
    energy = 0;
    for (c = 0; c < VECTOR_SIZE; c++) begin
      dot_acc = 0;
      for (r = 0; r < VECTOR_SIZE; r++) begin
        val = MAT[r][c];
        dot_acc = sig[r] ? (dot_acc + longint'(val)) : (dot_acc - longint'(val));
      end
      energy = sig[c] ? (energy + dot_acc) : (energy - dot_acc);
    end
    return energy;
  endfunction

task automatic display_all_blocksum_and_dot_products();
  // Temporary variable to store the real dot product for each column
  logic signed [ACC_WIDTH-1:0] real_dot_product;  // Real dot product for each column
  int r, c;

  // Loop through each column of J (i.e., for each dot product)
  for (c = 0; c < VECTOR_SIZE; c++) begin
    real_dot_product = 0;
    
    // Calculate the real dot product for the current column (dot product of J[c] * sigma)
    for (r = 0; r < VECTOR_SIZE; r++) begin
      // If sigma[r] is 1, add the corresponding J value, otherwise subtract it
      real_dot_product = real_dot_product + (sigma[r] ? J_full[r][c] : -J_full[r][c]);
    end
    
    // Multiply the result by sigma[c] (for σ^T weighting)
    if (sigma[c]) begin
      real_dot_product = real_dot_product;  // Positive (same as add)
    end else begin
      real_dot_product = -real_dot_product;  // Negative (same as subtract)
    end

    // Now compare it with block_sum for this column
    $display("=== Column %0d ===", c);
   $display("  Real Dot Product = %010b", real_dot_product);  // Real calculated dot product for the current column
  end
endtask

  
  // One random-J run (σ must be set beforehand)
  task automatic run_random_case(input string name, input int seed);
    longint signed exp_full;
    longint signed dut_full;

    fill_J_full_random(seed);
    exp_full = compute_energy_ref_random(sigma, J_full);

    @(posedge clk); start = 1; @(posedge clk); start = 0;

    wait (dut.start_enable);
  while (dut.start_enable) begin
   // $display("  Calculated Dot Product = %010b", dut.debug_dot_c);
   // $display("  Calculated block_sum = %010b", dut.block_sum);  
   // $display("  Calculated Energy_next = %010b", dut.Energy_next);  
    @(posedge clk);  // Wait for DUT to finish processing
  end

    // compare in wide domain (no truncation)
    dut_full = dut.Energy_next; // sign-extend DUT to longint
    if (dut_full === exp_full)
      $display("[PASS] %-16s  DUT=%0d  EXP=%0d", name, dut_full, exp_full);
    else
      $error  ("[FAIL] %-16s  DUT=%0d  EXP=%0d", name, dut_full, exp_full);
  endtask

  // === Stimulus ===
  initial begin
    $display("=== MatMul randomized-J self-check (no truncation) ===");
    @(posedge rst_n); @(posedge clk);
    
   
   set_sigma_all0();    run_random_case("randJ_all0" , 32'hA11A);
   set_sigma_all1();    run_random_case("randJ_all1" , 32'hB22B);
   set_sigma_1010();    run_random_case("randJ_1010" , 32'hC33C);
   for (int i = 0; i < 10000; i++) begin
     set_sigma_random(i);    
     run_random_case($sformatf("randJ_sigmaR_%0d", i), i+32'h1000);
   end    
 



  // display_all_blocksum_and_dot_products();
  //display_all_blocksum_and_dot_products();
  //  $display("==== Debug Info ====");
  //  $display("Sigma: %b", sigma);
  // $display("J Matrix (first few rows):");
  //  for (int i = 0; i < 15; i++)  // Display first 5 rows (or customize)
  //   $display("J[%0d][%0d] = %0d", i, 0, J_full[i][0]);  // Display column 0
    $display("=== Done ===");
    $finish;
  end

  // === VCD ===
  initial begin
    $dumpfile("MatMul_tb.vcd");
    $dumpvars(0, tb_MatMul);
  end

endmodule
