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
    parameter int INT_RESULT_WIDTH    = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH,
    // Energy bit width calculation
    parameter int ENERGY_WIDTH    = $clog2(VECTOR_SIZE) + $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH
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
  // Local function for adder/subtractor
  function signed [INT_RESULT_WIDTH-1:0] adder_subtractor (
      input logic         sigma_bit,
      input logic [J_ELEMENT_WIDTH-1:0] j_element
  );
      adder_subtractor = sigma_bit ? j_element : -j_element;
  endfunction : adder_subtractor
  
  // Accumulator for final result
  logic signed [ENERGY_WIDTH-1:0] Energy_next; // 1 bit wider???
  // Counter for iterating over J matrix chunks
  logic [$clog2(NUM_J_CHUNKS)-1:0] j_chunk_counter;
  // Sampled start signal
  logic start_enable;
  logic start_enable_prev;
  logic energy_exceeded;
  assign energy_exceeded = (Energy_next >= Energy_previous);

  // Generate the multiply-accumulate logic
logic signed [ENERGY_WIDTH-1:0] temp_Energy_next;
always_comb begin
  temp_Energy_next = '0;
  for (int i = 0; i < J_COLS_PER_CLK; i++) begin
    automatic logic signed [INT_RESULT_WIDTH-1:0] temp_sum = '0;
    for (int k = 0; k < VECTOR_SIZE; k++) begin
      temp_sum += adder_subtractor(sigma[k], J_Matrix_chunk[k][i]);
    end
    temp_Energy_next += temp_sum;
  end
end


  // Sample the start signal
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      start_enable <= 0;
    end else begin
      if (start) begin
        start_enable <= 1;
      end else if (j_chunk_counter == (NUM_J_CHUNKS - 1) || energy_exceeded) begin
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
    .WIDTH($clog2(NUM_J_CHUNKS)),
    .MAX_VALUE(NUM_J_CHUNKS )
  ) counter_inst (
    .clk(clk),
    .rst_n(rst_n),
    .en(start_enable), // Enable the counter when start is asserted
    .count(j_chunk_counter),
    .wrap() // Not used
  );

  // Accumulate temp_Energy_next into Energy_next
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Energy_next <= 0;
        end else if (start_enable_prev && !start_enable) begin
            Energy_next <= 0;
        end else if (start_enable) begin
            Energy_next <= Energy_next + temp_Energy_next;
        end
    end
  

endmodule