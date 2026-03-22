onerror {resume}
quietly virtual signal -install /tb_energy_monitor/dut { /tb_energy_monitor/dut/hbias_i[15:12]} H3
quietly virtual signal -install /tb_energy_monitor/dut { /tb_energy_monitor/dut/hbias_i[11:8]} H2
quietly virtual signal -install /tb_energy_monitor/dut { /tb_energy_monitor/dut/hbias_i[7:4]} H2001
quietly virtual signal -install /tb_energy_monitor/dut { /tb_energy_monitor/dut/hbias_i[3:0]} H0
quietly WaveActivateNextPane {} 0
add wave -noupdate -label H3 -radix unsigned /tb_energy_monitor/dut/H3
add wave -noupdate -label H2 -radix unsigned /tb_energy_monitor/dut/H2
add wave -noupdate -label H1 -radix unsigned /tb_energy_monitor/dut/H2001
add wave -noupdate -label H0 -radix unsigned /tb_energy_monitor/dut/H0
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
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
WaveRestoreZoom {44160 ps} {60640 ps}
