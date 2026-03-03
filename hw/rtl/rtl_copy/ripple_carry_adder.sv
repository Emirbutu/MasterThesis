module ripple_carry_adder #(
  parameter int WIDTH = 8
)(
  input  logic [WIDTH-1:0] a,
  input  logic [WIDTH-1:0] b,
  input  logic             cin,
  output logic [WIDTH-1:0] sum,
  output logic             cout
);
  logic [WIDTH:0]   carry;
  assign carry[0] = cin;

  genvar i;
  generate
    for (i = 0; i < WIDTH; i++) begin : GEN_FA
      full_adder u_fa (
        .a   (a[i]),
        .b   (b[i]),
        .cin (carry[i]),
        .sum (sum[i]),
        .cout(carry[i+1])
      );
    end
  endgenerate

  assign cout = carry[WIDTH];

endmodule
