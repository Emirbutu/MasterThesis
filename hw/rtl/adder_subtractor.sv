module adder_subtractor #(
  parameter int WIDTH = 8
)(
  input  logic [WIDTH-1:0] a,
  input  logic [WIDTH-1:0] b,
  input  logic             sub,
  output logic [WIDTH-1:0] result,
  output logic             cout,
  output logic             overflow,
  output logic             zero
);

  logic [WIDTH-1:0] b_xor;
  assign b_xor = b ^ {WIDTH{sub}};

  ripple_carry_adder #(.WIDTH(WIDTH)) u_rca (
    .a   (a),
    .b   (b_xor),
    .cin (sub),
    .sum (result),
    .cout(cout)
  );

  assign overflow = (a[WIDTH-1] == b_xor[WIDTH-1]) && 
                    (result[WIDTH-1] != a[WIDTH-1]);

  assign zero = (result == {WIDTH{1'b0}});

endmodule