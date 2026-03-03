module generic_mux #(
  parameter int NUM_INPUTS  = 2,  // Non-power-of-2
  parameter int DATA_WIDTH  = 5,
  parameter int SEL_WIDTH   = $clog2(NUM_INPUTS)
)(
  input  logic [DATA_WIDTH-1:0] inputs [0:NUM_INPUTS-1],
  input  logic [SEL_WIDTH-1:0]  sel,
  output logic [DATA_WIDTH-1:0] out
);


  assign out = (sel < NUM_INPUTS) ? inputs[sel] : inputs[0];

endmodule