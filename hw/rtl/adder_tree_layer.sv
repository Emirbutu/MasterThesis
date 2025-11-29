module adder_tree_layer #(
  parameter int INPUTS_AMOUNT = 4,
  parameter int DATAW = 8
)(
  input  logic signed [DATAW-1:0] inputs  [INPUTS_AMOUNT],
  output logic signed [DATAW:0]   outputs [INPUTS_AMOUNT/2]
);

  localparam int NUM_OUTPUTS = INPUTS_AMOUNT / 2;

  genvar i;
  generate
    for (i = 0; i < NUM_OUTPUTS; i++) begin : GEN_ADDERS
      // Sign-extend inputs to (DATAW+1) bits
      logic signed [DATAW:0] a_ext;
      logic signed [DATAW:0] b_ext;
      
      assign a_ext = {{1{inputs[2*i][DATAW-1]}}, inputs[2*i]};
      assign b_ext = {{1{inputs[2*i+1][DATAW-1]}}, inputs[2*i+1]};

      // Adder outputs
      logic [DATAW:0] result;
      logic           cout_unused;
      logic           overflow_unused;
      logic           zero_unused;

      adder_subtractor #(.WIDTH(DATAW+1)) u_add (
        .a       (a_ext),
        .b       (b_ext),
        .sub     (1'b0),            // Always addition
        .result  (result),
        .cout    (cout_unused),
        .overflow(overflow_unused),
        .zero    (zero_unused)
      );

      assign outputs[i] = result;
    end
  endgenerate

endmodule