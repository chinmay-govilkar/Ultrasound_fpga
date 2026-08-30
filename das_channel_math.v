`timescale 1ns / 1ps

module das_channel_math #(
    parameter COORD_WIDTH = 16  // 16-bit precision for spatial coordinates
)(
    input  wire                   clk,
    
    // Coordinates for the current pixel we want to draw
    input  wire signed [COORD_WIDTH-1:0] focal_x,  // X-coordinate of the pixel
    input  wire signed [COORD_WIDTH-1:0] focal_z,  // Depth (Z) of the pixel
    
    // Coordinate of this specific transducer position
    input  wire signed [COORD_WIDTH-1:0] transducer_x,
    
    // Output: The squared distance (X^2 + Z^2) ready for the Square Root engine
    output reg  unsigned [(COORD_WIDTH*2)-1:0] distance_squared
);

    // Pipeline Registers to ensure high clock speeds (100MHz+)
    reg signed [COORD_WIDTH-1:0] dx;
    reg signed [COORD_WIDTH-1:0] dz;
    
    reg signed [(COORD_WIDTH*2)-1:0] dx_sq;
    reg signed [(COORD_WIDTH*2)-1:0] dz_sq;

    always @(posedge clk) begin
        // Stage 1: Calculate the distance differences
        dx <= focal_x - transducer_x;
        dz <= focal_z; // Z distance is just the depth, assuming transducer is at Z=0

        // Stage 2: Calculate the squares (Vivado will route these to DSP48 Slices!)
        dx_sq <= dx * dx;
        dz_sq <= dz * dz;

        // Stage 3: Sum the squares (A^2 + B^2)
        distance_squared <= $unsigned(dx_sq + dz_sq);
    end

endmodule