`include "include/registers.svh"

// DotProductTree_comb.sv
// Pure combinational dot product with 1-bit sigma selecting ±J.
// Uses adder_tree_layer; no clocks, no flops.

module DotProductTree #(
  parameter bit PIPED             = 0,
  // Bit mask selecting which stage boundaries get registered when PIPED==1.
  // Bit 0 -> between level0 and layer0, bit (i+1) -> between layer i and layer i+1
  parameter int VECTOR_SIZE       = 256, // must be >= 2
  parameter int J_ELEMENT_WIDTH   = 4,
  parameter int LEVELS            = $clog2(VECTOR_SIZE),
  parameter logic [LEVELS-1:0] PIPE_STAGE_MASK = '0,
  // term width = Jw+1, final width = (Jw+1) + ceil(log2(VECTOR_SIZE))
  parameter int INT_RESULT_WIDTH  = (J_ELEMENT_WIDTH + 1) + $clog2(VECTOR_SIZE)
)(
  input  logic                                         clk,
  input  logic                                         rst_n,
  input  logic [VECTOR_SIZE-1:0]                     sigma,      // 1 -> +J, 0 -> -J
  input  logic [J_ELEMENT_WIDTH-1:0]                 J_col [0:VECTOR_SIZE-1],
  input start,
  output logic signed [INT_RESULT_WIDTH-1:0]         dot_out,
  output logic                                        start_out 
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
  if(PIPED == 0) begin : GEN_COMB_TREE
  assign start_out = start;  
    for (i = 0; i < LEVELS; i++) begin : LAYER
      localparam int W_IN         = W0 + i;
      localparam int COUNT_IN    = (VECTOR_SIZE >> i);
      localparam int COUNT_OUT = (VECTOR_SIZE >> (i+1));
      localparam int W_OUT         = W_IN + 1;

      logic [W_IN-1:0] in_i [0:COUNT_IN-1];
      logic [W_OUT-1:0] out_i[0:COUNT_OUT-1];

      // Bind inputs for the first layer
      if (i == 0) begin : SRC0
        for (genvar m = 0; m < COUNT_IN; m++) begin : BIND0
          assign in_i[m] = level0[m];
        end
      end else begin : SRCN
        // Take outputs from previous layer directly if not first layer
        for (genvar m = 0; m < COUNT_IN; m++) begin : BINDN
          assign in_i[m] = LAYER[i-1].out_i[m];
        end
      end

        adder_tree_layer #(
          .INPUTS_AMOUNT (COUNT_IN),
          .DATAW         (W_IN)
        ) u_layer (
          .inputs  ( in_i  ),
          .outputs ( out_i )
        );
      end
    end else begin : GEN_PIPE_TREE
      // Stage 0 (between level0 and layer0)
      logic [W0-1:0] stage0_data [0:VECTOR_SIZE-1];
      logic start_stage [0:LEVELS]; 
      assign start_stage[0] = start;
      logic start_stage0_reg;
      if (PIPE_STAGE_MASK[0]) begin : GEN_START_STAGE0_REG
        `FF(start_stage0_reg, start_stage[0], '0, clk, rst_n)
        assign start_stage[1] = start_stage0_reg;
      end else begin : GEN_START_STAGE0_WIRE
        assign start_stage[1] = start_stage[0];
      end

      if (PIPE_STAGE_MASK[0]) begin : GEN_STAGE0_REG
        for (genvar m = 0; m < VECTOR_SIZE; m++) begin : REG
          `FF(stage0_data[m], level0[m], '0, clk, rst_n)
        end
      end else begin : GEN_STAGE0_WIRE
        for (genvar m = 0; m < VECTOR_SIZE; m++) begin : WIRE
          assign stage0_data[m] = level0[m];
        end
      end

      for (i = 0; i < LEVELS; i++) begin : LAYER_PIPE
        localparam int W_IN      = W0 + i;
        localparam int COUNT_IN  = (VECTOR_SIZE >> i);
        localparam int COUNT_OUT = (VECTOR_SIZE >> (i+1));
        localparam int W_OUT     = W_IN + 1;

        logic [W_IN-1:0] in_i      [0:COUNT_IN-1];
        logic [W_OUT-1:0] out_i     [0:COUNT_OUT-1];
        logic [W_OUT-1:0] stage_out [0:COUNT_OUT-1];

        if (i == 0) begin : SRC_STAGE0
          for (genvar m = 0; m < COUNT_IN; m++) begin : BIND_STAGE0
            assign in_i[m] = stage0_data[m];
          end
        end else begin : SRC_STAGE
          for (genvar m = 0; m < COUNT_IN; m++) begin : BIND_STAGE
            assign in_i[m] = LAYER_PIPE[i-1].stage_out[m];
          end
        end

        adder_tree_layer #(
          .INPUTS_AMOUNT (COUNT_IN),
          .DATAW         (W_IN)
        ) u_layer_pipe (
          .inputs  ( in_i  ),
          .outputs ( out_i )
        );
        logic start_stage_reg;
        if ((i+1) < LEVELS ? PIPE_STAGE_MASK[i+1] : 1'b0) begin : REG_STAGE
          for (genvar n = 0; n < COUNT_OUT; n++) begin : REG
            `FF(stage_out[n], out_i[n], '0, clk, rst_n)
          end
          `FF(start_stage_reg, start_stage[i+1], '0, clk, rst_n)
          assign start_stage[i+2] = start_stage_reg;
        end else begin : WIRE_STAGE
          for (genvar n = 0; n < COUNT_OUT; n++) begin : WIRE
            assign stage_out[n] = out_i[n];
          end
          assign start_stage[i+2] = start_stage[i+1];
        end
      end
      assign start_out = start_stage[LEVELS];
    end
  endgenerate

  generate
    if (PIPED == 0) begin : GEN_OUT_COMB
      assign dot_out = $signed( GEN_COMB_TREE.LAYER[LEVELS-1].out_i[0] );
    end else begin : GEN_OUT_PIPE
      assign dot_out = $signed( GEN_PIPE_TREE.LAYER_PIPE[LEVELS-1].stage_out[0] );
    end
  endgenerate

endmodule
