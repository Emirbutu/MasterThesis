`timescale 1ns/1ps

module tb_MatMul;

  // ===============================================================
  // === Parameters (exactly same defaults as in MatMul module) ===
  // ===============================================================
  parameter int MEM_BANDWIDTH   = 4096;        // bits per clock
  parameter int VECTOR_SIZE     = 256;         // sigma vector length
  parameter int J_ELEMENT_WIDTH = 4;           // bit width per J element
  parameter int J_COLS_PER_READ = MEM_BANDWIDTH / (VECTOR_SIZE * J_ELEMENT_WIDTH);
  parameter int J_COLS_PER_CLK  = J_COLS_PER_READ;
  parameter int NUM_J_CHUNKS    = VECTOR_SIZE / J_COLS_PER_READ;
  parameter int INT_RESULT_WIDTH = $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH;
  parameter int ENERGY_WIDTH     = $clog2(VECTOR_SIZE) + $clog2(VECTOR_SIZE) + J_ELEMENT_WIDTH;

  // ===============================================================
  // === DUT I/O Signals ===========================================
  // ===============================================================
  logic clk;
  logic rst_n;
  logic start;
  logic [VECTOR_SIZE-1:0] sigma;
  logic [J_ELEMENT_WIDTH-1:0] J_Matrix_chunk [0:VECTOR_SIZE-1][0:J_COLS_PER_READ-1];
  logic [ENERGY_WIDTH-1:0] Energy_previous;

  // ===============================================================
  // === DUT Instance ==============================================
  // ===============================================================
  MatMul #(
    .MEM_BANDWIDTH(MEM_BANDWIDTH),
    .VECTOR_SIZE(VECTOR_SIZE),
    .J_ELEMENT_WIDTH(J_ELEMENT_WIDTH)
  ) dut (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .sigma(sigma),
    .J_Matrix_chunk(J_Matrix_chunk),
    .Energy_previous(Energy_previous)
  );

  // ===============================================================
  // === Clock & Reset =============================================
  // ===============================================================
  always #5 clk = ~clk;  // 100 MHz clock

  initial begin
    clk = 0;
    rst_n = 0;
    start = 0;
    sigma = '0;
    Energy_previous = '0;
    repeat (3) @(posedge clk);
    rst_n = 1;
  end

  // ===============================================================
  // === Stimulus ==================================================
  // ===============================================================
  initial begin
    $display("=== Starting MatMul Simulation ===");
    @(posedge rst_n);
    @(posedge clk);

    // ------------------- TEST 1 -------------------
    sigma = {VECTOR_SIZE{1'b1}};  // all ones
    foreach (J_Matrix_chunk[i, j]) begin
      J_Matrix_chunk[i][j] = $urandom_range(0, (1<<J_ELEMENT_WIDTH)-1);
    end
    Energy_previous = 'd12345677234; // max possible value
    start = 1;
    @(posedge clk);
    start = 0;
    repeat (65) @(posedge clk);

    // ------------------- TEST 2 -------------------
    sigma = {VECTOR_SIZE{1'b0}};  // all zeros
    foreach (J_Matrix_chunk[i, j]) begin
      J_Matrix_chunk[i][j] = $urandom_range(0, (1<<J_ELEMENT_WIDTH)-1);
    end
    Energy_previous = 'd500;
    start = 1;
    @(posedge clk);
    start = 0;
    repeat (65) @(posedge clk);

    // ------------------- TEST 3 -------------------
    sigma = 256'hA5A5A5A5_F0F0F0F0_0F0F0F0F_55AA55AA_0123456789ABCDEF_FFFFFFFF_00000000_FEDCBA98;
    foreach (J_Matrix_chunk[i, j]) begin
      J_Matrix_chunk[i][j] = $urandom_range(0, (1<<J_ELEMENT_WIDTH)-1);
    end
    Energy_previous = 'd800;
    start = 1;
    @(posedge clk);
    start = 0;
    repeat (65) @(posedge clk);

    $display("=== Simulation completed successfully ===");
    $stop;
  end

  // ===============================================================
  // === Monitors & Waveform Dump ==================================
  // ===============================================================
  initial begin
    $monitor("T=%0t | start=%b | Energy_prev=%0d | sigma[0]=%b | sigma[%0d]=%b",
              $time, start, Energy_previous, sigma[0], VECTOR_SIZE-1, sigma[VECTOR_SIZE-1]);
  end

  initial begin
    $dumpfile("MatMul_tb.vcd");
    $dumpvars(0, tb_MatMul);
  end

endmodule
