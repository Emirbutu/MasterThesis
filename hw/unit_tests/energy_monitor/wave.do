onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_energy_monitor/dut/counter_q
add wave -noupdate /tb_energy_monitor/dut/weight_valid_pipe
add wave -noupdate /tb_energy_monitor/dut/clk_i
add wave -noupdate /tb_energy_monitor/dut/weight_valid_i
add wave -noupdate /tb_energy_monitor/dut/weight_i
add wave -noupdate -radix binary /tb_energy_monitor/dut/current_spin
add wave -noupdate -radix decimal {/tb_energy_monitor/dut/partial_energy_calc_inst[3]/u_partial_energy_calc/energy_local_wo_hbias}
add wave -noupdate -radix decimal {/tb_energy_monitor/dut/partial_energy_calc_inst[2]/u_partial_energy_calc/energy_local_wo_hbias}
add wave -noupdate -color Coral -radix decimal {/tb_energy_monitor/dut/partial_energy_calc_inst[1]/u_partial_energy_calc/energy_local_wo_hbias}
add wave -noupdate -radix decimal {/tb_energy_monitor/dut/partial_energy_calc_inst[0]/u_partial_energy_calc/energy_local_wo_hbias}
add wave -noupdate {/tb_energy_monitor/dut/partial_energy_calc_inst[3]/u_partial_energy_calc/current_spin_pipe}
add wave -noupdate {/tb_energy_monitor/dut/partial_energy_calc_inst[2]/u_partial_energy_calc/current_spin_pipe}
add wave -noupdate {/tb_energy_monitor/dut/partial_energy_calc_inst[1]/u_partial_energy_calc/current_spin_pipe}
add wave -noupdate {/tb_energy_monitor/dut/partial_energy_calc_inst[0]/u_partial_energy_calc/current_spin_pipe}
add wave -noupdate /tb_energy_monitor/dut/weight_raddr_em_o
add wave -noupdate /tb_energy_monitor/dut/weight_handshake
add wave -noupdate -color Yellow /tb_energy_monitor/weight_ready_o
add wave -noupdate /tb_energy_monitor/rst_ni
add wave -noupdate /tb_energy_monitor/spin_valid_i
add wave -noupdate -color Magenta /tb_energy_monitor/dut/weight_ready_pipe
add wave -noupdate -radix unsigned /tb_energy_monitor/dut/u_step_counter_sram/q_o
add wave -noupdate /tb_energy_monitor/dut/u_step_counter_sram/step_en_i
add wave -noupdate -radix decimal /tb_energy_monitor/dut/energy_o
add wave -noupdate -radix decimal /tb_energy_monitor/dut/local_energy_parallel
add wave -noupdate -radix unsigned /tb_energy_monitor/dut/weight_raddr_em_o
add wave -noupdate /tb_energy_monitor/dut/max_flipped_count_valid
add wave -noupdate -color White /tb_energy_monitor/dut/counter_q_diff
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {189000 ps} 0}
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
configure wave -timelineunits ns
update
WaveRestoreZoom {171064 ps} {230164 ps}
