`timescale 1ns/1ps

module tb_MatMul;

  // --- Match DUT params ---
  parameter int MEM_BANDWIDTH    = 4096;
  parameter int VECTOR_SIZE      = 256;
  parameter int J_ELEMENT_WIDTH  = 4;
  parameter int J_COLS_PER_READ  = MEM_BANDWIDTH / (VECTOR_SIZE * J_ELEMENT_WIDTH); // = 4
  parameter int J_COLS_PER_CLK   = J_COLS_PER_READ;
  parameter int NUM_J_CHUNKS     = VECTOR_SIZE / J_COLS_PER_READ;                    // = 64
  parameter int INT_RESULT_WIDTH = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH + 1;        // +1 headroom
  // UPDATED: +1 sign headroom so J=15 fits (max 983,040)
  parameter int ENERGY_WIDTH     = J_ELEMENT_WIDTH + 2*$clog2(VECTOR_SIZE) + 1;      // = 21

  // --- I/O ---
  logic clk, rst_n, start;
  logic [VECTOR_SIZE-1:0] sigma;                           // our spec: 1=add, 0=sub
  logic [VECTOR_SIZE-1:0] sigma_dut;                       // what DUT receives
  logic [J_ELEMENT_WIDTH-1:0] J_Matrix_chunk [0:VECTOR_SIZE-1][0:J_COLS_PER_READ-1];
  logic [ENERGY_WIDTH-1:0]    Energy_previous;

  assign sigma_dut = sigma;
  
  // --- DUT ---
  MatMul #(
    .MEM_BANDWIDTH   (MEM_BANDWIDTH),
    .VECTOR_SIZE     (VECTOR_SIZE),
    .J_ELEMENT_WIDTH (J_ELEMENT_WIDTH)
  ) dut (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (start),
    .sigma          (sigma_dut),
    .J_Matrix_chunk (J_Matrix_chunk),
    .Energy_previous(Energy_previous)
  );

  // --- Clock / Reset ---
  always #5 clk = ~clk; // 100 MHz

  initial begin
    clk = 0; rst_n = 0; start = 0;
    sigma = '0;
    Energy_previous = {ENERGY_WIDTH{1'b1}}; // prevent early stop
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // Fill the active chunk with a constant J value (1 or 15)
  task automatic fill_J_const(input logic [J_ELEMENT_WIDTH-1:0] JVAL);
    int r, c;
    for (r = 0; r < VECTOR_SIZE; r++)
      for (c = 0; c < J_COLS_PER_READ; c++)
        J_Matrix_chunk[r][c] = JVAL;
  endtask

  // Sigma patterns (our spec: 1=add, 0=sub)
  task automatic set_sigma_all0(); sigma = '0; endtask
  task automatic set_sigma_all1(); sigma = {VECTOR_SIZE{1'b1}}; endtask
  task automatic set_sigma_1010();
    int i; for (i = 0; i < VECTOR_SIZE; i++) sigma[i] = (i % 2 == 0); // LSB=1 → 1010…
  endtask

  // Golden energy for constant-J matrix:
  // dot = (2*C1 - N) * JVAL ;  E = (2*C1 - N)^2 * JVAL This is an alternative method to find energy without calculating the full dot products(if all j values are same)
  function automatic longint signed golden_energy_constJ(
      input logic [VECTOR_SIZE-1:0] sig,
      input int unsigned JVAL
  );
    int C1, i; longint signed term;
    C1 = 0; for (i = 0; i < VECTOR_SIZE; i++) C1 += (sig[i] ? 1 : 0);
    term = (2*C1 - VECTOR_SIZE);
    return term * term * JVAL;
  endfunction

  function automatic logic signed [ENERGY_WIDTH-1:0] truncE(input longint signed x);
    truncE = x; // 2's complement truncation to ENERGY_WIDTH
  endfunction

  // Capture last running energy
  //logic signed [ENERGY_WIDTH-1:0] last_energy;
  //always @(posedge clk) if (dut.start_enable_prev) last_energy <= dut.Energy_next;

  // One deterministic run
  task automatic run_case(input string name,
                          input logic [J_ELEMENT_WIDTH-1:0] JVAL,
                          input int pattern_sel); // 0=all0, 1=all1, 2=1010
    longint signed E_ref_full; logic signed [ENERGY_WIDTH-1:0] E_ref;
    case (pattern_sel)
      0: set_sigma_all0();
      1: set_sigma_all1();
      default: set_sigma_1010();
    endcase
    fill_J_const(JVAL);
    E_ref_full = golden_energy_constJ(sigma, JVAL);
    E_ref      = truncE(E_ref_full);

    @(posedge clk); start = 1; @(posedge clk); start = 0;

    // Wait run complete
    wait (dut.start_enable);
    while (dut.start_enable) @(posedge clk);// proceed with the rest of the task after 1 CLK period of start_enable being low

    if (dut.Energy_next === E_ref)
      $display("[PASS] %-12s  J=%0d  DUT=%0d  EXP=%0d", name, JVAL, dut.Energy_next , E_ref);
    else
      $error  ("[FAIL] %-12s  J=%0d  DUT=%0d  EXP=%0d", name, JVAL, dut.Energy_next , E_ref);
  endtask

  // === Stimulus ===
  initial begin
    $display("=== MatMul simple self-check (const J, simple sigma) ===");
    @(posedge rst_n); @(posedge clk);

    // J=1
    run_case("all0_J1" , 4'd1 , 0);
    run_case("all1_J1" , 4'd1 , 1);
    run_case("alt_J1"  , 4'd1 , 2);

    // J=15
    run_case("all0_J15", 4'd15, 0);
    run_case("all1_J15", 4'd15, 1);
    run_case("alt_J15" , 4'd15, 2);

    $display("=== Done ===");
    $finish;
  end

  // === VCD ===
  initial begin
    $dumpfile("MatMul_tb.vcd");
    $dumpvars(0, tb_MatMul);
  end

endmodule
