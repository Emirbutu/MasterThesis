module DotProductTree_array #(
  parameter bit  PIPED             = 1'b0,
  parameter int  VECTOR_SIZE       = 256,
  parameter int  J_ELEMENT_WIDTH   = 4,
  parameter int  LEVELS            = $clog2(VECTOR_SIZE),
  parameter logic [LEVELS-1:0] PIPE_STAGE_MASK = '0,
  parameter bit REG_FINAL         = 1'b1,
  parameter int  INT_RESULT_WIDTH  = (J_ELEMENT_WIDTH + 1) + $clog2(VECTOR_SIZE),
  parameter int  LANES             = 4
)(
  input  logic                                       clk,
  input  logic                                       rst_n,
  input  logic [VECTOR_SIZE-1:0]                     sigma,      // shared across lanes
  input  logic [J_ELEMENT_WIDTH-1:0]                 J_cols [LANES][0:VECTOR_SIZE-1], // per-lane column vectors
  input  logic                                       start,      // shared start/valid
  output logic signed [INT_RESULT_WIDTH-1:0]         dot_outs [LANES],
  output logic                                       start_outs [LANES]
);

  genvar l;
  generate
    for (l = 0; l < LANES; l++) begin : G_LANES
      DotProductTree #(
        .REG_FINAL         (REG_FINAL),
        .PIPED            (PIPED),
        .VECTOR_SIZE      (VECTOR_SIZE),
        .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH),
        .LEVELS           (LEVELS),
        .PIPE_STAGE_MASK  (PIPE_STAGE_MASK),
        .INT_RESULT_WIDTH (INT_RESULT_WIDTH)
      ) u_dpt (
        .clk       (clk),
        .rst_n     (rst_n),
        .sigma     (sigma),
        .J_col     (J_cols[l]),
        .start     (start),
        .dot_out   (dot_outs[l]),
        .start_out (start_outs[l])
      );
    end
  endgenerate

endmodule