onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_energy_monitor/dut/weight_valid_i
add wave -noupdate /tb_energy_monitor/dut/weight_i
add wave -noupdate /tb_energy_monitor/dut/clk_i
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {55000 ps} 0}
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
WaveRestoreZoom {37498 ps} {90855 ps}
