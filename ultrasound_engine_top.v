`timescale 1ns/1ps
// Recommended Stage 1 acquisition top. Reconstruction runs in Python.
// PHY, ADC configuration, AXIS clock converter and DMA are vendor/project blocks.
module ultrasound_engine_top #(
    parameter DATA_WIDTH=14,MAX_SAMPLES=32768,
    parameter COUNT_WIDTH=$clog2(MAX_SAMPLES+1),LINE_WIDTH=5
)(
    input wire adc_clk,rst_n,arm,trigger,adc_valid,
    input wire signed [DATA_WIDTH-1:0] adc_data,
    input wire [COUNT_WIDTH-1:0] record_samples,
    input wire [LINE_WIDTH-1:0] line_id,
    output wire arm_ready,armed,busy,line_done,capture_error,
    output wire [15:0] m_axis_tdata,
    output wire [1:0] m_axis_tkeep,
    output wire [LINE_WIDTH-1:0] m_axis_tuser,
    output wire m_axis_tvalid,m_axis_tlast,
    input wire m_axis_tready
);
    fmc150_axi_capture #(.DATA_WIDTH(DATA_WIDTH),.MAX_SAMPLES(MAX_SAMPLES),
        .COUNT_WIDTH(COUNT_WIDTH),.LINE_WIDTH(LINE_WIDTH)) capture(
        .adc_clk(adc_clk),.rst_n(rst_n),.arm(arm),.trigger(trigger),.adc_valid(adc_valid),
        .adc_data(adc_data),.record_samples(record_samples),.line_id(line_id),
        .arm_ready(arm_ready),.armed(armed),.busy(busy),.line_done(line_done),
        .capture_error(capture_error),.m_axis_tdata(m_axis_tdata),.m_axis_tkeep(m_axis_tkeep),
        .m_axis_tuser(m_axis_tuser),.m_axis_tvalid(m_axis_tvalid),
        .m_axis_tlast(m_axis_tlast),.m_axis_tready(m_axis_tready)
    );
endmodule
