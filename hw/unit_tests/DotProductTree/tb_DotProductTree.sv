`timescale 1ns/1ps

module tb_DotProductTree;
 // ---- Parameters (small for readable console; set VECTOR_SIZE=256 later) ----
  localparam int VECTOR_SIZE      = 256;  // 256 when ready
  localparam int J_ELEMENT_WIDTH  = 4;   // UNSIGNED J elements
  localparam int INT_RESULT_WIDTH = J_ELEMENT_WIDTH + $clog2(VECTOR_SIZE) + 1;

  // ---- DUT I/O ----
  logic [VECTOR_SIZE-1:0]                 sigma;          // 1: subtract, 0: add
  logic [J_ELEMENT_WIDTH-1:0]             J_col [0:VECTOR_SIZE-1]; // UNSIGNED
  logic signed [INT_RESULT_WIDTH-1:0]     dut_out;

  // ---- DUT ----
  DotProductTree #(
    .VECTOR_SIZE      (VECTOR_SIZE),
    .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH)
  ) dut (
    .sigma  (sigma),
    .J_col  (J_col),
    .dot_out(dut_out)
  );

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
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]}; // zero-extend
      acc   = acc + b_ext;
    end
    exp = acc;
    if (dut_out===exp) $display("[PASS] all_add   dut=%0d exp=%0d", dut_out, exp);
    else               $error  ("[FAIL] all_add   dut=%0d exp=%0d", dut_out, exp);

    // ---------- Case 2: sigma=0, same J ----------
    sigma = '0;
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
      acc   = acc - b_ext;
    end
    exp = acc;
    if (dut_out===exp) $display("[PASS] all_sub   dut=%0d exp=%0d", dut_out, exp);
    else               $error  ("[FAIL] all_sub   dut=%0d exp=%0d", dut_out, exp);

    // ---------- Case 3: alternating sigma 1010... ----------
    for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = (i % 2);
    #1;
    acc = '0;
    for (i = 0; i < VECTOR_SIZE; i++) begin
      b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
      acc   = sigma[i] ? (acc + b_ext) : (acc - b_ext);
    end
    exp = acc;
    if (dut_out===exp) $display("[PASS] alt_10    dut=%0d exp=%0d", dut_out, exp);
    else               $error  ("[FAIL] alt_10    dut=%0d exp=%0d", dut_out, exp);

    // ---------- Cases 4+: random mixes ----------
    for (t = 0; t < 50000; t++) begin
      for (i = 0; i < VECTOR_SIZE; i++) J_col[i] = $urandom_range((1<<J_ELEMENT_WIDTH)-1, 0);
      for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = $urandom_range(1, 0);
      #1;
      acc = '0;
      for (i = 0; i < VECTOR_SIZE; i++) begin
        b_ext = {{(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[i]};
        acc   = sigma[i] ? (acc + b_ext) : (acc - b_ext);
      end
      exp = acc;
       if (dut_out===exp) $display("[PASS] rand1    dut=%0d exp=%0d", dut_out, exp);
       else               $error  ("[FAIL] alt_10    dut=%0d exp=%0d", dut_out, exp);
    end

    $display("=== Done. ===");
    $finish;
  end

endmodule
 