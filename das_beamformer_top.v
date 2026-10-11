`timescale 1ns/1ps
// Optional sequential gather/interpolate/sum: rectangular unnormalised signed DAS.
// Supply NUM_LINES descriptors per pixel, ordered by line number. TLAST marks
// the final descriptor of EACH PIXEL. Output TLAST marks the final FRAME pixel.
// Memory is external (DDR adapter or small das_memory_matrix), one request at a time.
// Descriptors=Python export_delay_table, explicit addr0,addr1,Q-fraction,valid.
// protocol_error is sticky: discard the frame on any malformed descriptor.
module das_beamformer_top #(
    parameter NUM_LINES=25,DATA_WIDTH=16,ADDR_WIDTH=16,
    parameter LINE_WIDTH=(NUM_LINES>1 ? $clog2(NUM_LINES) : 1),FRAC_BITS=12,OUTPUT_WIDTH=32,
    parameter PIXELS_PER_FRAME=241*401
)(
    input wire clk,rst_n,s_axis_tvalid,
    output wire s_axis_tready,
    input wire [LINE_WIDTH-1:0] s_axis_line,
    input wire [ADDR_WIDTH-1:0] s_axis_addr0,s_axis_addr1,
    input wire [FRAC_BITS-1:0] s_axis_fraction,
    input wire s_axis_sample_valid,s_axis_tlast,
    output wire mem_req_valid,
    input wire mem_req_ready,
    output reg [LINE_WIDTH-1:0] mem_req_line,
    output reg [ADDR_WIDTH-1:0] mem_req_addr0,mem_req_addr1,
    input wire mem_rsp_valid,
    output wire mem_rsp_ready,
    input wire signed [DATA_WIDTH-1:0] mem_rsp_data0,mem_rsp_data1,
    output reg signed [OUTPUT_WIDTH-1:0] m_axis_tdata,
    output reg m_axis_tvalid,m_axis_tlast,
    input wire m_axis_tready,
    output reg protocol_error
);
    localparam ACCEPT=0,REQUEST=1,RESPONSE=2,ZERO=3,INTERP=4,HOLD=5;
    localparam INTERP_WIDTH=DATA_WIDTH+FRAC_BITS+2;
    localparam ACC_WIDTH=INTERP_WIDTH+$clog2(NUM_LINES);
    localparam signed [ACC_WIDTH-1:0] ROUND=
        {{(ACC_WIDTH-1){1'b0}},1'b1} << (FRAC_BITS-1);
    reg [2:0] state;
    reg [LINE_WIDTH-1:0] channel_count;
    reg [31:0] pixel_count;
    reg [FRAC_BITS-1:0] fraction_r;
    reg signed [ACC_WIDTH-1:0] accumulator;
    wire signed [INTERP_WIDTH-1:0] interp_value;
    wire interp_valid;
    wire input_interp_valid=(state==RESPONSE && mem_rsp_valid) || state==ZERO;
    wire signed [DATA_WIDTH-1:0] input0=state==ZERO ? {DATA_WIDTH{1'b0}} : mem_rsp_data0;
    wire signed [DATA_WIDTH-1:0] input1=state==ZERO ? {DATA_WIDTH{1'b0}} : mem_rsp_data1;
    wire signed [ACC_WIDTH-1:0] extended=
        {{(ACC_WIDTH-INTERP_WIDTH){interp_value[INTERP_WIDTH-1]}},interp_value};
    wire signed [ACC_WIDTH-1:0] total=accumulator+extended;
    assign s_axis_tready=state==ACCEPT;
    assign mem_req_valid=state==REQUEST;
    assign mem_rsp_ready=state==RESPONSE;
    das_single_channel #(.DATA_WIDTH(DATA_WIDTH),.FRAC_BITS(FRAC_BITS)) interp(
        .clk(clk),.rst_n(rst_n),.input_valid(input_interp_valid),
        .sample0(input0),.sample1(input1),.fraction(fraction_r),
        .interpolated_scaled(interp_value),.output_valid(interp_valid)
    );
    always @(posedge clk) begin
        if (!rst_n) begin
            state<=ACCEPT; channel_count<=0; pixel_count<=0; accumulator<=0;
            fraction_r<=0; mem_req_line<=0; mem_req_addr0<=0; mem_req_addr1<=0;
            m_axis_tdata<=0; m_axis_tvalid<=0; m_axis_tlast<=0; protocol_error<=0;
        end else begin
            case(state)
                ACCEPT: if (s_axis_tvalid) begin
                    if (s_axis_line!=channel_count ||
                        s_axis_tlast!=(channel_count==NUM_LINES-1)) protocol_error<=1;
                    mem_req_line<=s_axis_line; mem_req_addr0<=s_axis_addr0;
                    mem_req_addr1<=s_axis_addr1; fraction_r<=s_axis_fraction;
                    state<=s_axis_sample_valid ? REQUEST : ZERO;
                end
                REQUEST: if (mem_req_ready) state<=RESPONSE;
                RESPONSE: if (mem_rsp_valid) state<=INTERP;
                ZERO: state<=INTERP;
                INTERP: if (interp_valid) begin
                    if (channel_count==NUM_LINES-1) begin
                        m_axis_tdata<=(total+ROUND) >>> FRAC_BITS;
                        m_axis_tvalid<=1; m_axis_tlast<=pixel_count==PIXELS_PER_FRAME-1;
                        state<=HOLD; accumulator<=0; channel_count<=0;
                    end else begin
                        accumulator<=total; channel_count<=channel_count+1'b1; state<=ACCEPT;
                    end
                end
                HOLD: if (m_axis_tready) begin
                    m_axis_tvalid<=0; m_axis_tlast<=0;
                    pixel_count<=pixel_count==PIXELS_PER_FRAME-1 ? 0 : pixel_count+1'b1;
                    state<=ACCEPT;
                end
                default: state<=ACCEPT;
            endcase
        end
    end
endmodule
