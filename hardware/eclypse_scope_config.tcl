# Configure a current Digilent ZmodScopeController for this 100 MSPS profile.
# In an open Eclypse BD:
#   source hardware/eclypse_scope_config.tcl
#   configure_scope_1410_105 /ZmodADC_Controller_0
# This sets controller parameters ONLY. It does not generate clocks, connect
# calibration/relay control, assign physical pins, or validate a bitstream.
proc configure_scope_1410_105 {cell_name} {
    set cell [get_bd_cells -quiet $cell_name]
    if {[llength $cell] != 1} {error "Select exactly one ZmodScopeController cell"}
    if {![string match "digilent.com:user:ZmodScopeController:*" [get_property VLNV $cell]]} {
        error "Requires current ZmodScopeController, not legacy ZmodADC1410_Controller"
    }
    set_property -dict [list CONFIG.kZmodID {0} CONFIG.kSamplingPeriod {10000} \
        CONFIG.kADC_ClkDiv {1} CONFIG.kExtCalibEn {true} \
        CONFIG.kExtRelayConfigEn {true}] $cell
    if {[get_property CONFIG.kADC_Width $cell] != 14} {
        error "Controller did not select the 14-bit Scope 1410-105"
    }
    puts "Controller configured for Scope 1410-105 at 100 MSPS."
    puts "Supply SysClk100=100 MHz, ADC_SamplingClk=100 MHz, ADC_InClk=100 MHz."
    puts "Connect factory processed coefficients, relay controls and real board clocks/XDC."
}
