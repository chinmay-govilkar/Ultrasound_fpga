`timescale 1ns/1ps
// Optional geometry diagnostic, NOT an address generator. Output units=length^2.
// Software computes (Tx distance+Rx distance)/c, timing calibration, then Fs.
module das_channel_math #(parameter COORD_WIDTH=18)(
    input wire clk,rst_n,input_valid,
    input wire signed [COORD_WIDTH-1:0] focal_x,focal_z,transducer_x,transducer_z,
    output reg [2*COORD_WIDTH+2:0] distance_squared,
    output reg output_valid
);
    localparam DIFF_WIDTH=COORD_WIDTH+1,SQUARE_WIDTH=2*DIFF_WIDTH;
    reg signed [DIFF_WIDTH-1:0] dx,dz;
    reg [SQUARE_WIDTH-1:0] dx_sq,dz_sq;
    reg v0,v1;
    always @(posedge clk) begin
        if (!rst_n) begin
            dx<=0; dz<=0; dx_sq<=0; dz_sq<=0; distance_squared<=0;
            v0<=0; v1<=0; output_valid<=0;
        end else begin
            v0<=input_valid; v1<=v0; output_valid<=v1;
            if (input_valid) begin
                dx<=$signed({focal_x[COORD_WIDTH-1],focal_x})-
                    $signed({transducer_x[COORD_WIDTH-1],transducer_x});
                dz<=$signed({focal_z[COORD_WIDTH-1],focal_z})-
                    $signed({transducer_z[COORD_WIDTH-1],transducer_z});
            end
            if (v0) begin dx_sq<=dx*dx; dz_sq<=dz*dz; end
            if (v1) distance_squared<={1'b0,dx_sq}+{1'b0,dz_sq};
        end
    end
endmodule
