// ========== Generate sigma_c ==========
logic [1:0] sigma_c [0:VECTOR_SIZE-1];
// sigma_c_inverse: Result of sigma_new * sigma_f_inv (2-bit: 00=0, 01=+1, 11=-1)
logic [1:0] sigma_r [0:VECTOR_SIZE-1];
generate
  for (genvar i = 0; i < VECTOR_SIZE; i++) begin : GEN_SIGMA_C
    assign sigma_c[i] = sigma_f[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00; // It means that if sigma_f is 1, then sigma_c is +1(2'b01)
                                                                             // or -1(2'b10) based on sigma_new, else 0
  
  end : GEN_SIGMA_C
endgenerate
// ========== Generate sigma_c_inverse ==========
generate
  for (genvar i = 0; i < VECTOR_SIZE; i++) begin : GEN_SIGMA_R
    assign sigma_r[i] = sigma_f_inv[i] ? (sigma_new[i] ? 2'b01 : 2'b10) : 2'b00;// It means that if sigma_f_inv is 1, then sigma_c is +1(2'b01) 
                                                                                // or -1(2'b10) based on sigma_new, else 0
  end : GEN_SIGMA_R
endgenerate