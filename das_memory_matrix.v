`timescale 1ns/1ps
// Optional SMALL-RECORD matrix, two synchronous reads, no reads during writes.
// Full 25x20000 capture belongs in DDR. The RAM is not reset; fill before reading.
module das_memory_matrix #(
    parameter NUM_LINES=25,DATA_WIDTH=14,DEPTH_BITS=10,
    parameter LINE_WIDTH=(NUM_LINES>1 ? $clog2(NUM_LINES) : 1)
)(
    input wire clk,rst_n,we,
    input wire [LINE_WIDTH-1:0] current_line,
    input wire [DEPTH_BITS-1:0] write_addr,
    input wire signed [DATA_WIDTH-1:0] data_in,
    input wire mem_req_valid,
    output wire mem_req_ready,
    input wire [LINE_WIDTH-1:0] mem_req_line,
    input wire [DEPTH_BITS-1:0] mem_req_addr0,mem_req_addr1,
    output reg mem_rsp_valid,
    input wire mem_rsp_ready,
    output reg signed [DATA_WIDTH-1:0] mem_rsp_data0,mem_rsp_data1,
    output reg address_error
);
    localparam LINE_DEPTH=1<<DEPTH_BITS;
    (* ram_style="block" *) reg signed [DATA_WIDTH-1:0] ram[0:NUM_LINES*LINE_DEPTH-1];
    wire req_fire=mem_req_valid && mem_req_ready;
    assign mem_req_ready=!we && (!mem_rsp_valid || mem_rsp_ready);
    // Port A: write OR read0. Port B: read1. Avoid three-port RAM.
    always @(posedge clk) begin
        if (we && current_line<NUM_LINES) ram[{current_line,write_addr}]<=data_in;
        else if (req_fire)
            mem_rsp_data0<=mem_req_line<NUM_LINES ? ram[{mem_req_line,mem_req_addr0}] : 0;
        if (req_fire)
            mem_rsp_data1<=mem_req_line<NUM_LINES ? ram[{mem_req_line,mem_req_addr1}] : 0;
    end
    always @(posedge clk) begin
        if (!rst_n) begin mem_rsp_valid<=0; address_error<=0; end
        else begin
            if (mem_rsp_valid && mem_rsp_ready) mem_rsp_valid<=0;
            if (req_fire) begin
                mem_rsp_valid<=1;
                if (mem_req_line>=NUM_LINES) address_error<=1;
            end
            if (we && current_line>=NUM_LINES) address_error<=1;
        end
    end
endmodule
