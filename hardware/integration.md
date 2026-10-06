# ZedBoard / FMC150 integration contract

This file describes the remaining board integration; it does not supply a
fabricated FMC150 pin map or an already tested Vivado project.

## Recommended acquisition path

1. Obtain the FMC150 board support package and exact carrier/card revision
   schematics. Configure ADC, clock generator, LVDS mode, output encoding, lane
   order and test patterns. Capture one signed 14-bit word per sampling clock.
   Verify with ramp/checkerboard patterns and a known low-amplitude RF sine wave.
2. Feed that word and its sample-domain clock into `ultrasound_engine_top`.
   Every capture/control input is synchronous to `adc_clk`. ADC and control
   cannot be driven by unrelated clock domains directly. Release reset
   synchronously. Use a request/acknowledgement CDC for ARM arm commands and
   stable configuration; synchronise status separately. A two-flop synchroniser
   alone does not transport an arbitrary one-cycle pulse or multibit command.
3. Connect 16-bit capture AXIS to an AMD AXIS Clock Converter if DMA clock differs.
   Add AXIS width conversion if the chosen DMA/IP stream width requires it.
   Preserve `TKEEP` and `TLAST`. The entire line is buffered before transmission,
   so DMA backpressure never stops the ADC sampling window.
4. Configure DMA S2MM to PS DDR through an AXI HP port. Allocate a DMA-safe buffer,
   handle cache maintenance/driver ownership, and program reception before firing.
   Set Buffer Length Register width to at least 17 for maximum 32768-sample,
   65536-byte lines (or a larger supported width). The common 14-bit default
   cannot describe a 40000-byte, 20000-sample line [AMD PG021].
5. ARM controls stage motion and the shared transmit/capture timing event. At each
   position: move -> settle -> program DMA -> wait arm_ready -> pulse arm with
   record_samples and line_id stable -> wait armed -> issue sample-clock trigger
   and TX event -> wait line_done and DMA completion -> inspect capture_error ->
   invalidate/read the completed buffer -> store metadata -> continue.
6. `line_done` means final AXIS beat accepted locally. With a downstream clock
   converter/FIFO, this is earlier than DDR completion; await DMA completion too.
   The module ignores arm/trigger while busy. A missing ADC word is stored as zero
   at its clock-time index and capture_error is set; discard/reacquire that line.
7. Store 25 records with line_id 0..24. `TUSER` identifies the line in the stream;
   basic DMA does not automatically save that metadata into DDR. Keep expected
   line identity and recorded position/timing in the ARM-side acquisition file.
8. Reconstruct only after all valid records are complete. Copy the 1 MB dataset to
   a PC first, or install numerical dependencies on an ARM Linux system later.

## Capture ports

| Port group | Required meaning |
| --- | --- |
| adc_clk, adc_data, adc_valid | One recovered, centred signed RF sample per clock; continuous sample cadence |
| rst_n | Synchronous reset in this module; coordinate reset across external CDC blocks |
| arm / arm_ready | A command is accepted on a rising clock edge when both are high |
| record_samples | 1..MAX_SAMPLES, latched with arm; default capacity 32768 |
| line_id | Stable with arm; host enforces physical scan order 0..24 |
| trigger / armed | One synchronous timing pulse after armed; same timing reference as TX |
| m_axis_* | 16-bit sign-extended RF; two valid bytes; TLAST on final sample; user=line_id |
| busy, line_done, capture_error | No new line until idle; completion plus line validity status |

Sample zero is the PHY word presented at the trigger edge. ADS62P49 pipeline
latency is 22 converter cycles; at 250 MSPS this is 88 ns before PHY/analogue
latency. Measure the effective echo origin. Assign each latency to either the
sample-origin convention or system_delay, once. A transmit-aligned digital
counter alone does not identify the analogue instant sampled by that word.

## Optional DAS core

Descriptors are pixel-major: z row outermost, x column inside, then line 0..24.
Each descriptor contains two in-range sample addresses, Q0.12 fractional weight,
line, sample_valid, and last-position marker. Its `s_axis_tlast` is the last
descriptor of **each pixel**, not the end of a whole-image DMA packet. An AXIS
packing/DMA adapter must implement this convention explicitly.

One request may be outstanding. Hold memory request fields while valid and not
ready; return both signed samples with response valid until response ready.
Out-of-record descriptors have sample_valid=0 and request no memory. An adapter
must validate addresses against the actual acquired length, not only the address
bus width. Matrix address_error and core protocol_error require frame rejection.

Output is one signed 32-bit RF sum per pixel, with TLAST at PIXELS_PER_FRAME.
Default pixel count is 241*401=96641. Compare to Python signed_rf with rectangular
weights and normalize=False, allowing fixed-point/rounding error. Fractions are
rounded in Q12; the accumulated result rounds half-up once after 25 contributions.

The optional core lacks a DDR master, descriptor DMA unpacker and board-level
control wrapper. `das_memory_matrix` provides a synchronous small-record adapter
for simulation/integration. Never scale its default 1024-sample demonstration
silently into 25x32768 on the XC7Z020. Full-rate records belong in DDR. Prefer
anti-aliased RF decimation or IQ plus deliberate scaling before a BRAM accelerator.

## Required board checks

Confirm VADJ/IOSTANDARD against both revision schematics and the vendor BSP;
connector mating does not establish electrical compatibility. Use the forwarded
ADC clock, verified even/odd DDR lane ordering, calibrated input delays, proper
termination and ADC test mode. Set real input/setup/hold and generated-clock
constraints. Check CDC, DRC, BRAM mapping, post-route timing at the actual sample
rate, and reset/clock-lock behaviour. `synth_ooc.tcl` is synthesis-only post-PHY
logic and supplies no physical ADC timing constraints.

For the receiver, verify the T/R protection, recovery time, analogue anti-alias
filter, gain and clipping with the actual pulser and transducer. ADC sample rate
alone does not provide those functions. The FMC150 input is AC-coupled; check
the installed revision's transfer response over the received RF band.

References: [FMC150](https://www.abaco.com/Products-and-Services/Digital-Signal-Processing/FPGA-Mezzanine-Cards/FMC150),
[ADS62P49 datasheet](https://www.ti.com/lit/ds/symlink/ads62p49.pdf),
[ZedBoard guide](https://files.digilent.com/resources/programmable-logic/zedboard/ZedBoard_HW_UG_v2_2.pdf),
[AMD PG021](https://docs.amd.com/r/en-US/pg021_axi_dma/User-Parameters).
