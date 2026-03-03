`include "include/registers.svh"

// adder_tree.sv
// Configurable adder tree: fully pipelined or fully combinational.
// Uses adder_tree_layer with your adder_subtractor inside.
// Supports NUM_INPUTS = 1 (pass-through) and any power of 2.

module adder_tree #(
  parameter bit                PIPED           = 0,
  parameter int                NUM_INPUTS      = 8,    // Must be power of 2 (or 1)
  parameter int                INPUT_WIDTH     = 8,
  parameter int                LEVELS          = (NUM_INPUTS > 1) ? $clog2(NUM_INPUTS) : 0,
  // Bit mask selecting which stage boundaries get registered when PIPED==1.
  // bit[0]       -> register inputs before layer 0
  // bit[i]       -> register after layer i-1 (for i = 1 to LEVELS-1)
  // bit[LEVELS]  -> register final output
  parameter logic [LEVELS:0]   PIPE_STAGE_MASK = '0,
  // Output width = INPUT_WIDTH + ceil(log2(NUM_INPUTS))
  parameter int                OUTPUT_WIDTH    = INPUT_WIDTH + LEVELS
)(
  input  logic                            clk,
  input  logic                            rst_n,
  input  logic signed [INPUT_WIDTH-1:0]   inputs [0:NUM_INPUTS-1],
  input  logic                            start,
  output logic signed [OUTPUT_WIDTH-1:0]  sum_out,
  output logic                            start_out
);

  // -------- Compile-time checks --------
  initial begin
    if (NUM_INPUTS < 1)
      $fatal(1, "adder_tree expects NUM_INPUTS >= 1.");
    if (NUM_INPUTS > 1 && (NUM_INPUTS & (NUM_INPUTS - 1)) != 0)
      $fatal(1, "adder_tree expects NUM_INPUTS to be a power of 2 (or 1).");
    if (OUTPUT_WIDTH < INPUT_WIDTH + LEVELS)
      $error("OUTPUT_WIDTH(%0d) < required(%0d).", OUTPUT_WIDTH, INPUT_WIDTH + LEVELS);
  end

  // -------- Trivial case: NUM_INPUTS == 1 --------
  generate
    if (NUM_INPUTS == 1) begin : GEN_TRIVIAL

      // Sign-extend single input to output width
      logic signed [OUTPUT_WIDTH-1:0] sum_pre;
      logic                           start_pre;

      assign sum_pre   = {{(OUTPUT_WIDTH - INPUT_WIDTH){inputs[0][INPUT_WIDTH-1]}}, inputs[0]};
      assign start_pre = start;

      // Use PIPE_STAGE_MASK[0] to decide if output is registered
      if (PIPED && PIPE_STAGE_MASK[0]) begin : GEN_REG
        `FF(sum_out,   sum_pre,   '0, clk, rst_n)
        `FF(start_out, start_pre, '0, clk, rst_n)
      end else begin : GEN_WIRE
        assign sum_out   = sum_pre;
        assign start_out = start_pre;
      end

    end else begin : GEN_TREE
      // -------- Non-trivial case: NUM_INPUTS >= 2 --------

      // Start signal pipeline array
      logic start_stage [0:LEVELS+1];
      assign start_stage[0] = start;

      // ======== COMBINATIONAL TREE (PIPED == 0) ========
      if (PIPED == 0) begin : GEN_COMB_TREE

        for (genvar i = 0; i < LEVELS; i++) begin : LAYER
          localparam int W_IN      = INPUT_WIDTH + i;
          localparam int W_OUT     = W_IN + 1;
          localparam int COUNT_IN  = (NUM_INPUTS >> i);
          localparam int COUNT_OUT = (NUM_INPUTS >> (i + 1));

          logic signed [W_IN-1:0]  in_i  [0:COUNT_IN-1];
          logic signed [W_OUT-1:0] out_i [0:COUNT_OUT-1];

          // Bind inputs
          if (i == 0) begin : SRC0
            for (genvar m = 0; m < COUNT_IN; m++) begin : BIND0
              assign in_i[m] = inputs[m];
            end
          end else begin : SRCN
            for (genvar m = 0; m < COUNT_IN; m++) begin : BINDN
              assign in_i[m] = LAYER[i-1].out_i[m];
            end
          end

          // Instantiate adder layer
          adder_tree_layer #(
            .INPUTS_AMOUNT (COUNT_IN),
            .DATAW         (W_IN)
          ) u_layer (
            .inputs  (in_i),
            .outputs (out_i)
          );
        end

        // Final output (combinational, no registers)
        assign sum_out   = GEN_COMB_TREE.LAYER[LEVELS-1].out_i[0];
        assign start_out = start;

      // ======== PIPELINED TREE (PIPED == 1) ========
      end else begin : GEN_PIPE_TREE

        // Stage 0: optional register before layer 0
        logic signed [INPUT_WIDTH-1:0] stage0_data [0:NUM_INPUTS-1];

        if (PIPE_STAGE_MASK[0]) begin : GEN_STAGE0_REG
          for (genvar m = 0; m < NUM_INPUTS; m++) begin : REG
            `FF(stage0_data[m], inputs[m], '0, clk, rst_n)
          end
          `FF(start_stage[1], start_stage[0], '0, clk, rst_n)
        end else begin : GEN_STAGE0_WIRE
          for (genvar m = 0; m < NUM_INPUTS; m++) begin : WIRE
            assign stage0_data[m] = inputs[m];
          end
          assign start_stage[1] = start_stage[0];
        end

        // Tree layers with optional pipeline stages
        for (genvar i = 0; i < LEVELS; i++) begin : LAYER_PIPE
          localparam int W_IN      = INPUT_WIDTH + i;
          localparam int W_OUT     = W_IN + 1;
          localparam int COUNT_IN  = (NUM_INPUTS >> i);
          localparam int COUNT_OUT = (NUM_INPUTS >> (i + 1));

          logic signed [W_IN-1:0]  in_i      [0:COUNT_IN-1];
          logic signed [W_OUT-1:0] out_i     [0:COUNT_OUT-1];
          logic signed [W_OUT-1:0] stage_out [0:COUNT_OUT-1];

          // Bind inputs to this layer
          if (i == 0) begin : SRC_STAGE0
            for (genvar m = 0; m < COUNT_IN; m++) begin : BIND_STAGE0
              assign in_i[m] = stage0_data[m];
            end
          end else begin : SRC_STAGE
            for (genvar m = 0; m < COUNT_IN; m++) begin : BIND_STAGE
              assign in_i[m] = LAYER_PIPE[i-1].stage_out[m];
            end
          end

          // Instantiate adder layer
          adder_tree_layer #(
            .INPUTS_AMOUNT (COUNT_IN),
            .DATAW         (W_IN)
          ) u_layer_pipe (
            .inputs  (in_i),
            .outputs (out_i)
          );

          // Optional pipeline register after this layer
          // bit[i+1] controls register after layer i
          if (PIPE_STAGE_MASK[i + 1]) begin : REG_STAGE
            for (genvar n = 0; n < COUNT_OUT; n++) begin : REG
              `FF(stage_out[n], out_i[n], '0, clk, rst_n)
            end
            `FF(start_stage[i + 2], start_stage[i + 1], '0, clk, rst_n)
          end else begin : WIRE_STAGE
            for (genvar n = 0; n < COUNT_OUT; n++) begin : WIRE
              assign stage_out[n] = out_i[n];
            end
            assign start_stage[i + 2] = start_stage[i + 1];
          end
        end

        // Final output from last layer
        assign sum_out   = GEN_PIPE_TREE.LAYER_PIPE[LEVELS-1].stage_out[0];
        assign start_out = start_stage[LEVELS + 1];

      end // GEN_PIPE_TREE

    end // GEN_TREE
  endgenerate

endmodule