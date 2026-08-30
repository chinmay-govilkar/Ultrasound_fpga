`timescale 1ns / 1ps

module bram_buffer (
    input wire clk_write,         // 125 MHz clock from ISERDES
    input wire we,                // Write Enable
    input wire [8:0] write_addr,  // 512 addresses (0 to 511)
    input wire [27:0] data_in,    // 28-bit data in (two 14-bit samples)

    input wire clk_read,          // Standard System Clock (e.g. 100 MHz)
    input wire [8:0] read_addr,   // 512 addresses (0 to 511)
    output reg [27:0] data_out    // 28-bit data out
);

    // Infer Block RAM (512 rows, 28 bits wide)
    reg [27:0] ram [0:511];

    // Write Port (High Speed from ADC)
    always @(posedge clk_write) begin
        if (we) begin
            ram[write_addr] <= data_in;
        end
    end

    // Read Port (Slower Speed for Processor/DMA)
    always @(posedge clk_read) begin
        data_out <= ram[read_addr];
    end

endmodule