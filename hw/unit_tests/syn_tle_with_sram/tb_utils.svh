/*
// SRAM initialization modes
    typedef enum {
        INIT_ALL_ONES,
        INIT_ADDR_PATTERN,
        INIT_RANDOM
    } init_mode_t;

    localparam int TB_BANK_WORD_DW = (DATASPIN / PARALLELISM) * BITJ;
    localparam int TB_COL_WORD_DW = DATASPIN * BITJ;

    function automatic logic [TB_COL_WORD_DW-1:0] read_sram_word(
        input int bank_idx,
        input int addr_idx
    );
        logic [TB_COL_WORD_DW-1:0] col_data;
        begin
            col_data = '0;
            case (bank_idx)
                0: begin
                    col_data[0*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[0].gen_lane_bank[0].u_sram.sram[addr_idx];
                    col_data[1*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[0].gen_lane_bank[1].u_sram.sram[addr_idx];
                    col_data[2*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[0].gen_lane_bank[2].u_sram.sram[addr_idx];
                    col_data[3*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[0].gen_lane_bank[3].u_sram.sram[addr_idx];
                end
                1: begin
                    col_data[0*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[1].gen_lane_bank[0].u_sram.sram[addr_idx];
                    col_data[1*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[1].gen_lane_bank[1].u_sram.sram[addr_idx];
                    col_data[2*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[1].gen_lane_bank[2].u_sram.sram[addr_idx];
                    col_data[3*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[1].gen_lane_bank[3].u_sram.sram[addr_idx];
                end
                2: begin
                    col_data[0*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[2].gen_lane_bank[0].u_sram.sram[addr_idx];
                    col_data[1*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[2].gen_lane_bank[1].u_sram.sram[addr_idx];
                    col_data[2*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[2].gen_lane_bank[2].u_sram.sram[addr_idx];
                    col_data[3*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[2].gen_lane_bank[3].u_sram.sram[addr_idx];
                end
                3: begin
                    col_data[0*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[3].gen_lane_bank[0].u_sram.sram[addr_idx];
                    col_data[1*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[3].gen_lane_bank[1].u_sram.sram[addr_idx];
                    col_data[2*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[3].gen_lane_bank[2].u_sram.sram[addr_idx];
                    col_data[3*TB_BANK_WORD_DW +: TB_BANK_WORD_DW] = dut.gen_weight_srams[3].gen_lane_bank[3].u_sram.sram[addr_idx];
                end
                default: col_data = '0;
            endcase
            read_sram_word = col_data;
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

    task automatic write_sram_word(input int bank_idx, input int addr_idx, input logic [TB_BANK_WORD_DW-1:0] data_i);
        begin
            case (bank_idx)
                0: dut.gen_weight_srams[0].gen_lane_bank[0].u_sram.sram[addr_idx] = data_i;
                1: dut.gen_weight_srams[0].gen_lane_bank[1].u_sram.sram[addr_idx] = data_i;
                2: dut.gen_weight_srams[0].gen_lane_bank[2].u_sram.sram[addr_idx] = data_i;
                3: dut.gen_weight_srams[0].gen_lane_bank[3].u_sram.sram[addr_idx] = data_i;
                4: dut.gen_weight_srams[1].gen_lane_bank[0].u_sram.sram[addr_idx] = data_i;
                5: dut.gen_weight_srams[1].gen_lane_bank[1].u_sram.sram[addr_idx] = data_i;
                6: dut.gen_weight_srams[1].gen_lane_bank[2].u_sram.sram[addr_idx] = data_i;
                7: dut.gen_weight_srams[1].gen_lane_bank[3].u_sram.sram[addr_idx] = data_i;
                8: dut.gen_weight_srams[2].gen_lane_bank[0].u_sram.sram[addr_idx] = data_i;
                9: dut.gen_weight_srams[2].gen_lane_bank[1].u_sram.sram[addr_idx] = data_i;
                10: dut.gen_weight_srams[2].gen_lane_bank[2].u_sram.sram[addr_idx] = data_i;
                11: dut.gen_weight_srams[2].gen_lane_bank[3].u_sram.sram[addr_idx] = data_i;
                12: dut.gen_weight_srams[3].gen_lane_bank[0].u_sram.sram[addr_idx] = data_i;
                13: dut.gen_weight_srams[3].gen_lane_bank[1].u_sram.sram[addr_idx] = data_i;
                14: dut.gen_weight_srams[3].gen_lane_bank[2].u_sram.sram[addr_idx] = data_i;
                15: dut.gen_weight_srams[3].gen_lane_bank[3].u_sram.sram[addr_idx] = data_i;
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
        logic [TB_COL_WORD_DW-1:0] col_data;
        logic [TB_BANK_WORD_DW-1:0] write_data;
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
            col_data = '0;
            for (row = 0; row < DATASPIN; row++) begin
                col_data[row*BITJ +: BITJ] = j_matrix[row][col];
            end
            for (int s = 0; s < 4; s++) begin
                write_data = col_data[s*TB_BANK_WORD_DW +: TB_BANK_WORD_DW];
                write_sram_word(bank*4 + s, addr, write_data);
            end
        end

        // Keep remaining addresses (if any) at zero
        for (bank = 0; bank < (PARALLELISM * 4); bank++) begin
            for (addr = (DATASPIN / PARALLELISM); addr < SRAM_DEPTH; addr++) begin
                write_sram_word(bank, addr, '0);
            end
        end

        for (bank = 0; bank < (PARALLELISM * 4); bank++) begin
            $display("  - SRAM Bank[%0d] initialized", bank);
        end
    endtask

*/

/*
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
        logic [TB_COL_WORD_DW-1:0]          sram_word;
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
                hbias_val = hbias_shadow[col_idx];
                hscaling_val = hscaling_shadow[col_idx];
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
                $fatal("[check_energy_vs_ref][FAIL] Time %0t ns: DUT = %0d  REF = %0d  diff = %0d",
                       $time, $signed(energy_o), $signed(ref_val),
                       $signed(energy_o) - $signed(ref_val));
            end
            // Complete handshake: assert ready for one cycle
            energy_ready_i = 1;
            @(posedge clk_i);
            energy_ready_i = 0;
        end
    endtask
*/

    // -------------------------------------------------------------------------
    // Stimulus helper tasks/functions
    // -------------------------------------------------------------------------
    task automatic send_payload(input logic [IN_DATAW-1:0] payload);
        begin
            data_in <= payload;
            valid_in <= 1'b1;
            while (!ready_in) @(posedge clk_i);
            @(posedge clk_i);
            valid_in <= 1'b0;
            data_in <= '0;
            data_in[IN_LSB_EN +: 1] <= 1'b1;
            data_in[IN_LSB_STD_MODE +: 1] <= TB_STANDARD_MODE;
        end
    endtask

    task automatic send_cfg(input logic [SPINIDX_BIT-1:0] cfg_counter);
        logic [IN_DATAW-1:0] payload;
        begin
            payload = '0;
            payload[IN_LSB_EN +: 1] = 1'b1;
            payload[IN_LSB_STD_MODE +: 1] = TB_STANDARD_MODE;
            payload[IN_LSB_CFG_VALID +: 1] = 1'b1;
            payload[IN_LSB_CFG_COUNTER +: SPINIDX_BIT] = cfg_counter;
            send_payload(payload);
        end
    endtask

    task automatic send_spin(input logic [DATASPIN-1:0] spin_vec, input logic first_op);
        logic [IN_DATAW-1:0] payload;
        begin
            payload = '0;
            payload[IN_LSB_EN +: 1] = 1'b1;
            payload[IN_LSB_STD_MODE +: 1] = TB_STANDARD_MODE;
            payload[IN_LSB_FIRST_OP +: 1] = first_op;
            payload[IN_LSB_SPIN_VALID +: 1] = 1'b1;
            payload[IN_LSB_SPIN +: DATASPIN] = spin_vec;

            first_operation_i <= first_op;
            spin_i <= spin_vec;
            spin_valid_i <= 1'b1;
            send_payload(payload);
            spin_valid_i <= 1'b0;
        end
    endtask

    function automatic logic signed [BITJ-1:0] random_weight();
        begin
            random_weight = $signed($urandom_range(0, (1 << BITJ) - 1));
        end
    endfunction

/*
    task automatic build_and_init_sram_direct();
        logic signed [BITJ-1:0] val;
        logic [TB_COL_WORD_DW-1:0] sram_word;
        int row;
        int col;
        int addr;
        int bank;
        begin
            for (row = 0; row < DATASPIN; row++) begin
                for (col = row; col < DATASPIN; col++) begin
                    if (row == col) begin
                        val = '0;
                    end else begin
                        case (`test_mode)
                            `S1W1H1_TEST,
                            `S0W1H1_TEST:      val = $signed(4'sd1);
                            `S0W0H0_TEST,
                            `S1W0H0_TEST:      val = $signed(-4'sd1);
                            `MaxPosValue_TEST: val = $signed(4'sd7);
                            `MaxNegValue_TEST: val = $signed(-4'sd8);
                            default:           val = random_weight();
                        endcase
                    end
                    j_matrix[row][col] = val;
                    j_matrix[col][row] = val;
                end
            end

            case (`test_mode)
                `S1W1H1_TEST,
                `S0W1H1_TEST:      hbias_const = $signed(4'sd1);
                `S0W0H0_TEST,
                `S1W0H0_TEST:      hbias_const = $signed(-4'sd1);
                `MaxPosValue_TEST: hbias_const = $signed(4'sd7);
                `MaxNegValue_TEST: hbias_const = $signed(-4'sd8);
                default:           hbias_const = $signed($urandom_range(0, (1 << BITH) - 1));
            endcase
            hscaling_const = 'd1;

            for (col = 0; col < DATASPIN; col++) begin
                hbias_shadow[col] = hbias_const;
                hscaling_shadow[col] = hscaling_const;
            end

            for (addr = 0; addr < (DATASPIN / PARALLELISM); addr++) begin
                for (bank = 0; bank < PARALLELISM; bank++) begin
                    col = addr * PARALLELISM + bank;
                    sram_word = '0;
                    for (row = 0; row < DATASPIN; row++) begin
                        sram_word[row*BITJ +: BITJ] = j_matrix[row][col];
                    end
                    for (int s = 0; s < 4; s++) begin
                        write_sram_word(bank*4 + s, addr, sram_word[s*TB_BANK_WORD_DW +: TB_BANK_WORD_DW]);
                    end
                end
            end

            for (bank = 0; bank < PARALLELISM; bank++) begin
                case (bank)
                    0: begin
                        dut.gen_weight_srams[0].hbias_reg = hbias_const;
                        dut.gen_weight_srams[0].hscaling_reg = hscaling_const;
                    end
                    1: begin
                        dut.gen_weight_srams[1].hbias_reg = hbias_const;
                        dut.gen_weight_srams[1].hscaling_reg = hscaling_const;
                    end
                    2: begin
                        dut.gen_weight_srams[2].hbias_reg = hbias_const;
                        dut.gen_weight_srams[2].hscaling_reg = hscaling_const;
                    end
                    3: begin
                        dut.gen_weight_srams[3].hbias_reg = hbias_const;
                        dut.gen_weight_srams[3].hscaling_reg = hscaling_const;
                    end
                    default: begin end
                endcase
            end
        end
    endtask
*/

    function automatic logic [DATASPIN-1:0] build_spin(input int t);
        logic [DATASPIN-1:0] out_spin;
        int i;
        begin
            out_spin = '0;
            for (i = 0; i < DATASPIN; i++) begin
                case (`test_mode)
                    `S1W1H1_TEST,
                    `S1W0H0_TEST,
                    `MaxPosValue_TEST: out_spin[i] = 1'b1;
                    `S0W1H1_TEST,
                    `S0W0H0_TEST,
                    `MaxNegValue_TEST: out_spin[i] = 1'b0;
                    `RANDOM_TEST:      out_spin[i] = $urandom() % 2;
                    default:           out_spin[i] = t[0];
                endcase
            end
            build_spin = out_spin;
        end
    endfunction

    // ========================================================================
    // FIFO Vector Management Functions
    // ========================================================================

    // Load vectors from a file and populate the FIFO.
    // Supports both binary (256-bit 0/1) and hexadecimal formats.
    // Returns the number of vectors successfully loaded.
    function automatic integer load_vectors_from_file(
        input string file_path,
        inout logic [DATASPIN-1:0] vector_fifo [0:`NUM_TESTS-1],
        inout integer test_id_fifo [0:`NUM_TESTS-1],
        inout integer fifo_write_ptr,
        inout integer fifo_count,
        input integer max_vectors
    );
        integer file_fd;
        string line;
        logic [DATASPIN-1:0] vector;
        integer scan_result;
        integer vectors_loaded;
        
        begin
            vectors_loaded = 0;
            file_fd = $fopen(file_path, "r");
            
            if (file_fd != 0) begin
                while ((vectors_loaded < max_vectors) && (!$feof(file_fd))) begin
                    line = "";
                    void'($fgets(line, file_fd));
                    
                    // Try binary format first (256-bit 0/1 text lines)
                    scan_result = $sscanf(line, "%b", vector);
                    
                    // Fall back to hexadecimal if binary parsing failed
                    if (scan_result != 1) begin
                        scan_result = $sscanf(line, "%h", vector);
                    end
                    
                    // If parsing was successful, add to FIFO
                    if (scan_result == 1) begin
                        if (fifo_count < `NUM_TESTS) begin
                            vector_fifo[fifo_write_ptr] = vector;
                            test_id_fifo[fifo_write_ptr] = vectors_loaded;
                            fifo_write_ptr = (fifo_write_ptr + 1) % `NUM_TESTS;
                            fifo_count = fifo_count + 1;
                            vectors_loaded = vectors_loaded + 1;
                        end else begin
                            $warning("[FIFO] Vector FIFO overflow at vector %0d", vectors_loaded);
                        end
                    end
                end
                $fclose(file_fd);
            end else begin
                $error("[FIFO] Failed to open file: %0s", file_path);
            end
            
            if (vectors_loaded == 0) begin
                $warning("[FIFO] No valid vectors loaded from %0s", file_path);
            end else begin
                $display("[FIFO] Successfully loaded %0d vectors from %0s", vectors_loaded, file_path);
            end
            
            load_vectors_from_file = vectors_loaded;
        end
    endfunction

    // Add a single vector to the FIFO
    function automatic bit enqueue_vector(
        input logic [DATASPIN-1:0] vector,
        input integer test_id,
        inout logic [DATASPIN-1:0] vector_fifo [0:`NUM_TESTS-1],
        inout integer test_id_fifo [0:`NUM_TESTS-1],
        inout integer fifo_write_ptr,
        inout integer fifo_count
    );
        begin
            if (fifo_count < `NUM_TESTS) begin
                vector_fifo[fifo_write_ptr] = vector;
                test_id_fifo[fifo_write_ptr] = test_id;
                fifo_write_ptr = (fifo_write_ptr + 1) % `NUM_TESTS;
                fifo_count = fifo_count + 1;
                enqueue_vector = 1'b1;
            end else begin
                $warning("[FIFO] Cannot enqueue vector - FIFO is full (count=%0d)", fifo_count);
                enqueue_vector = 1'b0;
            end
        end
    endfunction

    // Remove and return a vector from the FIFO (dequeue)
    function automatic bit dequeue_vector(
        output logic [DATASPIN-1:0] vector,
        output integer test_id,
        inout logic [DATASPIN-1:0] vector_fifo [0:`NUM_TESTS-1],
        inout integer test_id_fifo [0:`NUM_TESTS-1],
        inout integer fifo_read_ptr,
        inout integer fifo_count
    );
        begin
            if (fifo_count > 0) begin
                vector = vector_fifo[fifo_read_ptr];
                test_id = test_id_fifo[fifo_read_ptr];
                fifo_read_ptr = (fifo_read_ptr + 1) % `NUM_TESTS;
                fifo_count = fifo_count - 1;
                dequeue_vector = 1'b1;
            end else begin
                $warning("[FIFO] Cannot dequeue - FIFO is empty");
                dequeue_vector = 1'b0;
            end
        end
    endfunction

    // Get current number of vectors in FIFO
    function automatic integer get_fifo_count(
        input integer fifo_count
    );
        begin
            get_fifo_count = fifo_count;
        end
    endfunction

    // Peek at the next vector without removing it from FIFO
    function automatic bit peek_fifo_vector(
        output logic [DATASPIN-1:0] vector,
        output integer test_id,
        input logic [DATASPIN-1:0] vector_fifo [0:`NUM_TESTS-1],
        input integer test_id_fifo [0:`NUM_TESTS-1],
        input integer fifo_read_ptr,
        input integer fifo_count
    );
        begin
            if (fifo_count > 0) begin
                vector = vector_fifo[fifo_read_ptr];
                test_id = test_id_fifo[fifo_read_ptr];
                peek_fifo_vector = 1'b1;
            end else begin
                $warning("[FIFO] Cannot peek - FIFO is empty");
                peek_fifo_vector = 1'b0;
            end
        end
    endfunction

    // Send all vectors from FIFO sequentially as spin payloads
    task automatic send_all_vectors_from_fifo(
        inout logic [DATASPIN-1:0] vector_fifo [0:`NUM_TESTS-1],
        inout integer test_id_fifo [0:`NUM_TESTS-1],
        inout integer fifo_read_ptr,
        inout integer fifo_count,
        output integer vectors_sent
    );
        logic [DATASPIN-1:0] vector;
        integer test_id;
        integer send_count;
        bit success;
        
        begin
            vectors_sent = 0;
            send_count = 0;
            
            $display("[FIFO] Starting to send %0d vectors from FIFO", fifo_count);
            
            while (fifo_count > 0) begin
                success = dequeue_vector(vector, test_id, vector_fifo, test_id_fifo, 
                                        fifo_read_ptr, fifo_count);
                
                if (success) begin
                    // Send with first_op flag set only for first vector
                    send_spin(vector, (send_count == 0));
                    vectors_sent = vectors_sent + 1;
                    send_count = send_count + 1;
                    
                    if ((send_count % 50) == 0) begin
                        $display("[FIFO] Sent %0d vectors so far...", send_count);
                    end
                end else begin
                    $warning("[FIFO] Failed to dequeue vector at position %0d", send_count);
                    break;
                end
            end
            
            $display("[FIFO] Completed sending %0d vectors from FIFO", vectors_sent);
        end
    endtask

    // Clear all vectors from FIFO
    function automatic void clear_fifo(
        inout integer fifo_write_ptr,
        inout integer fifo_read_ptr,
        inout integer fifo_count
    );
        begin
            fifo_write_ptr = 0;
            fifo_read_ptr = 0;
            fifo_count = 0;
            $display("[FIFO] FIFO cleared");
        end
    endfunction