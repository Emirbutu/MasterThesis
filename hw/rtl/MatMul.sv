//License: KU Leuven
module MatMul #(
    // Memory interface parameters
    parameter int MEM_BANDWIDTH   = 4096/4,        // Memory bandwidth in bits per clock cycle
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
    parameter int ENERGY_WIDTH    = $clog2(VECTOR_SIZE) + $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH +1,  // +1 for sign
    // Adder tree parameters
    parameter int LEVELS         = $clog2(VECTOR_SIZE), // number of levels in the adder tree
    parameter logic [LEVELS:0] PIPE_STAGE_MASK = {1'b1, {LEVELS{1'b0}}}, //  pipelined stages
    parameter bit PIPED             = 1'b1,
    parameter int PIPE_DEPTH   = PIPED ? $countones(PIPE_STAGE_MASK) : 0 // pipelined or combinational adder tree
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
    input  logic [ENERGY_WIDTH-1:0]                   Energy_previous,
    output logic sigma_needed_debug [0:J_COLS_PER_CLK-1],
    output logic signed [ENERGY_WIDTH-1:0] Energy_next_output
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
  assign Energy_next_output = Energy_next;
  // Generate the multiply-accumulate logic
 // Width to safely accumulate J_COLS_PER_CLK signed dot-products
  localparam int ACC_WIDTH = INT_RESULT_WIDTH + $clog2(J_COLS_PER_CLK) + 1; // +1 for sign
  // width for column index into sigma
  localparam int SIG_IDX_W = $clog2(VECTOR_SIZE);

  // base column of current chunk
  logic [9:0] start_piped;
  logic start_out;
  // Chain across columns for σ^T accumulation
  logic signed [ACC_WIDTH-1:0] stage2_sum [0:J_COLS_PER_CLK];
  assign stage2_sum[0] = '0;
  logic signed [ACC_WIDTH-1:0] block_sum; // final sum for a J chunk
  localparam int LANES = J_COLS_PER_READ; // or J_COLS_PER_CLK
  logic [$clog2(NUM_J_CHUNKS)-1:0] chunk_in_ctr;
  logic                            in_active;

  
  // Build lane-wise columns from J_Matrix_chunk[ROW][LANE]
  logic [J_ELEMENT_WIDTH-1:0] J_cols [LANES][0:VECTOR_SIZE-1];
  genvar c, r;
  generate
    for (c = 0; c < LANES; c++) begin : MAP_LANES
      for (r = 0; r < VECTOR_SIZE; r++) begin : MAP_ROWS
        assign J_cols[c][r] = J_Matrix_chunk[r][c];
      end
    end
  endgenerate

  // Outputs from the parallel dot-product array
  logic signed [INT_RESULT_WIDTH-1:0] dot_outs [LANES];
  logic                               start_outs [LANES];

  // Instantiate the array: parallel dot products, no accumulation here
  generate
  DotProductTree_array #(
    .PIPED            (PIPED),
    .VECTOR_SIZE      (VECTOR_SIZE),
    .J_ELEMENT_WIDTH  (J_ELEMENT_WIDTH),
    .LEVELS           ($clog2(VECTOR_SIZE)),
    .PIPE_STAGE_MASK  (PIPE_STAGE_MASK),
    .INT_RESULT_WIDTH (INT_RESULT_WIDTH),
    .LANES            (LANES)
  ) u_dpa (
    .clk        (clk),
    .rst_n      (rst_n),
    .sigma      (sigma),     // shared row-level sigma vector
    .J_cols     (J_cols),    // per-lane column vectors
    .start      (start),     // or your input-side valid (e.g., 'processing')
    .dot_outs   (dot_outs),
    .start_outs (start_outs)
  );
  endgenerate
logic  sigma_needed [0:LANES-1];
  // Determine which sigma bits are needed for each lane b
 always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (int i = 0; i < LANES; i++) begin
            sigma_needed[i] <= 1'b0;
        end
    end else  begin
        for (int i = 0; i < LANES; i++) begin
            logic [SIG_IDX_W-1:0] sigma_idx;
            sigma_idx = j_chunk_counter * J_COLS_PER_CLK + i;
            sigma_needed[i] <= sigma[sigma_idx];
        end
    end
 end


generate
  for (c = 0; c < LANES; c++) begin : GEN_ACCUMULATE
adder_subtractor_unit #(
    .WIDTH(ACC_WIDTH)
) adder_subtractor_unit_inst (
    .a(stage2_sum[c]),
    .b({{(ACC_WIDTH-INT_RESULT_WIDTH){dot_outs[c][INT_RESULT_WIDTH-1]}}, dot_outs[c]}), // sign-extend dot_out
    .sub(sigma_needed[c]), // 1=add, 0=sub
    .y(stage2_sum[c+1])
);
  end
 endgenerate
  
assign block_sum = stage2_sum[LANES];

assign sigma_needed_debug = sigma_needed;


// Use start_enable_pulse to set start_enable
always_ff @(posedge clk or negedge rst_n) begin
  if (!rst_n) begin
    start_enable <= 0;
  end else begin
    if (start_outs[0]) begin
      start_enable <= 1;
    end else if (j_chunk_counter == (NUM_J_CHUNKS-1)) begin
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
    .WIDTH($clog2(NUM_J_CHUNKS)+1)
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
        end else if (!start_enable_prev) begin
            Energy_next <= 0;
        end else if (start_enable || start_enable_prev) begin
            Energy_next <= Energy_next + block_sum;
        end
    end
  

endmodule