`timescale 1ns/1ps
// Digilent ZmodScopeController calibrated output, NOT legacy ZmodADC1410 words.
// All ports use ADC_SamplingClk. Accept/discard continuously outside echo windows.
module zmod_scope_adapter (
    input wire adc_clk,rst_n,latch_channel,receiver_channel,
    input wire [31:0] cDataAxisTdata,
    input wire cDataAxisTvalid,
    output wire cDataAxisTready,
    output wire signed [15:0] sample_data,
    output wire sample_valid
);
    reg selected_channel;
    always @(posedge adc_clk) begin
        if (!rst_n) selected_channel<=0;
        else if (latch_channel) selected_channel<=receiver_channel;
    end
    // 0=physical CH1 (upper half), 1=physical CH2 (lower half).
    assign sample_data=selected_channel ? $signed(cDataAxisTdata[15:0])
                                        : $signed(cDataAxisTdata[31:16]);
    assign sample_valid=cDataAxisTvalid;
    assign cDataAxisTready=1'b1;
endmodule
