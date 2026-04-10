module tc_sram #(
    parameter int unsigned NumWords   = 32'd064,
    parameter int unsigned DataWidth  = 32'd064,
    parameter int unsigned NumPorts   = 32'd1,
    parameter int unsigned Latency    = 32'd1,
    parameter bit READ_COMB           = 1'b1,
    parameter DWIDTH = 64,
    parameter DWIDTHB = DWIDTH / 8,
    parameter DEPTH = 64,
    parameter AWIDTH = $clog2(DEPTH)
) (
    input                   clk_i,
    input      [AWIDTH-1:0] addr_i,
    output     [DWIDTH-1:0] rdata_o,
    output                  valid_o,
    input      [DWIDTH-1:0] wdata_i,
    input      [DWIDTHB-1:0] be_i,
    input                   cs_i,
    input                   we_i
    
);
// Declare memory holder
reg [DWIDTH-1:0] memory [0:DEPTH-1];
localparam int unsigned RD_LAT = (Latency > 0) ? Latency : 1;

logic [DWIDTH-1:0] rdata_pipe [0:RD_LAT-1];
logic [RD_LAT-1:0] valid_pipe;
 
always @(posedge clk_i) begin 
    // Write
    if (cs_i && we_i) begin
        memory[addr_i] <= (wdata_i & be_i) | (memory[addr_i] & ~be_i);        
    end

    if (!READ_COMB) begin
        valid_pipe[0] <= cs_i && ~we_i;
        if (cs_i && ~we_i) begin
            rdata_pipe[0] <= memory[addr_i];
        end else begin
            rdata_pipe[0] <= {DWIDTH{1'bX}};
        end

        for (int i = 1; i < RD_LAT; i++) begin
            valid_pipe[i] <= valid_pipe[i-1];
            rdata_pipe[i] <= rdata_pipe[i-1];
        end
    end
end 

generate
    if (READ_COMB) begin : g_read_comb
        assign rdata_o = (cs_i && ~we_i) ? memory[addr_i] : {DWIDTH{1'bX}};
        assign valid_o = cs_i && ~we_i;
    end else begin : g_read_sync
        assign rdata_o = rdata_pipe[RD_LAT-1];
        assign valid_o = valid_pipe[RD_LAT-1];
    end
endgenerate
 
endmodule