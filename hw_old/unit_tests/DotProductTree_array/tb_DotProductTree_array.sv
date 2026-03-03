`timescale 1ns/1ps

module tb_DotProductTree_array;

  // Config
  localparam bit  PIPED            = 1'b1;
  localparam int  VECTOR_SIZE      = 256;
  localparam int  J_ELEMENT_WIDTH  = 4;
  localparam int  LEVELS           = $clog2(VECTOR_SIZE);
  localparam logic [LEVELS-1:0] PIPE_STAGE_MASK = {LEVELS{1'b1}}; // register every stage
  localparam int  INT_RESULT_WIDTH = (J_ELEMENT_WIDTH + 1) + $clog2(VECTOR_SIZE);
  localparam int  LANES            = 256;

  // DUT I/O
  logic clk, rst_n;
  logic [VECTOR_SIZE-1:0] sigma;
  logic [J_ELEMENT_WIDTH-1:0] J_cols [LANES][0:VECTOR_SIZE-1];
  logic start;
  logic signed [INT_RESULT_WIDTH-1:0] dot_outs [LANES];
  logic start_outs [LANES];

  // Clock
  initial clk = 0;
  always #5 clk = ~clk;

  // Reset
  task automatic do_reset();
    rst_n = 0;
    start = 0;
    sigma = '0;
    for (int l = 0; l < LANES; l++)
      for (int k = 0; k < VECTOR_SIZE; k++)
        J_cols[l][k] = '0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
  endtask

  // Deterministic vectors
  task automatic load_vectors_basic();
    // sigma: 1010...
    for (int k = 0; k < VECTOR_SIZE; k++) begin
      sigma[k] = (k % 2);
    end
    // Each lane gets a slightly different column
    for (int l = 0; l < LANES; l++) begin
      for (int k = 0; k < VECTOR_SIZE; k++) begin
        J_cols[l][k] = (k + 1 + l) & ((1<<J_ELEMENT_WIDTH)-1);
      end
    end
  endtask

  // Random vectors
  task automatic load_vectors_random();
    for (int k = 0; k < VECTOR_SIZE; k++)
      sigma[k] = $urandom_range(0,1);
    for (int l = 0; l < LANES; l++)
      for (int k = 0; k < VECTOR_SIZE; k++)
        J_cols[l][k] = $urandom_range(0, (1<<J_ELEMENT_WIDTH)-1);
  endtask

  // Reference per-lane
  function automatic integer signed ref_sum
    (input logic [VECTOR_SIZE-1:0] f_sigma,
     input logic [J_ELEMENT_WIDTH-1:0] f_J_col [0:VECTOR_SIZE-1]);
    integer signed acc;
    integer unsigned mag;
    acc = 0;
    for (int k = 0; k < VECTOR_SIZE; k++) begin
      mag = f_J_col[k];
      acc += (f_sigma[k] ? integer'(mag) : -integer'(mag));
    end
    return acc;
  endfunction

  // Run one case
  task automatic run_one_case(input string name);
    integer signed exp [LANES];
    for (int l = 0; l < LANES; l++)
      exp[l] = ref_sum(sigma, J_cols[l]);

    @(posedge clk);
    start <= 1'b1;
    @(posedge clk);
    start <= 1'b0;

    // Wait for valid (all lanes should align)
    wait (start_outs[0] === 1'b1);

    // Check all lanes
    for (int l = 0; l < LANES; l++) begin
      if ($signed(dot_outs[l]) !== exp[l]) begin
        $error("[%s] Lane %0d MISMATCH: got %0d, exp %0d",
               name, l, $signed(dot_outs[l]), exp[l]);
      end else begin
        $display("[%s] Lane %0d PASS: %0d", name, l, $signed(dot_outs[l]));
      end
    end

    @(posedge clk);
  endtask

  // DUT: Array of parallel dot products
  DotProductTreeArray #(
    .PIPED            (PIPED),
    .VECTOR_SIZE      (VECTOR_SIZE),
    .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH),
    .LEVELS           (LEVELS),
    .PIPE_STAGE_MASK  (PIPE_STAGE_MASK),
    .INT_RESULT_WIDTH (INT_RESULT_WIDTH),
    .LANES            (LANES)
  ) dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .sigma      (sigma),
    .J_cols     (J_cols),
    .start      (start),
    .dot_outs   (dot_outs),
    .start_outs (start_outs)
  );

  // Sequence
  initial begin
    do_reset();

    load_vectors_basic();
    run_one_case("basic");

    for (int t = 0; t < 5; t++) begin
      load_vectors_random();
      run_one_case($sformatf("rand%0d", t));
    end

    $display("All tests done.");
    $finish;
  end

endmodule