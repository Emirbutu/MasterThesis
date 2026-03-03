// Find all positions of '1' bits in parallel
// Outputs a compacted array of positions where bits are set

`include "VX_platform.vh"

module find_all_ones #(
    parameter N = 256,              // Input bitstream width
    parameter LOGN = `LOG2UP(N)     // Bits needed to represent position
) (
    input  wire [N-1:0]              data_in,
    output wire [N-1:0][LOGN-1:0]    positions,  // Array of positions (compacted)
    output wire [LOGN:0]             count,      // Number of 1s found
    output wire                      valid       // At least one 1 found
);

    // Step 1: Generate position indices for each bit
    wire [N-1:0][LOGN-1:0] bit_positions;
    for (genvar i = 0; i < N; ++i) begin : g_positions
        assign bit_positions[i] = LOGN'(i);
    end

    // Step 2: Extract valid positions (where data_in[i] == 1)
    // This creates a sparse array with gaps
    wire [N-1:0][LOGN-1:0] sparse_positions;
    wire [N-1:0] valid_bits;
    
    for (genvar i = 0; i < N; ++i) begin : g_extract
        assign valid_bits[i] = data_in[i];
        assign sparse_positions[i] = data_in[i] ? bit_positions[i] : '0;
    end

    // Step 3: Compact the array (remove gaps)
    // Use a parallel prefix network to compute write positions
    wire [N-1:0][LOGN:0] prefix_sum;
    
    // First element
    assign prefix_sum[0] = {1'b0, valid_bits[0]};
    
    // Compute running sum of valid bits
    for (genvar i = 1; i < N; ++i) begin : g_prefix
        assign prefix_sum[i] = prefix_sum[i-1] + valid_bits[i];
    end
    
    // Total count of 1s
    assign count = prefix_sum[N-1];
    assign valid = (count != 0);
    
    // Step 4: Write positions to compacted output array
    // Each valid bit writes its position to the appropriate index
    reg [N-1:0][LOGN-1:0] positions_reg;
    
    always_comb begin
        // Initialize all positions to 0
        positions_reg = '0;
        
        // For each input bit, if it's set, write its position
        for (int i = 0; i < N; i++) begin
            if (valid_bits[i]) begin
                // Write position is (prefix_sum[i] - 1)
                positions_reg[prefix_sum[i] - 1'b1] = bit_positions[i];
            end
        end
    end
    
    assign positions = positions_reg;

endmodule
`TRACING_ON
