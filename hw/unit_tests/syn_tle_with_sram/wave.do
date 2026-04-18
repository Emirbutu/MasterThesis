onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/clk_i
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/rst_ni
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/en_i
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/load_i
add wave -noupdate -radix unsigned /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/d_i
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/recount_en_i
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/step_en_i
add wave -noupdate -radix unsigned /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/q_o
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/overflow_o
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/overflow
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/finish
add wave -noupdate -radix unsigned /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/counter_reg
add wave -noupdate -radix unsigned /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/counter_n
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/load_cond
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/step_cond
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/overflow_cond
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_step_counter_diff/recount_cond
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/weight_handshake
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_logic_ctrl/current_state
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/u_logic_ctrl/weight_ready_o
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/weight_ready_o
add wave -noupdate /tb_syn_tle_with_sram/dut/DUS/weight_raddr_valid_em_o
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {247000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {668430 ps}
