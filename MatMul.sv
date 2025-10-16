module MatMul #(
    // Number of elements in the vector (e.g. 256)
    parameter int VECTOR_WIDTH = 256,
    // Width (bits) of each J element (e.g. 8)
    parameter int N            = 8,
    // Accumulator width: enough bits to hold VECTOR_WIDTH elements of N bits summed together.
    parameter int ACC_WIDTH    = N + $clog2(VECTOR_WIDTH) + $clog2(VECTOR_WIDTH)
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic        [N-1:0]            J_Column [0:VECTOR_WIDTH-1], // Column of J matrix (256 elements of 8 bits each)
    input  logic                           start,
    input  logic                           sigma_vector [0:VECTOR_WIDTH-1], // Vector of signs

    input  logic        [ACC_WIDTH:0]      E_p, // Positive energy
    output logic signed [ACC_WIDTH:0]      dot_result, // 25 bits to avoid overflow when summing 256 8-bit numbers and deal with sign
    output logic                           done,
    output logic                           flag  // Flag to indicate if dot_product > E_p  
);  


    logic [$clog2(VECTOR_WIDTH)-1:0] idx,cdx;

    typedef enum logic [1:0] {
        IDLE,
        COMPUTE,
        DONE
    } state_t;
    state_t state, next_state;




assign flag = (dot_result > E_p);

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (start) begin
                    next_state = COMPUTE;
                end
            end
            COMPUTE: begin
                if ((idx == VECTOR_WIDTH-1 && cdx == VECTOR_WIDTH-1) || flag == 1'd1) begin
                    next_state = DONE;
                end
            end
            DONE: begin
                next_state = IDLE;
            end
        endcase
    end




    always_ff @(posedge clk or negedge rst_n) begin
        if (state == COMPUTE) begin
            if (idx !=VECTOR_WIDTH - 1) begin
                dot_result <= sigma_vector[idx] ? dot_result + J_Column[idx]: dot_result - J_Column[idx];
                idx <= idx + 8'd1;
            end else if (cdx != VECTOR_WIDTH-1) begin
                cdx <= cdx + 8'd1;
                idx <= 0;
            end else begin
                cdx <= 0;
                idx <= 0;
            end 

            
        end else if (state == DONE) begin
            done <= 1'b1;
        end else if (state == IDLE) begin
            done <= 1'b0;
            flag <= 1'b0;
            dot_result <= '0;
            idx <= 0;
            cdx <= 0;
        end




     end




    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset all state elements and outputs
            state      <= IDLE;
            idx        <= '0;
            cdx        <= '0;
            dot_result <= '0;
            done      <= 1'b0;
        end else begin
            state <= next_state;
        end
    end 
    end
endmodule

// End of MatMul.sv