`timescale 1ns/1ps

module tb_adder_subtractor;

  parameter int WIDTH = 8;
  
  logic [WIDTH-1:0] a;
  logic [WIDTH-1:0] b;
  logic             sub;
  logic [WIDTH-1:0] result;
  logic             cout;
  logic             overflow;
  logic             zero;

  // DUT instantiation
  adder_subtractor #(.WIDTH(WIDTH)) dut (
    .a(a),
    .b(b),
    .sub(sub),
    .result(result),
    .cout(cout),
    .overflow(overflow),
    .zero(zero)
  );

  // Reference model
  logic [WIDTH:0]   expected_unsigned;
  logic signed [WIDTH-1:0] a_signed, b_signed, expected_signed;
  logic expected_overflow, expected_cout, expected_zero;

  task automatic check_result(
    input string test_name,
    input logic is_signed
  );
    if (is_signed) begin
      // Signed arithmetic check
      a_signed = $signed(a);
      b_signed = $signed(b);
      expected_signed = sub ? (a_signed - b_signed) : (a_signed + b_signed);
      
      // Check overflow for signed
      if (sub) begin
        // Subtraction overflow: pos - neg = neg or neg - pos = pos
        expected_overflow = (a[WIDTH-1] != b[WIDTH-1]) && 
                           (result[WIDTH-1] != a[WIDTH-1]);
      end else begin
        // Addition overflow: pos + pos = neg or neg + neg = pos
        expected_overflow = (a[WIDTH-1] == b[WIDTH-1]) && 
                           (result[WIDTH-1] != a[WIDTH-1]);
      end
      
      expected_zero = (expected_signed == 0);
      
      if ($signed(result) !== expected_signed) begin
        $error("[%s] FAIL: result=%0d, expected=%0d", 
               test_name, $signed(result), expected_signed);
      end else if (overflow !== expected_overflow) begin
        $error("[%s] FAIL: overflow=%b, expected=%b", 
               test_name, overflow, expected_overflow);
      end else if (zero !== expected_zero) begin
        $error("[%s] FAIL: zero=%b, expected=%b", 
               test_name, zero, expected_zero);
      end else begin
        $display("[%s] PASS: %0d %s %0d = %0d, overflow=%b, zero=%b", 
                 test_name, $signed(a), sub?"−":"+", $signed(b), 
                 $signed(result), overflow, zero);
      end
      
    end else begin
      // Unsigned arithmetic check
      expected_unsigned = sub ? ({1'b0,a} - {1'b0,b}) : ({1'b0,a} + {1'b0,b});
      expected_cout = sub ? (a >= b) : expected_unsigned[WIDTH];
      expected_zero = (expected_unsigned[WIDTH-1:0] == 0);
      
      if (result !== expected_unsigned[WIDTH-1:0]) begin
        $error("[%s] FAIL: result=%0d, expected=%0d", 
               test_name, result, expected_unsigned[WIDTH-1:0]);
      end else if (cout !== expected_cout) begin
        $error("[%s] FAIL: cout=%b, expected=%b", 
               test_name, cout, expected_cout);
      end else if (zero !== expected_zero) begin
        $error("[%s] FAIL: zero=%b, expected=%b", 
               test_name, zero, expected_zero);
      end else begin
        $display("[%s] PASS: %0d %s %0d = %0d, cout=%b, zero=%b", 
                 test_name, a, sub?"−":"+", b, result, cout, zero);
      end
    end
  endtask

  initial begin
    $display("=== Starting Adder/Subtractor Testbench (WIDTH=%0d) ===\n", WIDTH);
    
    // ========== UNSIGNED TESTS ==========
    $display("--- UNSIGNED ADDITION TESTS ---");
    
    // Basic addition
    sub = 0; a = 8'd50; b = 8'd30;
    #10 check_result("Unsigned: 50+30", 0);
    
    // Addition with overflow
    sub = 0; a = 8'd200; b = 8'd100;
    #10 check_result("Unsigned: 200+100 (overflow)", 0);
    
    // Max + 1
    sub = 0; a = 8'd255; b = 8'd1;
    #10 check_result("Unsigned: 255+1 (overflow)", 0);
    
    // Zero result
    sub = 0; a = 8'd0; b = 8'd0;
    #10 check_result("Unsigned: 0+0 (zero)", 0);
    
    $display("\n--- UNSIGNED SUBTRACTION TESTS ---");
    
    // Basic subtraction
    sub = 1; a = 8'd100; b = 8'd30;
    #10 check_result("Unsigned: 100−30", 0);
    
    // Subtraction with borrow (a < b)
    sub = 1; a = 8'd50; b = 8'd100;
    #10 check_result("Unsigned: 50−100 (borrow)", 0);
    
    // Equal operands
    sub = 1; a = 8'd75; b = 8'd75;
    #10 check_result("Unsigned: 75−75 (zero)", 0);
    
    // Zero minus something
    sub = 1; a = 8'd0; b = 8'd50;
    #10 check_result("Unsigned: 0−50", 0);
    
    // ========== SIGNED TESTS ==========
    $display("\n--- SIGNED ADDITION TESTS ---");
    
    // Positive + Positive (no overflow)
    sub = 0; a = 8'sd50; b = 8'sd30;
    #10 check_result("Signed: 50+30", 1);
    
    // Positive + Positive (overflow)
    sub = 0; a = 8'sd100; b = 8'sd50;
    #10 check_result("Signed: 100+50 (overflow)", 1);
    
    // Max positive + 1
    sub = 0; a = 8'sd127; b = 8'sd1;
    #10 check_result("Signed: 127+1 (overflow)", 1);
    
    // Negative + Negative (no overflow)
    sub = 0; a = -8'sd50; b = -8'sd30;
    #10 check_result("Signed: −50+(−30)", 1);
    
    // Negative + Negative (overflow)
    sub = 0; a = -8'sd100; b = -8'sd50;
    #10 check_result("Signed: −100+(−50) (overflow)", 1);
    
    // Min negative − 1
    sub = 0; a = -8'sd128; b = -8'sd1;
    #10 check_result("Signed: −128+(−1) (overflow)", 1);
    
    // Positive + Negative (no overflow possible)
    sub = 0; a = 8'sd100; b = -8'sd50;
    #10 check_result("Signed: 100+(−50)", 1);
    
    // Negative + Positive (no overflow possible)
    sub = 0; a = -8'sd100; b = 8'sd50;
    #10 check_result("Signed: −100+50", 1);
    
    // Result is zero
    sub = 0; a = 8'sd50; b = -8'sd50;
    #10 check_result("Signed: 50+(−50) (zero)", 1);
    
    $display("\n--- SIGNED SUBTRACTION TESTS ---");
    
    // Positive − Positive (no overflow)
    sub = 1; a = 8'sd100; b = 8'sd30;
    #10 check_result("Signed: 100−30", 1);
    
    // Positive − Negative (overflow possible)
    sub = 1; a = 8'sd100; b = -8'sd50;
    #10 check_result("Signed: 100−(−50) (overflow)", 1);
    
    // Max − (−1)
    sub = 1; a = 8'sd127; b = -8'sd1;
    #10 check_result("Signed: 127−(−1) (overflow)", 1);
    
    // Negative − Positive (overflow possible)
    sub = 1; a = -8'sd100; b = 8'sd50;
    #10 check_result("Signed: −100−50 (overflow)", 1);
    
    // Min − 1
    sub = 1; a = -8'sd128; b = 8'sd1;
    #10 check_result("Signed: −128−1 (overflow)", 1);
    
    // Negative − Negative (no overflow)
    sub = 1; a = -8'sd50; b = -8'sd30;
    #10 check_result("Signed: −50−(−30)", 1);
    
    // Equal operands
    sub = 1; a = 8'sd75; b = 8'sd75;
    #10 check_result("Signed: 75−75 (zero)", 1);
    
    $display("\n--- EDGE CASES ---");
    
    // All bits set
    sub = 0; a = 8'hFF; b = 8'hFF;
    #10 check_result("Edge: 0xFF+0xFF", 0);
    
    // Alternating bits
    sub = 0; a = 8'hAA; b = 8'h55;
    #10 check_result("Edge: 0xAA+0x55", 0);
    
    // One operand zero
    sub = 0; a = 8'd0; b = 8'd123;
    #10 check_result("Edge: 0+123", 0);
    
    // Both operands max signed positive
    sub = 0; a = 8'sd127; b = 8'sd127;
    #10 check_result("Edge: 127+127 (overflow)", 1);
    
    // Both operands max signed negative
    sub = 0; a = -8'sd128; b = -8'sd128;
    #10 check_result("Edge: −128+(−128) (overflow)", 1);
    
    $display("\n=== Testbench Complete ===");
    $finish;
  end

endmodule