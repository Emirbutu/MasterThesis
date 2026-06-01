// Find all positions iteratively using priority encoder
// Takes multiple cycles but uses less area


`define CLOG2(x)    $clog2(x)
`define FLOG2(x)    ($clog2(x) - (((1 << $clog2(x)) > (x)) ? 1 : 0))
`define LOG2UP(x)   (((x) > 1) ? $clog2(x) : 1)
module find_all_ones_iterative #(
    parameter N = 256,
    parameter LOGN = `LOG2UP(N)
) (
    input  wire                      clk_i,
    input  wire                      rst_ni,
    input  wire                      start_i,        // Pulse to begin search
    input  wire [N-1:0]              data_i,
    
    output wire [N-1:0][LOGN-1:0]    positions,    // Array of found positions
    output wire [N-1:0]              valid_o,      // Valid bit for each position
    output wire [LOGN:0]             count,        // Number of 1s found
    output wire                      done,         // Search complete
    output wire                      empty_o       // No '1' bits found (set on first detection)
);

    // State machine
    typedef enum logic [1:0] {
        IDLE,
        SEARCH,
        DONE_ST
    } state_t;
    
    state_t state, next_state;
    
    // Internal registers
    reg [N-1:0] remaining_bits;
    reg [LOGN:0] found_count;
    reg [N-1:0][LOGN-1:0] positions_array;
    reg [N-1:0] valid_array;
    reg empty_flag;
    
    // LZC for finding next '1'
    wire [LOGN-1:0] next_pos;
    wire valid_found;
    
    lzc #(
        .N(N),
        .REVERSE(1)  // Start_i from LSB (bit 0)
    ) lzc_inst (
        .data_in(remaining_bits),
        .data_out(next_pos),
        .valid_out(valid_found)
    );
    
    // State machine
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start_i) next_state = SEARCH;
            end
            SEARCH: begin
                if (!valid_found) next_state = DONE_ST;
            end
            DONE_ST: begin
                next_state = IDLE;
            end
        endcase
    end
    
    // Datapath
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            remaining_bits <= '0;
            found_count <= '0;
            positions_array <= '0;
            valid_array <= '0;
            empty_flag <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    if (start_i) begin
                        remaining_bits <= data_i;
                        found_count <= '0;
                        positions_array <= '0;
                        valid_array <= '0;
                        empty_flag <= 1'b0;
                    end
                end
                
                SEARCH: begin
                    if (valid_found) begin
                        // Store the position
                        positions_array[found_count] <= next_pos;
                        valid_array[found_count] <= 1'b1;
                        found_count <= found_count + 1'b1;
                        
                        // Clear the found bit
                        remaining_bits[next_pos] <= 1'b0;
                    end else if (found_count == '0) begin
                        // No '1' bit found at first detection
                        empty_flag <= 1'b1;
                    end
                end
                
                DONE_ST: begin
                    // Hold results
                end
            endcase
        end
    end
    
    // Outputs
    assign positions = positions_array;
    assign valid_o = valid_array;
    assign count = found_count;
    assign done = (state == DONE_ST);
    assign empty_o = empty_flag;

endmodule
