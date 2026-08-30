`timescale 1ns / 1ps

module das_memory_matrix #(
    parameter NUM_LINES = 25,       // Your 25 mechanical transducer positions
    parameter DATA_WIDTH = 14,      // 14-bit data from the FMC150 ADC
    parameter DEPTH_BITS = 10       // 10-bit address = 1024 depth samples per line
)(
    input wire clk,

    // --- WRITE PORT (From your ADC Capture Logic) ---
    input wire we,
    input wire [4:0] current_line,  // Tells the memory which of the 25 positions we are currently recording
    input wire [DEPTH_BITS-1:0] write_addr,
    input wire [DATA_WIDTH-1:0] data_in,

    // --- READ PORT (For the DAS Beamforming Engine) ---
    // A massive "packed array" containing 25 different read addresses
    input wire [(NUM_LINES * DEPTH_BITS)-1 : 0] delay_read_addrs,

    // A massive "packed array" outputting 25 data points simultaneously
    output wire [(NUM_LINES * DATA_WIDTH)-1 : 0] das_data_out
);

    // Use a Verilog Generate block to stamp out 25 physical Block RAMs
    genvar i;
    generate
        for (i = 0; i < NUM_LINES; i = i + 1) begin : scan_line_bram
            
            // Infer the internal RAM block (1024 rows of 14-bit data)
            reg [DATA_WIDTH-1:0] ram [0:(1<<DEPTH_BITS)-1];
            reg [DATA_WIDTH-1:0] out_reg;

            // 1. WRITE LOGIC
            always @(posedge clk) begin
                // Only write to this specific BRAM if the motor is at this specific position
                if (we && (current_line == i)) begin
                    ram[write_addr] <= data_in;
                end
            end

            // 2. READ LOGIC (The Beamforming Phase)
            // Unpack this specific BRAM's read address from the massive input bus
            wire [DEPTH_BITS-1:0] specific_read_addr = delay_read_addrs[(i+1)*DEPTH_BITS-1 : i*DEPTH_BITS];

            always @(posedge clk) begin
                out_reg <= ram[specific_read_addr];
            end

            // Assign this BRAM's data to its specific slice of the massive output bus
            assign das_data_out[(i+1)*DATA_WIDTH-1 : i*DATA_WIDTH] = out_reg;
            
        end
    endgenerate

endmodule