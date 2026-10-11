`timescale 1ns/1ps
// Eclypse Z7 Stage 1 top, downstream of Digilent ZmodScopeController.
// adc_clk MUST be controller ADC_SamplingClk, default 100 MHz.
// source_ready/source_error and ALL controls are already synchronous to adc_clk.
// Vendor PHY/SPI/calibration, CDC, DMA and PS control remain project blocks.
module ultrasound_engine_top #(
    parameter MAX_SAMPLES=16384,
    parameter COUNT_WIDTH=$clog2(MAX_SAMPLES+1),LINE_WIDTH=5
)(
    input wire adc_clk,rst_n,arm,trigger,
    input wire [31:0] cDataAxisTdata,
    input wire cDataAxisTvalid,
    output wire cDataAxisTready,
    input wire receiver_channel,source_ready,source_error,
    input wire [COUNT_WIDTH-1:0] record_samples,
    input wire [LINE_WIDTH-1:0] line_id,
    output wire arm_ready,armed,busy,line_done,capture_error,
    output wire [15:0] m_axis_tdata,
    output wire [1:0] m_axis_tkeep,
    output wire [LINE_WIDTH-1:0] m_axis_tuser,
    output wire m_axis_tvalid,m_axis_tlast,
    input wire m_axis_tready
);
    wire capture_ready,sample_valid;
    wire signed [15:0] sample_data;
    wire arm_fire=arm && arm_ready;
    assign arm_ready=capture_ready && source_ready && !source_error;
    zmod_scope_adapter adapter(
        .adc_clk(adc_clk),.rst_n(rst_n),.latch_channel(arm_fire),
        .receiver_channel(receiver_channel),.cDataAxisTdata(cDataAxisTdata),
        .cDataAxisTvalid(cDataAxisTvalid),.cDataAxisTready(cDataAxisTready),
        .sample_data(sample_data),.sample_valid(sample_valid)
    );
    adc_line_capture #(.DATA_WIDTH(16),.MAX_SAMPLES(MAX_SAMPLES),
        .COUNT_WIDTH(COUNT_WIDTH),.LINE_WIDTH(LINE_WIDTH)) capture(
        .adc_clk(adc_clk),.rst_n(rst_n),.arm(arm_fire),.trigger(trigger),
        .adc_valid(sample_valid && source_ready),.adc_error(source_error || !source_ready),
        .adc_data(sample_data),.record_samples(record_samples),.line_id(line_id),
        .arm_ready(capture_ready),.armed(armed),.busy(busy),.line_done(line_done),
        .capture_error(capture_error),.m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),
        .m_axis_tuser(m_axis_tuser),.m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),.m_axis_tready(m_axis_tready)
    );
endmodule
