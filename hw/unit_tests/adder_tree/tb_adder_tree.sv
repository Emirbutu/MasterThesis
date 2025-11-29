`timescale 1ns/1ps

module tb_adder_tree;

  // ========================================================================
  // CONFIGURABLE PARAMETERS - CHANGE THESE TO TEST DIFFERENT CONFIGURATIONS
  // ========================================================================
  localparam int NUM_INPUTS       = 2;        // 1, 2, 4, 8, 16, ...
  localparam int INPUT_WIDTH      = 8;
  localparam bit PIPED            = 1;        // 0 = combinational, 1 = pipelined
  localparam int LEVELS           = (NUM_INPUTS > 1) ? $clog2(NUM_INPUTS) : 0;
  localparam logic [LEVELS:0] PIPE_STAGE_MASK = 2'b11;  // Adjust width based on LEVELS
  
  localparam int NUM_RANDOM_TESTS = 100;
  // ========================================================================

  // Derived parameters
  localparam int OUTPUT_WIDTH = INPUT_WIDTH + LEVELS;
  
  // Calculate expected latency from PIPE_STAGE_MASK
  function automatic int calc_latency();
    int lat;
    lat = 0;
    if (PIPED) begin
      for (int i = 0; i <= LEVELS; i++) begin
        if (PIPE_STAGE_MASK[i]) lat++;
      end
    end
    return lat;
  endfunction
  
  localparam int LATENCY = calc_latency();

  // ========== Clock and Reset ==========
  logic clk;
  logic rst_n;

  initial clk = 0;
  always #5 clk = ~clk;

  // ========== Test counters ==========
  int total_tests;
  int passed_tests;
  int failed_tests;

  // ========== DUT signals ==========
  logic signed [INPUT_WIDTH-1:0]   inputs [0:NUM_INPUTS-1];
  logic                            start;
  logic signed [OUTPUT_WIDTH-1:0]  sum_out;
  logic                            start_out;

  // ========== DUT instantiation ==========
  adder_tree #(
    .PIPED          (PIPED),
    .NUM_INPUTS     (NUM_INPUTS),
    .INPUT_WIDTH    (INPUT_WIDTH),
    .PIPE_STAGE_MASK(PIPE_STAGE_MASK)
  ) dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .inputs   (inputs),
    .start    (start),
    .sum_out  (sum_out),
    .start_out(start_out)
  );

  // ========== Helper functions ==========
  
  // Calculate expected sum
  function automatic logic signed [OUTPUT_WIDTH-1:0] calc_expected();
    logic signed [OUTPUT_WIDTH-1:0] total;
    total = 0;
    for (int i = 0; i < NUM_INPUTS; i++) begin
      total = total + inputs[i];
    end
    return total;
  endfunction

  // Generate random signed value
  function automatic logic signed [INPUT_WIDTH-1:0] random_signed_value();
    logic [INPUT_WIDTH-1:0] val;
    val = $urandom();
    return $signed(val);
  endfunction

  // Format inputs array as string for display
  function automatic string format_inputs();
    string s;
    s = "[";
    for (int i = 0; i < NUM_INPUTS; i++) begin
      if (i > 0) s = {s, ", "};
      $sformat(s, "%s%0d", s, inputs[i]);
    end
    s = {s, "]"};
    return s;
  endfunction

  // ========== Test tasks ==========

  // Combinational test (PIPED = 0)
  task automatic test_combinational(input string test_name);
    logic signed [OUTPUT_WIDTH-1:0] expected;
    string inputs_str;
    
    start = 1;
    #1; // Small delay for combinational logic
    
    expected = calc_expected();
    inputs_str = format_inputs();
    total_tests++;
    
    if (sum_out === expected && start_out === 1'b1) begin
      passed_tests++;
      $display("[COMB] %s PASS: %s -> sum=%0d, start_out=%b", 
               test_name, inputs_str, sum_out, start_out);
    end else begin
      failed_tests++;
      $error("[COMB] %s FAIL: %s -> sum=%0d (exp %0d), start_out=%b (exp 1)", 
             test_name, inputs_str, sum_out, expected, start_out);
    end
    
    start = 0;
    #9;
  endtask

  // Pipelined test (PIPED = 1)
  task automatic test_pipelined(input string test_name);
    logic signed [OUTPUT_WIDTH-1:0] expected;
    logic signed [INPUT_WIDTH-1:0]  saved_inputs [0:NUM_INPUTS-1];
    string inputs_str;
    
    // Save inputs for later comparison
    for (int i = 0; i < NUM_INPUTS; i++) begin
      saved_inputs[i] = inputs[i];
    end
    inputs_str = format_inputs();
    
    // Apply inputs on clock edge
    @(posedge clk);
    start = 1;
    
    @(posedge clk);
    start = 0;
    // Clear inputs to verify pipeline holds data
    for (int i = 0; i < NUM_INPUTS; i++) begin
      inputs[i] = 0;
    end
    
    // Wait for pipeline latency (if latency > 1)
    if (LATENCY > 1) begin
      repeat(LATENCY - 1) @(posedge clk);
    end
    
    // Check after latency
    #1;
    
    // Calculate expected from saved inputs
    expected = 0;
    for (int i = 0; i < NUM_INPUTS; i++) begin
      expected = expected + saved_inputs[i];
    end
    
    total_tests++;
    
    if (sum_out === expected && start_out === 1'b1) begin
      passed_tests++;
      $display("[PIPE lat=%0d] %s PASS: %s -> sum=%0d, start_out=%b", 
               LATENCY, test_name, inputs_str, sum_out, start_out);
    end else begin
      failed_tests++;
      $error("[PIPE lat=%0d] %s FAIL: %s -> sum=%0d (exp %0d), start_out=%b (exp 1)", 
             LATENCY, test_name, inputs_str, sum_out, expected, start_out);
    end
    
    @(posedge clk);
  endtask

  // Generic test wrapper
  task automatic run_test(input string test_name);
    if (PIPED == 0) begin
      test_combinational(test_name);
    end else begin
      test_pipelined(test_name);
    end
  endtask

  // Set all inputs to same value
  task automatic set_all_inputs(input logic signed [INPUT_WIDTH-1:0] val);
    for (int i = 0; i < NUM_INPUTS; i++) begin
      inputs[i] = val;
    end
  endtask

  // Set inputs to sequential values
  task automatic set_sequential_inputs(input logic signed [INPUT_WIDTH-1:0] start_val, input int step);
    for (int i = 0; i < NUM_INPUTS; i++) begin
      inputs[i] = start_val + i * step;
    end
  endtask

  // Set random inputs
  task automatic set_random_inputs();
    for (int i = 0; i < NUM_INPUTS; i++) begin
      inputs[i] = random_signed_value();
    end
  endtask

  // Set alternating positive/negative
  task automatic set_alternating_inputs(
    input logic signed [INPUT_WIDTH-1:0] pos_val,
    input logic signed [INPUT_WIDTH-1:0] neg_val
  );
    for (int i = 0; i < NUM_INPUTS; i++) begin
      inputs[i] = (i % 2 == 0) ? pos_val : neg_val;
    end
  endtask

  // ========== Main test sequence ==========
  initial begin
    int seed;
    
    // Initialize
    total_tests = 0;
    passed_tests = 0;
    failed_tests = 0;
    seed = $urandom();
    
    rst_n = 0;
    start = 0;
    for (int i = 0; i < NUM_INPUTS; i++) inputs[i] = 0;
    
    #20;
    rst_n = 1;
    #10;

    // ========== Print configuration ==========
    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════════════╗");
    $display("║                    ADDER TREE TESTBENCH                              ║");
    $display("╠══════════════════════════════════════════════════════════════════════╣");
    $display("║  Configuration:                                                      ║");
    $display("║    NUM_INPUTS      = %3d                                             ║", NUM_INPUTS);
    $display("║    INPUT_WIDTH     = %3d                                             ║", INPUT_WIDTH);
    $display("║    OUTPUT_WIDTH    = %3d                                             ║", OUTPUT_WIDTH);
    $display("║    LEVELS          = %3d                                             ║", LEVELS);
    $display("║    PIPED           = %3d                                             ║", PIPED);
    $display("║    PIPE_STAGE_MASK = %b                                          ║", PIPE_STAGE_MASK);
    $display("║    LATENCY         = %3d cycles                                      ║", LATENCY);
    $display("║    Random seed     = %0d                                            ║", seed);
    $display("╚══════════════════════════════════════════════════════════════════════╝");
    $display("\n");

    // ========== Edge case tests ==========
    $display("════════════════════════════════════════════════════════════════");
    $display("  EDGE CASE TESTS");
    $display("════════════════════════════════════════════════════════════════");

    // All zeros
    set_all_inputs(0);
    run_test("All zeros");

    // All ones
    set_all_inputs(1);
    run_test("All ones");

    // All minus ones
    set_all_inputs(-1);
    run_test("All minus ones");

    // All max positive
    set_all_inputs(8'sd127);
    run_test("All max positive (127)");

    // All min negative
    set_all_inputs(-8'sd128);
    run_test("All min negative (-128)");

    // Sequential positive
    set_sequential_inputs(8'sd10, 10);
    run_test("Sequential positive (10, 20, 30, ...)");

    // Sequential negative
    set_sequential_inputs(-8'sd10, -10);
    run_test("Sequential negative (-10, -20, -30, ...)");

    // Alternating max/min
    set_alternating_inputs(8'sd127, -8'sd128);
    run_test("Alternating max/min");

    // Alternating that cancels
    set_alternating_inputs(8'sd50, -8'sd50);
    run_test("Alternating cancel (50, -50, ...)");

    // Single large positive, rest zero
    set_all_inputs(0);
    inputs[0] = 8'sd100;
    run_test("Single positive, rest zero");

    // Single large negative, rest zero
    set_all_inputs(0);
    inputs[0] = -8'sd100;
    run_test("Single negative, rest zero");

    // ========== Random tests ==========
    $display("\n════════════════════════════════════════════════════════════════");
    $display("  RANDOM TESTS (%0d iterations)", NUM_RANDOM_TESTS);
    $display("════════════════════════════════════════════════════════════════");

    for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
      string test_name;
      $sformat(test_name, "Random[%0d]", i);
      set_random_inputs();
      run_test(test_name);
    end

    // ========== Summary ==========
    $display("\n");
    $display("╔══════════════════════════════════════════════════════════════════════╗");
    $display("║                         TEST SUMMARY                                 ║");
    $display("╠══════════════════════════════════════════════════════════════════════╣");
    $display("║  Configuration:                                                      ║");
    $display("║    NUM_INPUTS      = %3d                                             ║", NUM_INPUTS);
    $display("║    PIPED           = %3d                                             ║", PIPED);
    $display("║    PIPE_STAGE_MASK = %b                                          ║", PIPE_STAGE_MASK);
    $display("║    LATENCY         = %3d cycles                                      ║", LATENCY);
    $display("╠══════════════════════════════════════════════════════════════════════╣");
    $display("║  Total tests:  %5d                                                  ║", total_tests);
    $display("║  Passed:       %5d                                                  ║", passed_tests);
    $display("║  Failed:       %5d                                                  ║", failed_tests);
    $display("╠══════════════════════════════════════════════════════════════════════╣");
    if (failed_tests == 0) begin
      $display("║  ✓ ALL TESTS PASSED                                                  ║");
    end else begin
      $display("║  ✗ SOME TESTS FAILED                                                 ║");
    end
    $display("╚══════════════════════════════════════════════════════════════════════╝");
    $display("\n");

    $finish;
  end

endmodule