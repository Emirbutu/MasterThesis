// DotProductChain.sv

module DotProductChain #(
    parameter int VECTOR_SIZE       = 256,
    parameter int J_ELEMENT_WIDTH   = 4,
    parameter int INT_RESULT_WIDTH  = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH
)(
    input  logic [VECTOR_SIZE-1:0]                          sigma,   // control bits
    input  logic [J_ELEMENT_WIDTH-1:0]               J_col [0:VECTOR_SIZE-1], // one J column
    output logic signed [INT_RESULT_WIDTH-1:0]              dot_out
);
    // stage_sum[VECTOR_SIZE] is the final dot product.
    logic signed [INT_RESULT_WIDTH-1:0] stage_sum [0:VECTOR_SIZE];
    //assign stage_sum[0] = '0;

    genvar k;
    generate
        for (k = 0; k < VECTOR_SIZE; k++) begin : Mult_sigma_with_J
            // Sign-extend J element to adder width
            logic signed [INT_RESULT_WIDTH-1:0] b_ext;
            assign b_ext = { {(INT_RESULT_WIDTH - J_ELEMENT_WIDTH){1'b0}}, J_col[k] };

            adder_subtractor_unit #(
                .WIDTH(INT_RESULT_WIDTH)
            ) addsub_i (
                .a  (0), //It was stage_sum[k], but changed to 0 
                .b  (b_ext),
                .sub(sigma[k]),   // 0 = subtract, 1 = add 
                .y  (stage_sum[k])
            );
        end






    endgenerate

    assign dot_out = stage_sum[VECTOR_SIZE];
endmodule
