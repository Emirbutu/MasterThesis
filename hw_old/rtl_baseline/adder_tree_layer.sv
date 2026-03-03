//KU Leuven License
module adder_tree_layer #(
    parameter int INPUTS_AMOUNT,
    parameter int DATAW
) (
    input logic [DATAW-1:0] inputs [INPUTS_AMOUNT],
    output logic [DATAW:0] outputs [INPUTS_AMOUNT/2]// #outputs = #inputs halved
);
    localparam int Num_of_outputs = INPUTS_AMOUNT/2;

  
    genvar i;
    generate
        for (i = 0; i < Num_of_outputs; i = i + 1) begin: adder_generation
            assign outputs[i] = signed'(inputs[2*i]) + signed'(inputs[2*i+1]);
        end
    endgenerate
    
endmodule
