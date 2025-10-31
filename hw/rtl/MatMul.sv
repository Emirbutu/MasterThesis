//License: KU Leuven
module MatMul #(
    // Memory interface parameters
    parameter int MEM_BANDWIDTH   = 4096,        // Memory bandwidth in bits per clock cycle
    // Matrix/Vector dimensions
    parameter int VECTOR_SIZE     = 256,         // Number of elements in sigma vector (configurable)
    parameter int J_ELEMENT_WIDTH = 4,           // Bit width of each J matrix element
    // Derived parameter: how many J columns fit in one memory read
    // Each J column uses VECTOR_SIZE * J_ELEMENT_WIDTH bits
    parameter int J_COLS_PER_READ = MEM_BANDWIDTH / (VECTOR_SIZE * J_ELEMENT_WIDTH),
    // Number of J columns processed per clock cycle
    parameter int J_COLS_PER_CLK = J_COLS_PER_READ,
    parameter int NUM_J_CHUNKS = VECTOR_SIZE / J_COLS_PER_READ,
    // Intermediate vector bit width calculation
    parameter int INT_RESULT_WIDTH    = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH + 1, // +1 for sign ???  I hope it's ok
    // Energy bit width calculation
    parameter int ENERGY_WIDTH    = $clog2(VECTOR_SIZE) + $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH +1  // +1 for sign
) (
    // Clock and reset
    input  logic                                      clk,
    input  logic                                      rst_n,
    // Control
    input  logic                                      start,        
    // Sigma vector — single-cycle supply (one bit per element)
    input  logic [VECTOR_SIZE-1:0]                    sigma,      // packed sigma bits (element 0 = LSB)
    // J matrix input: VECTOR_SIZE rows × J_COLS_PER_READ columns, each element is J_ELEMENT_WIDTH bits
    // Unpacked (big-endian) ordering for rows/columns: [0:VECTOR_SIZE-1][0:J_COLS_PER_READ-1]
    input  logic [J_ELEMENT_WIDTH-1:0]                J_Matrix_chunk [0:VECTOR_SIZE-1][0:J_COLS_PER_READ-1],
    input  logic [ENERGY_WIDTH-1:0]                   Energy_previous
);
  // Accumulator for final result
  logic signed [ENERGY_WIDTH-1:0] Energy_next; // sign bit extended
  // Counter for iterating over J matrix chunks
  logic [$clog2(NUM_J_CHUNKS)-1:0] j_chunk_counter;
  // Sampled start signal
  logic start_enable;
  logic start_enable_prev;
  logic energy_exceeded;
  assign energy_exceeded = (Energy_next >= Energy_previous);

  // Generate the multiply-accumulate logic
 // Width to safely accumulate J_COLS_PER_CLK signed dot-products
  localparam int ACC_WIDTH = INT_RESULT_WIDTH + $clog2(J_COLS_PER_CLK) + 1; // +1 for sign
  // width for column index into sigma
  localparam int SIG_IDX_W = $clog2(VECTOR_SIZE);

  // base column of current chunk
  wire [SIG_IDX_W-1:0] col_base = j_chunk_counter * J_COLS_PER_READ;

  // Chain across columns for σ^T accumulation
  logic signed [ACC_WIDTH-1:0] stage2_sum [0:J_COLS_PER_CLK];
  assign stage2_sum[0] = '0;
  logic signed [ACC_WIDTH-1:0] block_sum; // final sum for a J chunk
  genvar c, r;
  generate
    for (c = 0; c < J_COLS_PER_CLK; c++) begin : MULTIPLE_COLUMNS_AT_ONCE

      // Map column c of J_Matrix_chunk into a 1D array for the DotProductChain ( I also wonder if I can connect the whole column directly without this mapping)
      logic [J_ELEMENT_WIDTH-1:0] this_col [0:VECTOR_SIZE-1];
      for (r = 0; r < VECTOR_SIZE; r++) begin : MAP_COL
        assign this_col[r] = J_Matrix_chunk[r][c]; // UNSIGNED elements
      end

      // Per-column dot product (Σ with J_col[c]); UNSIGNED J w/ zero-extend handled inside
      wire signed [INT_RESULT_WIDTH-1:0] dot_c;
      DotProductChain #(
        .VECTOR_SIZE      (VECTOR_SIZE),
        .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH),
        .INT_RESULT_WIDTH (INT_RESULT_WIDTH)
      ) dpc_i (
        .sigma   (sigma),
        .J_col   (this_col),
        .dot_out (dot_c)
      );
      
      // Sign-extend dot_c up to the σ^T accumulator width
      wire signed [ACC_WIDTH-1:0] dot_ext =
        {{(ACC_WIDTH-INT_RESULT_WIDTH){dot_c[INT_RESULT_WIDTH-1]}}, dot_c}; // I copied the sign bit and filled the upper bits with it to do the sign-extension

      wire [SIG_IDX_W-1:0] col_idx = col_base + c;
      wire sigma_col_bit = sigma[col_idx];
      // σ^T accumulation: 0=subtract, 1=add
      adder_subtractor_unit #(
        .WIDTH(ACC_WIDTH)   
      ) addsub_sigmaT_i (
        .a   (stage2_sum[c]),
        .b   (dot_ext),
        .sub (sigma_col_bit),  // 0 = subtract, 1 = add]),
        .y   (stage2_sum[c+1])
      );
    end
  endgenerate

  assign block_sum = stage2_sum[J_COLS_PER_CLK];

  // Sample the start signal
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_enable <= 0;
    end else begin
      if (start) begin
        start_enable <= 1;
      end else if (j_chunk_counter == (NUM_J_CHUNKS-1)) begin //early stop is canceled for now
        start_enable <= 0;
      end
    end
  end
 
    
    // Sample start_enable to detect negative edge
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_enable_prev <= 0;
        end else begin
            start_enable_prev <= start_enable;
        end
    end

  // Instantiate the counter module
  counter #(
    .WIDTH($clog2(NUM_J_CHUNKS))
  ) counter_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en(start_enable), // Enable the counter when start is asserted
    .count(j_chunk_counter),
    .wrap() // Not used
  );

  // Accumulate block_sum  into Energy_next
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Energy_next <= 0;
        end else if (start_enable_prev && !start_enable) begin
            Energy_next <= 0;
        end else if (start_enable) begin
            Energy_next <= Energy_next + block_sum;
        end
    end
  

endmodule