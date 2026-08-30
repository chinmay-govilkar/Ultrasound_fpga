`timescale 1ns / 1ps

module das_single_channel #(
    parameter COORD_WIDTH = 16
)(
    input  wire clk,
    
    // The target pixel coordinate
    input  wire signed [COORD_WIDTH-1:0] focal_x,
    input  wire signed [COORD_WIDTH-1:0] focal_z,
    
    // The specific transducer's physical location
    input  wire signed [COORD_WIDTH-1:0] transducer_x,

    // The Final Output: The exact address to read from the BRAM
    output wire [15:0] read_address,
    output wire        address_valid
);

    // Internal wire carrying the huge 32-bit number between the two modules
    wire [31:0] distance_squared;

    // 1. Instantiate YOUR Custom Math Module (Calculates X^2 + Z^2)
    das_channel_math #(
        .COORD_WIDTH(COORD_WIDTH)
    ) math_engine (
        .clk(clk),
        .focal_x(focal_x),
        .focal_z(focal_z),
        .transducer_x(transducer_x),
        .distance_squared(distance_squared)
    );

    // 2. Instantiate the Xilinx CORDIC Square Root IP
    // Note: AXI4-Stream buses are always padded to byte boundaries (multiples of 8).
    // Because your CORDIC output is 17 bits, Vivado will automatically pad the tdata bus to 24 bits.
    wire [23:0] cordic_out; 

    cordic_0 sqrt_engine (
        .aclk(clk),                                        // System clock
        .s_axis_cartesian_tvalid(1'b1),                    // Data is always valid in our pipeline
        .s_axis_cartesian_tdata(distance_squared),         // Plug in the 32-bit square from our math module
        .m_axis_dout_tvalid(address_valid),                // Goes HIGH when the square root is finished
        .m_axis_dout_tdata(cordic_out)                     // The padded final square root
    );

    // Extract the clean 16-bit address from the padded CORDIC output bus
    assign read_address = cordic_out[15:0];

endmodule