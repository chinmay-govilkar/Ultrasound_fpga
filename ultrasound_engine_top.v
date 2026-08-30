`timescale 1ns / 1ps

module ultrasound_engine_top #(
    parameter PIXELS_PER_FRAME = 65536 // Example: A 256x256 pixel image
)(
    input  wire        clk,
    input  wire        rst_n,

    // Raw FMC150 ADC Inputs
    input  wire        adc_we,
    input  wire [4:0]  current_line,
    input  wire [9:0]  write_addr,
    input  wire [13:0] adc_data_in,

    // Target Pixel Input from Processor
    input  wire signed [15:0] target_focal_x,
    input  wire signed [15:0] target_focal_z,

    // AXI4-Stream Master Output (To DMA -> Processor RAM)
    output wire [31:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    output wire        m_axis_tlast,
    input  wire        m_axis_tready
);

    // Wires from Beamformer to Envelope Detector
    wire [31:0] raw_rf_pixel;
    wire        pixel_valid;

    // 1. Instantiate Your Massive Hardware Beamformer
    das_beamformer_top beamformer_inst (
        .clk(clk),
        .we(adc_we),
        .current_line(current_line),
        .write_addr(write_addr),
        .data_in(adc_data_in),
        .target_focal_x(target_focal_x),
        .target_focal_z(target_focal_z),
        .final_pixel_intensity(raw_rf_pixel),
        .pixel_valid(pixel_valid)
    );

    // 2. Envelope Detector & AXI Stream Packager
    reg [31:0] abs_val;
    reg        valid_reg;
    reg        last_reg;
    reg [31:0] pixel_counter;

    always @(posedge clk) begin
        if (!rst_n) begin
            abs_val <= 0;
            valid_reg <= 0;
            last_reg <= 0;
            pixel_counter <= 0;
        end else begin
            if (pixel_valid && m_axis_tready) begin
                // Envelope Detection (Absolute Value)
                if (raw_rf_pixel[31] == 1'b1) // If negative
                    abs_val <= (~raw_rf_pixel + 1'b1); // Two's complement
                else
                    abs_val <= raw_rf_pixel;
                
                valid_reg <= 1'b1;

                // TLAST logic: Tell the DMA when the image frame is finished!
                if (pixel_counter == PIXELS_PER_FRAME - 1) begin
                    last_reg <= 1'b1;
                    pixel_counter <= 0;
                end else begin
                    last_reg <= 1'b0;
                    pixel_counter <= pixel_counter + 1;
                end
            end else begin
                valid_reg <= 1'b0;
                last_reg <= 1'b0;
            end
        end
    end

    assign m_axis_tdata  = abs_val;
    assign m_axis_tvalid = valid_reg;
    assign m_axis_tlast  = last_reg;

endmodule