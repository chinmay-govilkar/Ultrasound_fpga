`timescale 1ns / 1ps

module tb_top_stage1();
    
    // Inputs
    reg clk_sys;
    reg fmc_clk_p;
    wire fmc_clk_n;
    reg [6:0] fmc_data_p;
    reg [6:0] fmc_data_n;
    reg reset;
    reg trigger;
    
    // Outputs
    wire tx_ready;

    // Automatically generate the negative differential clock
    assign fmc_clk_n = ~fmc_clk_p;

    // Instantiate the Unit Under Test (UUT)
    top_stage1 uut (
        .clk_sys(clk_sys),
        .fmc_clk_p(fmc_clk_p),
        .fmc_clk_n(fmc_clk_n),
        .fmc_data_p(fmc_data_p),
        .fmc_data_n(fmc_data_n),
        .reset(reset),
        .trigger(trigger),
        .tx_ready(tx_ready) 
    );

    // Clock Generation
    always #5 clk_sys = ~clk_sys;     // 100 MHz System Clock 
    always #2 fmc_clk_p = ~fmc_clk_p; // 250 MHz FMC Clock (4ns period -> 2ns HIGH, 2ns LOW)

    // Mathematical variables for generating the 1 MHz sine wave
    real pi = 3.14159265358979323846;
    real time_us;
    real sine_val;
    reg [13:0] adc_14bit_val; 

    initial begin
        clk_sys = 0;
        fmc_clk_p = 0;
        reset = 1;       
        trigger = 0;
        fmc_data_p = 7'd0;
        fmc_data_n = 7'h7F; 

        // Reset the system
        #100;
        reset = 0;
        
        // Wait and then fire the trigger
        #50;
        trigger = 1; 
        #20;
        trigger = 0;
        
        // Let it run long enough to capture the double-samples
        #20000;
        $finish;
    end

    // 1. Calculate the 14-bit sine wave continuously (Avoids clock race conditions)
    always begin
        #1; // Update math every 1 ns
        time_us = $realtime / 1000.0; 
        sine_val = $sin(2.0 * pi * 1.0 * time_us); 
        // Map from range [-1.0, 1.0] to [0, 16383] for the 14-bit FMC150 ADC
        adc_14bit_val = $rtoi((sine_val + 1.0) * 8191.5);
    end

    // 2. Simulate the DDR LVDS Serialization (Fixed Setup/Hold Timing)
    always @(fmc_clk_p) begin
        if (fmc_clk_p == 1'b0) begin
            // Shift data by 1ns to perfectly center it in the 2ns HIGH clock pulse
            fmc_data_p <= #1 adc_14bit_val[6:0];
            fmc_data_n <= #1 ~adc_14bit_val[6:0];
        end else begin
            // Shift data by 1ns to perfectly center it in the 2ns LOW clock pulse
            fmc_data_p <= #1 adc_14bit_val[13:7];
            fmc_data_n <= #1 ~adc_14bit_val[13:7];
        end
    end

endmodule