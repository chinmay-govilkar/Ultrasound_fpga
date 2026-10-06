`timescale 1ns/1ps
// Post-PHY boundary: one SIGNED sample per adc_clk, all control synchronous.
// FMC150 BSP provides actual LVDS/SPI/clock interface. AXIS clock=adc_clk.
// Use AMD AXIS Clock Converter before a DMA in a different clock domain.
// Buffer the entire line: ADC capture cannot be backpressured.
module fmc150_axi_capture #(
    parameter DATA_WIDTH=14, MAX_SAMPLES=32768,
    parameter COUNT_WIDTH=$clog2(MAX_SAMPLES+1), LINE_WIDTH=5
)(
    input wire adc_clk,rst_n,arm,trigger,adc_valid,
    input wire [COUNT_WIDTH-1:0] record_samples,
    input wire [LINE_WIDTH-1:0] line_id,
    input wire signed [DATA_WIDTH-1:0] adc_data,
    output wire arm_ready,armed,busy,
    output reg line_done,capture_error,
    output reg [15:0] m_axis_tdata,
    output wire [1:0] m_axis_tkeep,
    output reg [LINE_WIDTH-1:0] m_axis_tuser,
    output reg m_axis_tvalid,m_axis_tlast,
    input wire m_axis_tready
);
    localparam IDLE=0,ARMED=1,CAPTURE=2,READ=3,LOAD=4,SEND=5;
    reg [2:0] state;
    reg [COUNT_WIDTH-1:0] count_r,wr_index,rd_index;
    (* ram_style="block" *) reg signed [DATA_WIDTH-1:0] ram[0:MAX_SAMPLES-1];
    reg signed [DATA_WIDTH-1:0] ram_q;
    assign arm_ready=state==IDLE;
    assign armed=state==ARMED;
    assign busy=state!=IDLE;
    assign m_axis_tkeep=2'b11;
    always @(posedge adc_clk) begin
        if (!rst_n) begin
            state<=IDLE; count_r<=0; wr_index<=0; rd_index<=0; ram_q<=0;
            m_axis_tdata<=0; m_axis_tuser<=0; m_axis_tvalid<=0; m_axis_tlast<=0;
            line_done<=0; capture_error<=0;
        end else begin
            line_done<=0;
            case(state)
                IDLE: if (arm) begin
                    capture_error<=0;
                    if (record_samples==0 || record_samples>MAX_SAMPLES) capture_error<=1;
                    else begin count_r<=record_samples; m_axis_tuser<=line_id; state<=ARMED; end
                end
                ARMED: if (trigger) begin
                    // Sample zero is the PHY word on this edge. Calibrate latency.
                    ram[0]<=adc_valid ? adc_data : {DATA_WIDTH{1'b0}};
                    if (!adc_valid) capture_error<=1;
                    wr_index<=1; rd_index<=0;
                    state<=count_r==1 ? READ : CAPTURE;
                end
                CAPTURE: begin
                    // Preserve the clock-time axis even if an ADC word is missing.
                    ram[wr_index]<=adc_valid ? adc_data : {DATA_WIDTH{1'b0}};
                    if (!adc_valid) capture_error<=1;
                    if (wr_index==count_r-1) begin rd_index<=0; state<=READ; end
                    else wr_index<=wr_index+1'b1;
                end
                READ: begin ram_q<=ram[rd_index]; state<=LOAD; end
                LOAD: begin
                    m_axis_tdata<={{(16-DATA_WIDTH){ram_q[DATA_WIDTH-1]}},ram_q};
                    m_axis_tvalid<=1; m_axis_tlast<=rd_index==count_r-1; state<=SEND;
                end
                SEND: if (m_axis_tready) begin
                    m_axis_tvalid<=0; m_axis_tlast<=0;
                    if (rd_index==count_r-1) begin state<=IDLE; line_done<=1; end
                    else begin rd_index<=rd_index+1'b1; state<=READ; end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
