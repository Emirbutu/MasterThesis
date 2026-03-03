// Copyright 2025 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`timescale 1ns / 1ps

module tb_adder_tree_layer;

  // ---- Parameters to test ----
  localparam int INPUTS_AMOUNT = 8;   // must be even
  localparam int DATAW         = 8;   // signed data width (two's complement)

  // ---- DUT I/O ----
  logic [DATAW-1:0] in_vec [INPUTS_AMOUNT];
  logic [DATAW:0]   out_vec[INPUTS_AMOUNT/2];

  // ---- DUT ----
  adder_tree_layer #(
    .INPUTS_AMOUNT(INPUTS_AMOUNT),
    .DATAW(DATAW)
  ) dut (
    .inputs (in_vec),
    .outputs(out_vec)
  );

  // ---- Helper: compute expected pairwise sums (signed) ----
  function automatic logic signed [DATAW:0] exp_sum(
      input logic [DATAW-1:0] a,
      input logic [DATAW-1:0] b
  );
    exp_sum = $signed(a) + $signed(b);
  endfunction

  // ---- Drive a signed value into in_vec[idx] conveniently ----
  task automatic drive_signed(input int idx, input int signed val);
    // Truncates to DATAW bits in two's complement
    in_vec[idx] = logic'(val[DATAW-1:0]);
  endtask

  // ---- Check all output pairs ----
  task automatic check_outputs(string tag);
    for (int i = 0; i < INPUTS_AMOUNT/2; i++) begin
      logic signed [DATAW:0] want = exp_sum(in_vec[2*i], in_vec[2*i+1]);
      assert (out_vec[i] === want)
        else $fatal(1, "[%s] Mismatch @pair %0d: got %0d, expected %0d",
                    tag, i, $signed(out_vec[i]), want);
    end
    $display("[%0t] %s: PASS", $time, tag);
  endtask

  // ---- Randomize inputs uniformly over DATAW-bit signed range ----
  task automatic randomize_inputs();
    for (int k = 0; k < INPUTS_AMOUNT; k++) begin
      // random DATAW-bit pattern; interpret as signed in DUT
      in_vec[k] = $urandom();
    end
  endtask

  initial begin
    // Basic sanity (even input count)
    if (INPUTS_AMOUNT % 2) $fatal("INPUTS_AMOUNT must be even.");

    // 1) All zeros
    foreach (in_vec[i]) in_vec[i] = '0;
    #1; check_outputs("all_zeros");

    // 2) Directed signed patterns (covers corners)
    drive_signed(0,  10); drive_signed(1,  -3);   // 7
    drive_signed(2, 127); drive_signed(3,   1);   // 128 (fits in DATAW+1)
    drive_signed(4, -128);drive_signed(5,  -1);   // -129 (fits in DATAW+1)
    drive_signed(6,   50);drive_signed(7, -50);   // 0
    #1; check_outputs("directed");

    // 3) A few random trials
    for (int t = 0; t < 50; t++) begin
      randomize_inputs();
      #1; check_outputs($sformatf("random_%0d", t));
    end

    $display("All tests completed successfully.");
    $finish;
  end

initial begin
  $dumpfile("tb_adder_tree_layer.vcd");
  $dumpvars(0, tb_adder_tree_layer);
  for (int i=0; i<INPUTS_AMOUNT; i++)        $dumpvars(0, tb_adder_tree_layer.in_vec[i]);
  for (int i=0; i<INPUTS_AMOUNT/2; i++)      $dumpvars(0, tb_adder_tree_layer.out_vec[i]);
end

endmodule
