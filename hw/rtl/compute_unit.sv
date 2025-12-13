`include "include/registers.svh"

module compute_unit #(
  // ========== Configurable Parameters ==========
  parameter int VECTOR_SIZE    = 256,    // Size of sigma vectors and J matrix rows
  parameter int DATA_WIDTH     = 4,      // Bit width of each J element (signed)
  parameter int COL_PER_CC     = 1,       // Number of J columns processed per cycle
  parameter bit PIPED_FIRST_TREE          = 1,      // Pipeline adder trees
  parameter int LEVELS_1         = (VECTOR_SIZE > 1) ? $clog2(VECTOR_SIZE) : 0,
  parameter logic [LEVELS_1:0] PIPE_STAGE_MASK_FIRST_TREE = '1,
  // Width calculations
  parameter int MUX_DATA_WIDTH = DATA_WIDTH + 1,  // Extended by 1 bit for negation
  parameter int FIRST_TREE_OUTPUT_WIDTH = MUX_DATA_WIDTH + LEVELS_1,  // First tree output width
  parameter int SECOND_TREE_OUTPUT_WIDTH = FIRST_TREE_OUTPUT_WIDTH + LEVELS_2,  // Second tree output width
  parameter int ACCUM_WIDTH = DATA_WIDTH + $clog2(VECTOR_SIZE * VECTOR_SIZE) + 1,  // Accumulator width: covers VECTOR_SIZE*VECTOR_SIZE*DATA_WIDTH + sign
  parameter bit PIPED_SECOND_TREE          = 1,      // Pipeline second adder tree
  parameter int LEVELS_2         = (COL_PER_CC > 1) ? $clog2(COL_PER_CC) : 0,
  parameter logic [LEVELS_2:0] PIPE_STAGE_MASK_SECOND_TREE = '1
)(
  // ========== Clock and Reset ==========
  input  logic clk,
  input  logic rst_n,
  // ========== Sigma Vectors ==========
  // sigma_f: VECTOR_SIZE elements, each 1 bit
  input  logic [VECTOR_SIZE-1:0] sigma_f,          //Showing the bits that are flipped with respect to previous sigma
  // sigma_f_inv: VECTOR_SIZE elements, each 1 bit
  input  logic [VECTOR_SIZE-1:0] sigma_f_inv,      //Showing the bits that are not flipped with respect to previous sigma
  // sigma_new: VECTOR_SIZE elements, each 1 bit
  input  logic [VECTOR_SIZE-1:0] sigma_new,
  // ========== J Matrix Columns ==========
  // COL_PER_CC columns, each with VECTOR_SIZE elements of DATA_WIDTH bits
  input  logic signed [DATA_WIDTH-1:0] j_cols [0:COL_PER_CC-1][0:VECTOR_SIZE-1],
  // ========== Control Signals ==========
  input  logic [COL_PER_CC-1:0] valid_i,
  input  logic [COL_PER_CC-1:0] final_flag_i,
  input  logic clear,
  // ========== Outputs ==========
  output logic signed [ACCUM_WIDTH-1:0] accum_out,
  output logic final_flag_o
  );
  // ========== Compile-time Checks ==========
  initial begin
    if (VECTOR_SIZE < 1)
      $fatal(1, "compute_unit: VECTOR_SIZE must be >= 1");
    if (DATA_WIDTH < 1)
      $fatal(1, "compute_unit: DATA_WIDTH must be >= 1");
    if (COL_PER_CC < 1)
      $fatal(1, "compute_unit: COL_PER_CC must be >= 1");
  end
// ========== Internal Signals ==========
logic [1:0] sigma_c [0:VECTOR_SIZE-1];
// sigma_c_inverse: Result of sigma_new * sigma_f_inv (2-bit: 00=0, 01=+1, 11=-1)
logic [1:0] sigma_r [0:VECTOR_SIZE-1];
// MUX signals
logic signed [MUX_DATA_WIDTH-1:0] mux_inputs [0:COL_PER_CC-1][0:VECTOR_SIZE-1][0:2];
logic signed [MUX_DATA_WIDTH-1:0] mux_out [0:COL_PER_CC-1][0:VECTOR_SIZE-1];
// First Adder tree signals
logic signed [FIRST_TREE_OUTPUT_WIDTH-1:0] column_sums [0:COL_PER_CC-1];
logic final_flag_piped [0:COL_PER_CC-1];
logic done [0:COL_PER_CC-1];
// Second Adder tree signals
logic start_second_tree;
logic final_flag_second_tree_i;
logic final_flag_second_tree_o;
logic signed [SECOND_TREE_OUTPUT_WIDTH-1:0] final_sum;
logic acc_flag;
// Accumulator signals
logic signed [ACCUM_WIDTH-1:0] accum_q;
logic signed [ACCUM_WIDTH-1:0] accum_d;
logic accum_load;
logic final_flag_delayed;
// ========== Generate sigma_c ==========
generate
  for (genvar i = 0; i < VECTOR_SIZE; i++) begin : GEN_SIGMA_C
    assign sigma_c[i] = sigma_f[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00; // It means that if sigma_f is 1, then sigma_c is +1(2'b01)
                                                                             // or -1(2'b10) based on sigma_new, else 0
  
  end : GEN_SIGMA_C
endgenerate
// ========== Generate sigma_c_inverse ==========
generate
  for (genvar i = 0; i < VECTOR_SIZE; i++) begin : GEN_SIGMA_R
    assign sigma_r[i] = sigma_f_inv[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00;// It means that if sigma_f_inv is 1, then sigma_c is +1(2'b01) 
                                                                                // or -1(2'b10) based on sigma_new, else 0
  end : GEN_SIGMA_R
endgenerate
// ========== Generate MUXes for J column selection ==========
logic signed [MUX_DATA_WIDTH-1:0] mux_out_pre [0:COL_PER_CC-1][0:VECTOR_SIZE-1];

generate
  for (genvar col = 0; col < COL_PER_CC; col++) begin : GEN_COL
    for (genvar row = 0; row < VECTOR_SIZE; row++) begin : GEN_ROW
      
      // MUX inputs: [0] = zero, [1] = J element, [2] = -J element
      assign mux_inputs[col][row][0] = '0;
      assign mux_inputs[col][row][1] = MUX_DATA_WIDTH'(j_cols[col][row]);
      assign mux_inputs[col][row][2] = -MUX_DATA_WIDTH'(j_cols[col][row]);
      
      // Instantiate generic_mux
      generic_mux #(
        .NUM_INPUTS (3),
        .DATA_WIDTH (MUX_DATA_WIDTH)
      ) u_mux (
        .inputs (mux_inputs[col][row]),
        .sel    (sigma_c[row]),
        .out    (mux_out_pre[col][row])
      );
      
      // Mask output with valid signal
      assign mux_out[col][row] = valid_i[col] ? mux_out_pre[col][row] : '0;
      
    end : GEN_ROW
  end : GEN_COL
endgenerate

// ========== Generate Adder Trees for Each Column ==========
  generate
    for (genvar col = 0; col < COL_PER_CC; col++) begin : GEN_ADDER_TREE
      
      // Collect all mux outputs for this column
      logic signed [MUX_DATA_WIDTH-1:0] adder_inputs [0:VECTOR_SIZE-1];
      
      for (genvar row = 0; row < VECTOR_SIZE; row++) begin : GEN_ADDER_INPUT
        assign adder_inputs[row] = mux_out[col][row];
      end : GEN_ADDER_INPUT
      
      // Instantiate adder tree for this column
      adder_tree #(
        .PIPED           (PIPED_FIRST_TREE),
        .NUM_INPUTS      (VECTOR_SIZE),
        .INPUT_WIDTH     (MUX_DATA_WIDTH),
        .LEVELS          (LEVELS_1),
        .PIPE_STAGE_MASK (PIPE_STAGE_MASK_FIRST_TREE),
      ) u_adder_tree (
        .clk       (clk),
        .rst_n     (rst_n),
        .inputs    (adder_inputs),
        .start     (valid_i[col]),
        .final_flag_i (final_flag_i[col]),
        .sum_out   (column_sums[col]),
        .start_out (done[col]),
        .final_flag_o (final_flag_piped[col])
      );
      
    end : GEN_ADDER_TREE
  endgenerate
// ========== OR the done and final_flag signals to create start for second tree ==========
assign start_second_tree = |done;
assign final_flag_second_tree_i = |final_flag_piped;
// ========== Second Level Adder Tree (sum all columns) ==========
adder_tree #(
  .PIPED           (PIPED_SECOND_TREE),
  .NUM_INPUTS      (COL_PER_CC),
  .INPUT_WIDTH     (FIRST_TREE_OUTPUT_WIDTH),
  .LEVELS          (LEVELS_2),
  .PIPE_STAGE_MASK (PIPE_STAGE_MASK_SECOND_TREE),  // Use same pipelining strategy
  .OUTPUT_WIDTH    (SECOND_TREE_OUTPUT_WIDTH)
) u_final_adder_tree (
  .clk       (clk),
  .rst_n     (rst_n),
  .inputs    (column_sums),
  .start     (start_second_tree),
  .final_flag_i (final_flag_second_tree_i),
  .sum_out   (final_sum),
  .start_out (acc_flag),
  .final_flag_o (final_flag_second_tree_o)
);

// ========== Accumulator Register with Adder ==========
// Load when acc_flag or final_flag_second_tree_o is asserted
assign accum_load = acc_flag | final_flag_second_tree_o;

// Adder: accumulate final_sum into accumulator
assign accum_d = accum_q + ACCUM_WIDTH'(final_sum);

// Accumulator register with load-enable, async reset, and sync clear
`FFLARNC(accum_q, accum_d, accum_load, clear, '0, clk, rst_n)

// Output accumulator value
assign accum_out = accum_q;

// Propagate final flag, avoid sync issues
`FF(final_flag_delayed, final_flag_second_tree_o, '0, clk, rst_n)
assign final_flag_o = final_flag_delayed;
endmodule