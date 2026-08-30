fmc150_axi_capture.v: Active ISERDES front-door deserializer catching the 250 MSPS LVDS stream and formatting it for AXI4-Stream.
das_memory_matrix.v: Active parallel memory holding the 25 synthetic aperture echo lines across 25 BRAM banks.
das_channel_math.v: Active DSP48 pipelined math engine calculating $(X^2 + Z^2)$ Pythagorean delays.
das_single_channel.v: Active wrapper pairing das_channel_math with the Xilinx CORDIC square-root IP.
das_beamformer_top.v: Active "God Module" stamping 25 physical channels and summing focal echo pixels in a single clock cycle.
ultrasound_engine_top.v: Active top-level container packaging the deserializer and beamformer into the final Custom IP block for your Vivado Block Design. 
