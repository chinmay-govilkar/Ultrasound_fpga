`timescale 1ns / 1ps

module das_beamformer_top #(
    parameter NUM_LINES = 25,       // Your 25 mechanical transducer positions
    parameter DATA_WIDTH = 14,      // 14-bit data from the FMC150 ADC
    parameter DEPTH_BITS = 10,      // 1024 depth samples
    parameter COORD_WIDTH = 16,     // 16-bit precision for coordinates
    parameter ELEMENT_PITCH = 500   // 500 micrometers (0.5mm) between mechanical steps
)(
    input wire clk,

    // --- Phase 1: Data Capture Inputs (From FMC150) ---
    input wire we,
    input wire [4:0] current_line,
    input wire [DEPTH_BITS-1:0] write_addr,
    input wire [DATA_WIDTH-1:0] data_in,

    // --- Phase 2: Beamforming Control (From ARM Processor) ---
    // The processor tells the FPGA: "Calculate the focus for this specific pixel"
    input wire signed [COORD_WIDTH-1:0] target_focal_x,
    input wire signed [COORD_WIDTH-1:0] target_focal_z,

    // --- Phase 3: Final Output ---
    output reg [31:0] final_pixel_intensity,
    output reg        pixel_valid
);

    // Massive internal wiring buses to connect our 25 math engines to our 25 memory banks
    wire [(NUM_LINES * DEPTH_BITS)-1 : 0] massive_address_bus;
    wire [(NUM_LINES * DATA_WIDTH)-1 : 0] massive_data_bus;
    wire [NUM_LINES-1:0]                  valid_flags;

    // 1. Instantiate the Memory Matrix (The 25 parallel BRAMs)
    das_memory_matrix #(
        .NUM_LINES(NUM_LINES), .DATA_WIDTH(DATA_WIDTH), .DEPTH_BITS(DEPTH_BITS)
    ) memory_matrix_inst (
        .clk(clk),
        .we(we),
        .current_line(current_line),
        .write_addr(write_addr),
        .data_in(data_in),
        .delay_read_addrs(massive_address_bus), // Input: The 25 calculated addresses
        .das_data_out(massive_data_bus)         // Output: The 25 raw echo samples
    );

    // 2. Instantiate 25 parallel Focal Delay Engines
    genvar i;
    generate
        for (i = 0; i < NUM_LINES; i = i + 1) begin : focal_channels
            
            // Calculate the physical X position of this specific transducer step
            // (e.g., Step 0 = 0um, Step 1 = 500um, Step 2 = 1000um)
            wire signed [COORD_WIDTH-1:0] physical_x_pos = i * ELEMENT_PITCH;

            // Temporary wire to catch the calculated 16-bit address from the CORDIC
            wire [15:0] calc_address;

            // Stamp out one math engine for this specific position
            das_single_channel #(
                .COORD_WIDTH(COORD_WIDTH)
            ) delay_engine_inst (
                .clk(clk),
                .focal_x(target_focal_x),
                .focal_z(target_focal_z),
                .transducer_x(physical_x_pos),
                .read_address(calc_address),
                .address_valid(valid_flags[i])
            );

            // Assign the bottom 10 bits (our BRAM depth) to the massive address bus
            assign massive_address_bus[(i+1)*DEPTH_BITS-1 +: i*DEPTH_BITS] = calc_address[DEPTH_BITS-1:0];
        end
    endgenerate

// 3. The "Sum" in Delay-and-Sum
    integer j;
    reg [31:0] accumulator;

    always @(posedge clk) begin
        // Only sum the data if the CORDIC square root math is finished
        if (valid_flags[0]) begin
            accumulator = 0;
            
            // Instantly loop through all 25 BRAM outputs and add them together
            for (j = 0; j < NUM_LINES; j = j + 1) begin
                // FIXED: Using the +: operator for variable part-select
                accumulator = accumulator + massive_data_bus[ (j*DATA_WIDTH) +: DATA_WIDTH ];
            end
            
            final_pixel_intensity <= accumulator;
            pixel_valid <= 1'b1;
        end else begin
            pixel_valid <= 1'b0;
        end
    end
    endmodule