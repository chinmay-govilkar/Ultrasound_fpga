# Reproducible Vivado OUT-OF-CONTEXT synthesis of reviewed post-PHY logic.
# From repo root: vivado -mode batch -source hardware/synth_ooc.tcl
# Optional core: append -tclargs das_beamformer_top 10.0
# This does NOT create a board bitstream or provide ADC I/O timing constraints.
set top ultrasound_engine_top
set period_ns 4.0
if {$argc > 0} {set top [lindex $argv 0]}
if {$argc > 1} {set period_ns [lindex $argv 1]}
file mkdir build/vivado
read_verilog [glob *.v]
synth_design -top $top -part xc7z020clg484-1 -mode out_of_context
if {$top eq "ultrasound_engine_top"} {set clock_port adc_clk} else {set clock_port clk}
create_clock -name core_clock -period $period_ns [get_ports $clock_port]
opt_design
report_utilization -file build/vivado/${top}_utilization.txt
report_timing_summary -file build/vivado/${top}_synth_timing.txt
write_checkpoint -force build/vivado/${top}_synth.dcp
