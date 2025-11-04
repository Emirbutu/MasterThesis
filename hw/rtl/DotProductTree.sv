// DotProductTree_comb.sv
// Pure combinational dot product with 1-bit sigma selecting ±J.
// Uses adder_tree_layer; no clocks, no flops.

module DotProductTree #(
  parameter int VECTOR_SIZE       = 256, // must be >= 2
  parameter int J_ELEMENT_WIDTH   = 4,
  // term width = Jw+1, final width = (Jw+1) + ceil(log2(VECTOR_SIZE))
  parameter int INT_RESULT_WIDTH  = (J_ELEMENT_WIDTH + 1) + $clog2(VECTOR_SIZE)
)(
  input  logic [VECTOR_SIZE-1:0]                     sigma,      // 1 -> +J, 0 -> -J
  input  logic [J_ELEMENT_WIDTH-1:0]                 J_col [0:VECTOR_SIZE-1],
  output logic signed [INT_RESULT_WIDTH-1:0]         dot_out
);
/*
  // -------- utilities --------
  function automatic int unsigned next_pow2 (input int unsigned n);
    int unsigned p;
    if (n <= 1) return 1;
    p = 1;
    while (p < n) p <<= 1;
    return p;
  endfunction
*/
 // localparam int PADDED_N = next_pow2(VECTOR_SIZE);
  localparam int LEVELS   = $clog2(VECTOR_SIZE);              // >= 1 (we assume VECTOR_SIZE >= 2)
  localparam int W0       = J_ELEMENT_WIDTH + 1;           // width of ±J terms
  localparam int W_FINAL  = W0 + LEVELS;                   // exact final width

  // Optional sim checks
  initial begin
    if (VECTOR_SIZE < 2)
      $fatal(1, "DotProductTree_comb expects VECTOR_SIZE >= 2.");
    if (INT_RESULT_WIDTH < W_FINAL)
      $error("INT_RESULT_WIDTH(%0d) < required(%0d).", INT_RESULT_WIDTH, W_FINAL);
  end

  // -------- level 0: build ±J terms and pad to power-of-two --------
  logic [W0-1:0] level0 [0:VECTOR_SIZE-1];

  genvar k;
  generate
    for (k = 0; k < VECTOR_SIZE; k++) begin : GEN_TERMS
      logic signed [W0-1:0] Jext;
      assign Jext       = { {(W0-J_ELEMENT_WIDTH){1'b0}}, J_col[k] }; // zero-extend magnitude
      assign level0[k]  = (sigma[k]) ? Jext : -Jext;                  // 1 -> +J, 0 -> -J
    end
  endgenerate

  // -------- adder tree (combinational), +1 bit per layer --------
  // Each layer i:
  //   inputs:  COUNT_I   = PADDED_N >> i, width WI = W0 + i
  //   outputs: COUNT_NEXT= PADDED_N >> (i+1), width WO = WI + 1
  genvar i;
  generate
    for (i = 0; i < LEVELS; i++) begin : LAYER
      localparam int WI         = W0 + i;
      localparam int COUNT_IN    = (VECTOR_SIZE >> i);
      localparam int COUNT_OUT = (VECTOR_SIZE >> (i+1));
      localparam int WO         = WI + 1;

      logic [WI-1:0] in_i [0:COUNT_IN-1];
      logic [WO-1:0] out_i[0:COUNT_OUT-1];

      // Bind inputs for this layer
      if (i == 0) begin : SRC0
        for (genvar m = 0; m < COUNT_IN; m++) begin : BIND0
          assign in_i[m] = level0[m];
        end
      end else begin : SRCN
        // Take outputs from previous layer directly
        for (genvar m = 0; m < COUNT_IN; m++) begin : BINDN
          assign in_i[m] = LAYER[i-1].out_i[m];
        end
      end

      // One reduction step
      adder_tree_layer #(
        .INPUTS_AMOUNT (COUNT_IN),
        .DATAW         (WI)
      ) u_layer (
        .inputs  ( in_i  ),
        .outputs ( out_i )
      );
    end
  endgenerate

  // Final sum is the single element at the last layer’s outputs.
  // Width is W_FINAL; assign to signed output (extends if INT_RESULT_WIDTH > W_FINAL).
  assign dot_out = $signed( LAYER[LEVELS-1].out_i[0] );

endmodule
