module MatMul #(
    parameter int VECTOR_WIDTH = 8,
    parameter int N            = 4
)(
    input  logic [VECTOR_WIDTH-1:0]   sigma_vector ,
    input  logic [N-1:0] J_Column [VECTOR_WIDTH], // VECTOR_WIDTH x VECTOR_WIDTH matrix,
                                                                        // each element is N bits
    output logic [DATA_WIDTH-1:0]   data_out
);


endmodule

// End of MatMul.sv