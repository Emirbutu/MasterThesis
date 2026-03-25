// SRAM initialization modes
    typedef enum {
        INIT_ALL_ONES,
        INIT_ADDR_PATTERN,
        INIT_RANDOM
    } init_mode_t;

    function automatic logic [SRAM_DWIDTH-1:0] read_sram_word(
        input int bank_idx,
        input int addr_idx
    );
        begin
            case (bank_idx)
                0: read_sram_word = sram_banks[0].u_sram.sram[addr_idx];
                1: read_sram_word = sram_banks[1].u_sram.sram[addr_idx];
                2: read_sram_word = sram_banks[2].u_sram.sram[addr_idx];
                3: read_sram_word = sram_banks[3].u_sram.sram[addr_idx];
            //    4: read_sram_word = sram_banks[4].u_sram.memory[addr_idx];
            //    5: read_sram_word = sram_banks[5].u_sram.memory[addr_idx];
            //    6: read_sram_word = sram_banks[6].u_sram.memory[addr_idx];
            //    7: read_sram_word = sram_banks[7].u_sram.memory[addr_idx];
                default: read_sram_word = '0;
            endcase
        end
    endfunction

    function automatic logic [SCALING_BIT-1:0] select_hscaling(input int idx);
        begin
            case (idx)
                0: select_hscaling = 'd1;
                1: select_hscaling = (SCALING_BIT >= 2) ? 'd2 : 'd1;
                2: select_hscaling = (SCALING_BIT >= 3) ? 'd4 : 'd1;
                3: select_hscaling = (SCALING_BIT >= 4) ? 'd8 : 'd1;
                default: select_hscaling = (SCALING_BIT >= 5) ? 'd16 : 'd1;
            endcase
        end
    endfunction

    function automatic logic signed [ENERGY_TOTAL_BIT-1:0] scale_hbias_ref(
        input logic signed [BITH-1:0] hbias_raw,
        input logic [SCALING_BIT-1:0] hscaling_raw
    );
        localparam int HBMULBIT = BITH + SCALING_BIT - 1;
        logic signed [HBMULBIT-1:0] hbias_ext;
        logic signed [HBMULBIT-1:0] hbias_scaled;
        begin
            hbias_ext = {{(HBMULBIT-BITH){hbias_raw[BITH-1]}}, hbias_raw};
            case (hscaling_raw)
                'd1: hbias_scaled = hbias_ext;
                'd2: hbias_scaled = hbias_ext <<< 1;
                'd4: hbias_scaled = hbias_ext <<< 2;
                'd8: hbias_scaled = hbias_ext <<< 3;
                'd16: hbias_scaled = hbias_ext <<< 4;
                default: hbias_scaled = hbias_ext;
            endcase
            scale_hbias_ref = $signed(hbias_scaled);
        end
    endfunction

    task automatic write_sram_word(
        input int bank_idx,
        input int addr_idx,
        input logic [SRAM_DWIDTH-1:0] data_i
    );
        begin
            case (bank_idx)
                0: sram_banks[0].u_sram.sram[addr_idx] = data_i;
                1: sram_banks[1].u_sram.sram[addr_idx] = data_i;
                2: sram_banks[2].u_sram.sram[addr_idx] = data_i;
                3: sram_banks[3].u_sram.sram[addr_idx] = data_i;
            //    4: sram_banks[4].u_sram.memory[addr_idx] = data_i;
            //    5: sram_banks[5].u_sram.memory[addr_idx] = data_i;
            //    6: sram_banks[6].u_sram.memory[addr_idx] = data_i;
            //    7: sram_banks[7].u_sram.memory[addr_idx] = data_i;
                default: begin end
            endcase
        end
    endtask

    // Task to initialize all SRAM banks with different patterns
    task automatic init_all_srams(input init_mode_t mode);
        logic [SRAM_DWIDTH-1:0] write_data;
        logic signed [BITJ-1:0] j_matrix [0:DATASPIN-1][0:DATASPIN-1];
        logic signed [BITH-1:0] hbias_vec [0:DATASPIN-1];
        logic [SCALING_BIT-1:0] hscaling_vec [0:DATASPIN-1];
        logic signed [BITJ-1:0] w_tmp;
        logic signed [BITH-1:0] h_tmp;
        logic [SCALING_BIT-1:0] hs_tmp;
        int row;
        int col;
        int bank;
        int addr;
        
        $display("Initializing all SRAM banks with mode: %s", mode.name());

        // --------------------------------------------------------------------
        // 1) Build full J matrix with forced symmetry: J[row][col] = J[col][row]
        // --------------------------------------------------------------------
        for (row = 0; row < DATASPIN; row++) begin
            for (col = row; col < DATASPIN; col++) begin
                if (row == col) begin
                    // Diagonal term is forced to zero.
                    w_tmp = '0;
                end else begin
                    case (mode)
                        INIT_ALL_ONES: begin
                            w_tmp = {{(BITJ-1){1'b0}}, 1'b1}; // +1
                        end
                        INIT_ADDR_PATTERN: begin
                            // Deterministic signed pattern derived from row/col.
                            w_tmp = $signed((row * DATASPIN + col) % (1 << BITJ));
                        end
                        INIT_RANDOM: begin
                            w_tmp = $signed($urandom_range(0, (1 << BITJ) - 1));
                        end
                        default: begin
                            w_tmp = '0;
                        end
                    endcase
                end
                j_matrix[row][col] = w_tmp;
                j_matrix[col][row] = w_tmp;
            end
        end

        // --------------------------------------------------------------------
        // 2) Build hbias/scaling vectors per column
        // --------------------------------------------------------------------
        for (col = 0; col < DATASPIN; col++) begin
            case (mode)
                INIT_ALL_ONES: begin
                    h_tmp = {{(BITH-1){1'b0}}, 1'b1};
                    hs_tmp = 'd1;
                end
                INIT_ADDR_PATTERN: begin
                    // Deterministic positive hbias per column: 0,1,2,...
                    // (for DATASPIN=256 this maps through 255).
                    h_tmp = $signed(col);
                    // Fixed scaling factor = 1 for address-pattern mode.
                    hs_tmp = 'd1;
                end
                INIT_RANDOM: begin
                    h_tmp = $signed($urandom_range(0, (1 << BITH) - 1));
                    hs_tmp = select_hscaling($urandom_range(0, 4));
                end
                default: begin
                    h_tmp = '0;
                    hs_tmp = 'd1;
                end
            endcase
            hbias_vec[col] = h_tmp;
            hscaling_vec[col] = hs_tmp;
            // hbias_vec[col] = '0;
            // hscaling_vec[col] = 'd1;
        end

        // --------------------------------------------------------------------
        // 3) Pack each column into SRAM words and write bank/address
        //    col -> bank = col % PARALLELISM, addr = col / PARALLELISM
        // --------------------------------------------------------------------
        for (col = 0; col < DATASPIN; col++) begin
            bank = col % PARALLELISM;
            addr = col / PARALLELISM;
            write_data = '0;
            for (row = 0; row < DATASPIN; row++) begin
                write_data[row*BITJ +: BITJ] = j_matrix[row][col];
            end
            write_data[SRAM_HBIAS_LSB +: BITH] = hbias_vec[col];
            write_data[SRAM_HSCALING_LSB +: SCALING_BIT] = hscaling_vec[col];
            write_sram_word(bank, addr, write_data);
        end

        // Keep remaining addresses (if any) at zero
        for (bank = 0; bank < PARALLELISM; bank++) begin
            for (addr = (DATASPIN / PARALLELISM); addr < SRAM_DEPTH; addr++) begin
                write_sram_word(bank, addr, '0);
            end
        end

        for (bank = 0; bank < PARALLELISM; bank++) begin
            $display("  - SRAM Bank[%0d] initialized", bank);
        end
    endtask

    // =========================================================================
    // Reference Energy Checker
    //
    // NOTE: This file must be `included inside the testbench module body so
    // that localparams (DATASPIN, PARALLELISM, BITJ, ENERGY_TOTAL_BIT,
    // SRAM_DWIDTH, LITTLE_ENDIAN, SRAM_DEPTH) and module signals (clk_i,
    // spin_valid_i, spin_ready_o, spin_i, energy_valid_o, energy_ready_i,
    // energy_o, sram_banks) are all in scope.
    // =========================================================================

    // Captured spin vector at the last accepted spin handshake.
    // Used as the reference input for compute_ref_energy_from_sram.
    logic [DATASPIN-1:0] spin_snapshot;

    // Per-column reference local energies for waveform inspection:
    //   local_energy_col_ref[j] = sigma_j * ( J[:,j] · sigma )
    // Not displayed; inspect on the waveform for column-by-column debugging.
    logic signed [ENERGY_TOTAL_BIT-1:0] local_energy_col_ref [0:DATASPIN-1];

    // One grouped reference value per weight input beat.
    // Each entry is the sum of PARALLELISM consecutive sigma-weighted
    // column energies, e.g. for PARALLELISM=4:
    //   [0] = col[0] + col[1] + col[2] + col[3]
    //   [1] = col[4] + col[5] + col[6] + col[7]
    logic signed [ENERGY_TOTAL_BIT-1:0] local_energy_group_ref [0:(DATASPIN/PARALLELISM)-1];
    
    // Total reference energy latched after each check_energy_vs_ref call.
    logic signed [ENERGY_TOTAL_BIT-1:0] energy_ref_total;

    // Mirrors DUT first-operation sampled behavior for hbias gating.
    logic ref_first_operation_sampled;

    // Capture the spin vector at every DUT-accepted spin handshake.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            spin_snapshot <= '0;
        else if (spin_valid_i && spin_ready_o)
            spin_snapshot <= spin_i;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            ref_first_operation_sampled <= 1'b0;
        else if (first_operation_i)
            ref_first_operation_sampled <= 1'b1;
        else if (energy_valid_o && energy_ready_i)
            ref_first_operation_sampled <= 1'b0;
    end

    // -------------------------------------------------------------------------
    // compute_ref_energy_from_sram
    //
    // Computes E = sigma^T * J * sigma column by column, reading J directly
    // from the SRAM hierarchy.
    //
    // Column mapping:
    //   col j  ->  bank = j % PARALLELISM,  addr = j / PARALLELISM
    //   sram_word = sram_banks[bank].u_sram.memory[addr]  (SRAM_DWIDTH bits)
    //   J[row][j] = sram_word[ row*BITJ +: BITJ ]         (signed, BITJ bits)
    //
    // Per-column computation:
    //   col_dot[j] = sum_{row != j} ( J[row][j] * sigma_row )
    //   local_e[j] = sigma_j * col_dot[j]
    //   E          = sum_j local_e[j]
    //
    // Spin encoding: bit = 1 -> sigma = +1,  bit = 0 -> sigma = -1.
    // hbias and hscaling are packed in SRAM and applied like DUT.
    //
    // Side-effect: populates local_energy_col_ref[j] for waveform visibility.
    // -------------------------------------------------------------------------
    function automatic signed [ENERGY_TOTAL_BIT-1:0] compute_ref_energy_from_sram(
        input logic [DATASPIN-1:0] spin_vec
    );
        logic signed [ENERGY_TOTAL_BIT-1:0] total_accum;
        logic signed [ENERGY_TOTAL_BIT-1:0] col_dot;
        logic signed [ENERGY_TOTAL_BIT-1:0] group_accum;
        logic signed [ENERGY_TOTAL_BIT-1:0] hbias_scaled;
        logic [SRAM_DWIDTH-1:0]             sram_word;
        logic signed [BITJ-1:0]             j_val;
        logic signed [BITH-1:0]             hbias_val;
        logic [SCALING_BIT-1:0]             hscaling_val;
        logic                               s_col, s_row;
        int                                 bank_idx, addr_idx, col_idx, row_idx, group_idx, bank_in_group;
        begin
            total_accum = '0;
            for (col_idx = 0; col_idx < DATASPIN; col_idx++) begin
                bank_idx  = col_idx % PARALLELISM;
                addr_idx  = col_idx / PARALLELISM;
                sram_word = read_sram_word(bank_idx, addr_idx);
                hbias_val = $signed(sram_word[SRAM_HBIAS_LSB +: BITH]);
                hscaling_val = sram_word[SRAM_HSCALING_LSB +: SCALING_BIT];
                hbias_scaled = scale_hbias_ref(hbias_val, hscaling_val);
                           
                s_col = (LITTLE_ENDIAN == `True) ? spin_vec[col_idx]
                                                 : spin_vec[DATASPIN - 1 - col_idx];
                col_dot = '0;
                for (row_idx = 0; row_idx < DATASPIN; row_idx++) begin
                    if (row_idx == col_idx) continue; // J diagonal = 0 by convention
                    j_val = $signed(sram_word[row_idx * BITJ +: BITJ]);
                    s_row = (LITTLE_ENDIAN == `True) ? spin_vec[row_idx]
                                                     : spin_vec[DATASPIN - 1 - row_idx];
                    // accumulate J[row][col] * sigma_row
                    if (s_row) col_dot += j_val;  // sigma = +1 : add
                    else       col_dot -= j_val;  // sigma = -1 : subtract
                end

                // local energy for this column; written for waveform visibility
                local_energy_col_ref[col_idx] = s_col ? (col_dot + hbias_scaled)
                                                     : -(col_dot + hbias_scaled);
                total_accum += local_energy_col_ref[col_idx];
            end

            for (group_idx = 0; group_idx < (DATASPIN / PARALLELISM); group_idx++) begin
                group_accum = '0;
                for (bank_in_group = 0; bank_in_group < PARALLELISM; bank_in_group++) begin
                    group_accum += local_energy_col_ref[group_idx * PARALLELISM + bank_in_group];
                end
                local_energy_group_ref[group_idx] = group_accum;
            end

            compute_ref_energy_from_sram = total_accum;
        end
    endfunction

    // -------------------------------------------------------------------------
    // check_energy_vs_ref
    //
    // Waits for DUT to assert energy_valid_o, then:
    //   1. Reads energy_o from DUT.
    //   2. Computes reference energy from SRAM using the captured spin_snapshot.
    //   3. Latches the result into energy_ref_total.
    //   4. Prints PASS / FAIL with values and difference.
    //   5. Completes the valid/ready handshake (pulses energy_ready_i one cycle).
    // -------------------------------------------------------------------------
    task automatic check_energy_vs_ref();
        logic signed [ENERGY_TOTAL_BIT-1:0] ref_val;
        begin
            wait (energy_valid_o);
            ref_val          = compute_ref_energy_from_sram(spin_snapshot);
            energy_ref_total = ref_val;
            if (energy_o === ref_val) begin
                $display("[check_energy_vs_ref][PASS] Time %0t ns: energy_o = %0d",
                         $time, $signed(energy_o));
            end else begin
                $error("[check_energy_vs_ref][FAIL] Time %0t ns: DUT = %0d  REF = %0d  diff = %0d",
                       $time, $signed(energy_o), $signed(ref_val),
                       $signed(energy_o) - $signed(ref_val));
            end
            // Complete handshake: assert ready for one cycle
            energy_ready_i = 1;
            @(posedge clk_i);
            energy_ready_i = 0;
        end
    endtask