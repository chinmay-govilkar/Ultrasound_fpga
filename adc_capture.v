`timescale 1ns / 1ps

module adc_capture (
    input wire clk_adc,            // 65 MHz Clock from AD9226
    input wire [11:0] adc_data_in, // Raw 12-bit parallel data
    output reg [11:0] adc_data_out // Synchronized output
);

    // Xilinx directive: Use flip-flops close to the pins so that there are no errors due to wires being of different lengths in the fpga
    (* IOB = "TRUE" *) reg [11:0] iob_data_reg;

    always @(posedge clk_adc) begin
        iob_data_reg <= adc_data_in;
        adc_data_out <= iob_data_reg; // Pipeline stage for stability
    end

endmodule