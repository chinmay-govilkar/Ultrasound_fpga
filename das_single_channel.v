`timescale 1ns/1ps
// Registered linear interpolation. Retain Q0.FRAC_BITS scale through the sum.
module das_single_channel #(
    parameter DATA_WIDTH=14,FRAC_BITS=12,RESULT_WIDTH=DATA_WIDTH+FRAC_BITS+2
)(
    input wire clk,rst_n,input_valid,
    input wire signed [DATA_WIDTH-1:0] sample0,sample1,
    input wire [FRAC_BITS-1:0] fraction,
    output reg signed [RESULT_WIDTH-1:0] interpolated_scaled,
    output reg output_valid
);
    localparam PRODUCT_WIDTH=DATA_WIDTH+FRAC_BITS+2;
    wire signed [FRAC_BITS+1:0] coeff1=$signed({2'b00,fraction});
    wire signed [FRAC_BITS+1:0] coeff0=$signed({2'b01,{FRAC_BITS{1'b0}}})-coeff1;
    wire signed [PRODUCT_WIDTH-1:0] p0=sample0*coeff0,p1=sample1*coeff1;
    always @(posedge clk) begin
        if (!rst_n) begin interpolated_scaled<=0; output_valid<=0; end
        else begin
            output_valid<=input_valid;
            if (input_valid) interpolated_scaled<=p0+p1;
        end
    end
endmodule
