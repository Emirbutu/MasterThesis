// Copyright 2026 KU Leuven.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Synthesis SRAM wrapper.
// Interface is aligned with tc_sram_eth/tc_sram-style generic SRAM wrappers.
 
`ifndef STATIC_ASSERT
`define STATIC_ASSERT(cond, msg) \
    initial begin \
        if (!(cond)) begin \
            $error("%s", msg); \
        end \
    end
`endif

// Macro pin mapping for ts1n28hpcpuhdhvtb64x256m1swbso_170a (TSMC28 64x256 SRAM)
// Pin descriptions from Liberty file:
//   CLK: Clock input
//   CEB: Chip enable (active low)
//   WEB: Write enable (active low)
//   A[5:0]: Address bus (6 bits for 256 words)
//   D[255:0]: Data input (256 bits)
//   Q[255:0]: Data output (256 bits)
//   BWEB[255:0]: Bit write enable (active low, per-bit)
//   RTSEL[1:0]: Read timing select (tie to 2'b10 for normal operation)
//   WTSEL[1:0]: Write timing select (tie to 2'b01 for normal operation)
//   SD: Shutdown (tie low for normal operation)
//   SLP: Sleep mode (tie low for normal operation)
//   BIST: Built-in self test (tie low for normal operation)
`define TSMC28_PORT_CONNECT \
    .CLK(CLK), .CEB(CEB), .WEB(WEB), .A(A), .D(D), .Q(Q), \
    .BWEB(BWEB), .RTSEL(2'b10), .WTSEL(2'b00), \
    .SD('0), .SLP('0), .BIST('0)

module tc_sram_syn #(
    parameter int unsigned NumWords     = 32'd1024,
    parameter int unsigned DataWidth    = 32'd128,
    parameter int unsigned ByteWidth    = 32'd8,
    parameter int unsigned NumPorts     = 32'd1,
    parameter int unsigned Latency      = 32'd1,
    parameter              SimInit      = "none",
    parameter bit          PrintSimCfg  = 1'b0,
    parameter              ImplKey      = "none",
    parameter int unsigned AddrWidth    = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
    parameter int unsigned BeWidth      = (DataWidth + ByteWidth - 32'd1) / ByteWidth,
    parameter              CdeFileInit  = "TS1N28HPCPUHDHVTB64X256M1SWBSO_initial.cde",
    parameter type         addr_t       = logic [AddrWidth-1:0],
    parameter type         data_t       = logic [DataWidth-1:0],
    parameter type         be_t         = logic [BeWidth-1:0]
) (
    input  logic                 clk_i,
    input  logic                 rst_ni,
    input  logic  [NumPorts-1:0] req_i,
    input  logic  [NumPorts-1:0] we_i,
    input  addr_t [NumPorts-1:0] addr_i,
    input  data_t [NumPorts-1:0] wdata_i,
    input  be_t   [NumPorts-1:0] be_i,
    output data_t [NumPorts-1:0] rdata_o
);

    logic unused_rst_ni;
    assign unused_rst_ni = rst_ni;

    // Stage the request signals on the falling edge so the macro sees a full
    // half-cycle of setup time before the next rising edge.
    logic  [NumPorts-1:0] req_q;
    logic  [NumPorts-1:0] we_q;
    addr_t [NumPorts-1:0] addr_q;
    data_t [NumPorts-1:0] wdata_q;
    be_t   [NumPorts-1:0] be_q;

    always_ff @(negedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            req_q   <= '0;
            we_q    <= '0;
            addr_q  <= '0;
            wdata_q <= '0;
            be_q    <= '0;
        end else begin
            req_q   <= req_i;
            we_q    <= we_i;
            addr_q  <= addr_i;
            wdata_q <= wdata_i;
            be_q    <= be_i;
        end
    end

    // TSMC28 SRAM macro interface signals
    wire CLK;                          // Clock input
    wire CEB;                          // Chip enable (active low)
    wire WEB;                          // Write enable (active low)
    wire [AddrWidth-1:0] A;            // Address bus
    wire [DataWidth-1:0] D;            // Data input
    wire [DataWidth-1:0] Q;            // Data output
    wire [DataWidth-1:0] BWEB;         // Bit write enable (active low)

    assign CLK = clk_i;
    assign CEB = ~req_q[0];
    assign WEB = ~we_q[0];
    assign A = addr_q[0];
    assign D = wdata_q[0];
    assign rdata_o[0] = Q;

    for (genvar i = 0; i < BeWidth; i++) begin : gen_be
        localparam int unsigned ByteStart = i * ByteWidth;
        localparam int unsigned ByteEnd = (ByteStart + ByteWidth > DataWidth) ? DataWidth : (ByteStart + ByteWidth);
        localparam int unsigned ActualByteWidth = ByteEnd - ByteStart;
        assign BWEB[ByteStart +: ActualByteWidth] = {ActualByteWidth{~be_q[0][i]}};
    end

    generate
        if ((DataWidth == 256) && (NumWords == 64)) begin : gen_64x256
`ifdef SYNTHESIS
            // Genus resolves the SRAM via .lib cell name; do not parameterize
            // the macro instance in synthesis, otherwise it becomes an
            // unresolved specialized reference.
            TS1N28HPCPUHDHVTB64X256M1SWBSO i_sp_ram (`TSMC28_PORT_CONNECT);
`else
            TS1N28HPCPUHDHVTB64X256M1SWBSO #(
                .cdeFileInit(CdeFileInit)
            ) i_sp_ram (`TSMC28_PORT_CONNECT);
`endif
        end else begin : gen_invalid_cfg
            initial $error("Unsupported tc_sram_syn geometry: NumWords=%0d DataWidth=%0d. Supported: 64x256 (64 words, 256 bits/word).", NumWords, DataWidth);
        end
    endgenerate

    // Genus parser in this flow can choke on macro-based static asserts.
    // Keep the wrapper synthesizable and rely on generate-time checks above.

`ifdef TARGET_LOG_INSTS
    initial begin
        $info("[INFO] tc_sram_syn: instantiated %0dx%0d SRAM macro", NumWords, DataWidth);
    end
`endif

endmodule
