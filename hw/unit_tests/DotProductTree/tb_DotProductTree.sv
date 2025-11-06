`timescale 1ns/1ps

module tb_DotProductTree;
  // ---- Parameters (small for readable console; set VECTOR_SIZE=256 later) ----
  localparam bit PIPED            = 1'b1;
  localparam int VECTOR_SIZE      = 256;  // 256 when ready
  localparam int J_ELEMENT_WIDTH  = 4;   // UNSIGNED J elements
  localparam int LEVELS           = $clog2(VECTOR_SIZE);
  localparam logic [LEVELS:0] PIPE_STAGE_MASK = {1'b1, {LEVELS{1'b1}}};
  localparam int INT_RESULT_WIDTH = J_ELEMENT_WIDTH + $clog2(VECTOR_SIZE) + 1;
  localparam int PIPE_DEPTH       = PIPED ? $countones(PIPE_STAGE_MASK) : 0;
  localparam int PIPE_LATENCY     = (PIPE_DEPTH > 0) ? (PIPE_DEPTH - 1) : 0;

  // ---- DUT I/O ----
  logic [VECTOR_SIZE-1:0]                 sigma;          // 1: subtract, 0: add
  logic [J_ELEMENT_WIDTH-1:0]             J_col [0:VECTOR_SIZE-1]; // UNSIGNED
  logic signed [INT_RESULT_WIDTH-1:0]     dut_out;
  logic clk, rst_n;

  // Expected results queue to align with pipeline latency
  logic signed [INT_RESULT_WIDTH-1:0] exp_q [$];

  // ---- DUT ----
  DotProductTree #(
    .PIPED            (PIPED),
    .PIPE_STAGE_MASK  (PIPE_STAGE_MASK),
    .VECTOR_SIZE      (VECTOR_SIZE),
    .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH)
  ) dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .sigma  (sigma),
    .J_col  (J_col),
    .dot_out(dut_out)
  );
  always #5 clk = ~clk; // 100 MHz
  initial begin
    clk = 0; rst_n = 0;
    sigma = '0;
    for (int i = 0; i < VECTOR_SIZE; i++) J_col[i] = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end
  // ---- Test sequence (no tasks/functions; all locals declared up front) ----
  initial begin
    integer i, t;
    integer SEED;
    logic signed [INT_RESULT_WIDTH-1:0] acc;
    logic signed [INT_RESULT_WIDTH-1:0] b_ext;
    logic signed [INT_RESULT_WIDTH-1:0] exp;

    // seed RNG (separate assignment avoids "implicitly static" warning)
    SEED = 32'hCAFEBABE;
    void'($urandom(SEED));

    $display("=== tb_dot_chain_fix (UNSIGNED J, zero-extend) ===");
    $display("VECTOR_SIZE=%0d  J_ELEMENT_WIDTH=%0d  INT_RESULT_WIDTH=%0d",
             VECTOR_SIZE, J_ELEMENT_WIDTH, INT_RESULT_WIDTH);

    // ---------- Case 1: sigma=1, J = 0..VECTOR_SIZE-1 ----------
    for (i = 0; i < VECTOR_SIZE; i++) J_col[i] = i[J_ELEMENT_WIDTH-1:0];
    sigma = '1;
    @(posedge clk);
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]}; // zero-extend
      acc   = acc + b_ext;
    end
    exp = acc;
    exp_q.push_back(exp);
    if (exp_q.size() > PIPE_LATENCY) begin
      automatic logic signed [INT_RESULT_WIDTH-1:0] exp_now = exp_q.pop_front();
      if (dut_out===exp_now) $display("[PASS] all_add   dut=%0d exp=%0d", dut_out, exp_now);
      else                   $error  ("[FAIL] all_add   dut=%0d exp=%0d", dut_out, exp_now);
    end

    // ---------- Case 2: sigma=0, same J ----------
    sigma = '0;
    @(posedge clk);
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
      acc   = acc - b_ext;
    end
    exp = acc;
    exp_q.push_back(exp);
    if (exp_q.size() > PIPE_LATENCY) begin
      automatic logic signed [INT_RESULT_WIDTH-1:0] exp_now = exp_q.pop_front();
      if (dut_out===exp_now) $display("[PASS] all_sub   dut=%0d exp=%0d", dut_out, exp_now);
      else                   $error  ("[FAIL] all_sub   dut=%0d exp=%0d", dut_out, exp_now);
    end

    // ---------- Case 3: alternating sigma 1010... ----------
    for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = (i % 2);
    @(posedge clk);
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
      acc   = sigma[i] ? (acc + b_ext) : (acc - b_ext);
    end
    exp = acc;
    exp_q.push_back(exp);
    if (exp_q.size() > PIPE_LATENCY) begin
      automatic logic signed [INT_RESULT_WIDTH-1:0] exp_now = exp_q.pop_front();
      if (dut_out===exp_now) $display("[PASS] alt_10    dut=%0d exp=%0d", dut_out, exp_now);
      else                   $error  ("[FAIL] alt_10    dut=%0d exp=%0d", dut_out, exp_now);
    end

    // ---------- Cases 4+: random mixes ----------
    for (t = 0; t < 50000; t++) begin
      for (i = 0; i < VECTOR_SIZE; i++) J_col[i] = $urandom_range((1<<J_ELEMENT_WIDTH)-1, 0);
      for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = $urandom_range(1, 0);
      @(posedge clk);
      #1;
      acc = '0;
      for (i = 0; i < VECTOR_SIZE; i++) begin
        b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
        acc   = sigma[i] ? (acc + b_ext) : (acc - b_ext);
      end
      exp = acc;
      exp_q.push_back(exp);
      if (exp_q.size() > PIPE_LATENCY) begin
        automatic logic signed [INT_RESULT_WIDTH-1:0] exp_now = exp_q.pop_front();
        if (dut_out===exp_now) $display("[PASS] rand1    dut=%0d exp=%0d", dut_out, exp_now);
        else                   $error  ("[FAIL] rand1    dut=%0d exp=%0d", dut_out, exp_now);
      end
    end

    // Flush remaining expected values through the pipeline
    for (t = 0; t <= PIPE_LATENCY; t++) begin
      @(posedge clk);
      #1;
      if (!exp_q.empty()) begin
        automatic logic signed [INT_RESULT_WIDTH-1:0] exp_now = exp_q.pop_front();
        if (dut_out===exp_now) $display("[PASS] flush    dut=%0d exp=%0d", dut_out, exp_now);
        else                   $error  ("[FAIL] flush    dut=%0d exp=%0d", dut_out, exp_now);
      end
    end

    $display("=== Done. ===");
    $finish;
  end

endmodule
 