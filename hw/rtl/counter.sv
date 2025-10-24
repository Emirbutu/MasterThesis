//Parameterized Counter Module
module counter #(
    parameter int WIDTH = 8             // Width of the counter
)(
    input  logic                clk,      // Clock input
    input  logic                rst_n,    // Active-low reset (asynchronous)
    input  logic                en,       // Counter enable
    output logic [WIDTH-1:0]    count,    // Current count value
    output logic                wrap      // Indicates counter wrapped around
);
    localparam int MAX_VALUE = 2**WIDTH-1;
    // Next value logic
    logic [WIDTH-1:0] next_count;
    
    // Wrap detection
    logic will_wrap;
    
    assign will_wrap = (count == MAX_VALUE);

    // Next count value calculation
    always_comb begin
        if (!en) begin
            next_count = '0;
        end else begin
            // Count up with wrap-around at MAX_VALUE
            next_count = will_wrap ? '0 : count + 1'b1;
        end
    end

    // Sequential logic with asynchronous reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
            wrap  <= 1'b0;
        end else begin
            count <= next_count;
            wrap  <= will_wrap;
        end
    end

    // Parameter validation
    initial begin
        if (WIDTH <= 0) begin
            $error("WIDTH must be positive");
        end
        if (MAX_VALUE >= 2**WIDTH) begin
            $error("MAX_VALUE must be less than 2**WIDTH");
        end
    end

endmodule
