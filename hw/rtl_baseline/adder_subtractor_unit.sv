//License: KU LeuvenBut
module adder_subtractor_unit #(
    parameter WIDTH = 8
)(
    input  logic signed [WIDTH-1:0] a,
    input  logic signed [WIDTH-1:0] b,
    input  logic                    sub,  // 1 = add, 0 = subtract
    output logic signed [WIDTH-1:0] y
);
    always_comb begin
        if (!sub)
            y = a - b;
        else
            y = a + b;
    end
endmodule
