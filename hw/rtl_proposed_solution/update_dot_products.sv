`include "include/registers.svh"

module update_dot_products #(
  parameter int NUM_ROWS_PER_CLK  = 4,
  parameter int VECTOR_SIZE     = 256,
  parameter int DATA_WIDTH      = 4,
  parameter bit PIPED           = 1,
  parameter int LEVELS          = (NUM_ROWS_PER_CLK > 1) ? $clog2(NUM_ROWS_PER_CLK) : 0,
  parameter logic [LEVELS:0] PIPE_STAGE_MASK = '1,
  parameter int ACCUM_WIDTH     = 16
)(
  input  logic clk,
  input  logic rst_n,
  input  logic clear,
  
  input  logic signed [DATA_WIDTH-1:0] j_rows [0:NUM_ROWS_PER_CLK-1][0:VECTOR_SIZE-1],
  input  logic [NUM_ROWS_PER_CLK-1:0] j_rows_valid,
  input  logic [NUM_ROWS_PER_CLK-1:0] sigma_bits,
  
  // Reset values as input - can be driven from testbench or top-level
  input  logic signed [ACCUM_WIDTH-1:0] reset_values [0:VECTOR_SIZE-1],
  
  output logic signed [ACCUM_WIDTH-1:0] accumulated_sums [0:VECTOR_SIZE-1],
  output logic done
);

  localparam int COLUMN_SUM_WIDTH = DATA_WIDTH + 1 + LEVELS + 1;
  
  // Compile-time check
  initial begin
    if (ACCUM_WIDTH < COLUMN_SUM_WIDTH)
      $fatal(1, "update_dot_products: ACCUM_WIDTH must be >= COLUMN_SUM_WIDTH (%0d)", COLUMN_SUM_WIDTH);
  end
  
  // Internal signals
  logic signed [COLUMN_SUM_WIDTH-1:0] column_sums [0:VECTOR_SIZE-1];
  logic handle_done;
  logic signed [ACCUM_WIDTH-1:0] accum_reg [0:VECTOR_SIZE-1];
  logic signed [ACCUM_WIDTH-1:0] new_accum_value [0:VECTOR_SIZE-1];
  logic signed [ACCUM_WIDTH-1:0] column_sums_ext [0:VECTOR_SIZE-1];
  
  // Instantiate handle_input_rows
  handle_input_rows #(
    .NUM_ROWS       (NUM_ROWS_PER_CLK),
    .VECTOR_SIZE    (VECTOR_SIZE),
    .DATA_WIDTH     (DATA_WIDTH),
    .PIPED          (PIPED),
    .LEVELS         (LEVELS),
    .PIPE_STAGE_MASK(PIPE_STAGE_MASK)
  ) u_handle_input_rows (
    .clk            (clk),
    .rst_n          (rst_n),
    .j_rows         (j_rows),
    .j_rows_valid   (j_rows_valid),
    .sigma_bits     (sigma_bits),
    .column_sums    (column_sums),
    .done           (handle_done)
  );
  
  // Generate accumulators for each column
  generate
    for (genvar c = 0; c < VECTOR_SIZE; c++) begin : GEN_ACCUMULATOR
      
      // Sign-extend column sum to accumulator width
      assign column_sums_ext[c] = ACCUM_WIDTH'(column_sums[c]);
      
      // Instantiate adder for accumulation
      adder_subtractor #(
        .WIDTH (ACCUM_WIDTH)
      ) u_adder (
        .a       (accum_reg[c]),
        .b       (column_sums_ext[c]),
        .sub     (1'b0),
        .result  (new_accum_value[c]),
        .cout    (),
        .overflow(),
        .zero    ()
      );
      
      // Accumulator register with reset value from input port
      `FFLARNC(accum_reg[c], new_accum_value[c], handle_done, clear, reset_values[c], clk, rst_n)
      
      // Output assignment
      assign accumulated_sums[c] = accum_reg[c];
      
    end : GEN_ACCUMULATOR
  endgenerate
  
  // Done signal
  assign done = handle_done;

endmodule