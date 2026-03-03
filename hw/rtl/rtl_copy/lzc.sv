module lzc #(
    parameter WIDTH = 256
)(
    input  logic [WIDTH-1:0] bitstream,
    output logic [$clog2(WIDTH)-1:0] positions [WIDTH-1:0],
    output logic [WIDTH-1:0] valid,
    output int num_ones
);
int write_idx;
    always_comb begin
        // Separate passes: first mark valid, then compact
        write_idx = 0;
        
        // Initialize outputs
        valid = '0;
        positions = '{default: '0};
        
        // Single pass: check each bit and write positions sequentially
        for (int i = 0; i < WIDTH; i++) begin
            if (bitstream[i]) begin
                positions[write_idx] = i;  // Or (WIDTH-1-i) for MSB-first
                valid[write_idx] = 1'b1;
                write_idx++;
            end
        end
        
        num_ones = write_idx;
    end
endmodule