module handle_input_rows #(
  // ========== Configurable Parameters ==========
  parameter int NUM_ROWS    = 4,      // Number of rows in J matrix
  parameter int VECTOR_SIZE  = 256,    // Number of elements per row
  parameter int DATA_WIDTH  = 4,      // Bit width of each J element (signed)
  parameter bit PIPED       = 1,
  parameter int LEVELS      = (NUM_ROWS > 1) ? $clog2(NUM_ROWS) : 0,
  parameter logic [LEVELS:0] PIPE_STAGE_MASK = '1     
  
)(
  // ========== Clock and Reset ==========
  input  logic clk,
  input  logic rst_n,

  // ========== J Matrix Rows ==========
  // Each row is an array of VECTOR_SIZE elements, each DATA_WIDTH bits wide
  input  logic signed [DATA_WIDTH-1:0] j_rows [0:NUM_ROWS-1][0:VECTOR_SIZE-1],
  input  logic [NUM_ROWS-1:0] j_rows_valid,
  

  // ========== Sigma Vector ==========
  // VECTOR_SIZE elements, each SIGMA_WIDTH bits wide
  input  logic [NUM_ROWS-1:0] sigma_bits,
 
  // ========== Control Signals ==========
  // ========== Outputs (to be defined in next steps) ==========
  output logic signed [DATA_WIDTH+1+LEVELS:0] column_sums [0:VECTOR_SIZE-1], // Each column sum output, 
  // BIT_WIDTH adjusted for shifts and additions,1 for shift,1 for sign, LEVELS for adder tree
  
  output logic done
);
  localparam int MUX_OUT_WIDTH = DATA_WIDTH + 1; // Width after left shift
  localparam int WIDTH_BEFORE_TREE   = MUX_OUT_WIDTH + 1; 
  // ========== Compile-time Checks ==========
  initial begin
    if (NUM_ROWS < 1)
      $fatal(1, "j_matrix_processor: NUM_ROWS must be >= 1");
    if (VECTOR_SIZE < 1)
      $fatal(1, "j_matrix_processor: VECTOR_SIZE must be >= 1");
    if (DATA_WIDTH < 1)
      $fatal(1, "j_matrix_processor: DATA_WIDTH must be >= 1");
  end

  // ========== Implementation will go here ==========
  
  // Placeholder
  logic signed [MUX_OUT_WIDTH-1:0] j_rows_shifted [0:NUM_ROWS-1][0:VECTOR_SIZE-1];
  logic adder_start;
  assign adder_start = |j_rows_valid;

  // Adder tree outputs
  logic [VECTOR_SIZE-1:0] adder_start_out;
    logic signed [WIDTH_BEFORE_TREE-1:0] sigma_times_rows [0:NUM_ROWS-1][0:VECTOR_SIZE-1];
  // MUX inputs array for each element
  logic [MUX_OUT_WIDTH-1:0] mux_inputs [0:NUM_ROWS-1][0:VECTOR_SIZE-1][0:1];
  logic signed [MUX_OUT_WIDTH-1:0] mux_out [0:NUM_ROWS-1][0:VECTOR_SIZE-1];
  // ========== Generate Shifted Values and MUX ==========
  generate
    for (genvar r = 0; r < NUM_ROWS; r++) begin : GEN_ROW
      for (genvar c = 0; c < VECTOR_SIZE; c++) begin : GEN_COL
        
        // Left shift (multiply by 2) with sign extension
        assign j_rows_shifted[r][c] = {j_rows[r][c], 1'b0};

        // MUX inputs: [0] = zero, [1] = shifted value
        assign mux_inputs[r][c][0] = '0;
        assign mux_inputs[r][c][1] = j_rows_shifted[r][c];

        // Instantiate 2:1 MUX using generic_mux
        generic_mux #(
          .NUM_INPUTS (2),
          .DATA_WIDTH (MUX_OUT_WIDTH)
        ) u_mux (
          .inputs (mux_inputs[r][c]),
          .sel    (j_rows_valid[r]),
          .out    (mux_out[r][c])
        );

      assign sigma_times_rows[r][c] = sigma_bits[r] ? 
                                 WIDTH_BEFORE_TREE'(mux_out[r][c]) : 
                                -WIDTH_BEFORE_TREE'(mux_out[r][c]); 

      end : GEN_COL
    end : GEN_ROW
  endgenerate


    // ========== Adder Tree for Each Column ==========
  generate
    for (genvar c = 0; c < VECTOR_SIZE; c++) begin : GEN_ADDER_TREE
      
      // Collect inputs for this column's adder tree
      logic signed [WIDTH_BEFORE_TREE-1:0] adder_inputs [0:NUM_ROWS-1];
      
      for (genvar r = 0; r < NUM_ROWS; r++) begin : GEN_ADDER_INPUT
        assign adder_inputs[r] = sigma_times_rows[r][c];
      end

      // Instantiate adder tree for this column
      adder_tree #(
        .PIPED          (PIPED),
        .NUM_INPUTS     (NUM_ROWS),
        .INPUT_WIDTH    (WIDTH_BEFORE_TREE),
        .PIPE_STAGE_MASK(PIPE_STAGE_MASK)
      ) u_adder_tree (
        .clk      (clk),
        .rst_n    (rst_n),
        .inputs   (adder_inputs),
        .start    (adder_start),
        .sum_out  (column_sums[c]),
        .start_out(adder_start_out[c])
      );

    end : GEN_ADDER_TREE
  endgenerate

  
  assign done = adder_start_out[0]; 
  

endmodule