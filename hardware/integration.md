# Eclypse Z7 and Zmod Scope 1410-105 integration

Use the current Digilent ZmodScopeController, whose output contract was checked
against vendor HDL commit `f4613fff005b098065fd5d619a2b88e55720a423`. This repository
contains tested acquisition and optional compute logic downstream of that IP.
The vendor PHY, board pins, PS driver and full Vivado project are integration work.

## Board and clock configuration

The carrier is Eclypse Z7, FPGA XC7Z020-1CLG484C, with 1 GiB DDR3L. Install the
1410-105 module on the chosen SYZYGY port and use the corresponding Digilent
Eclypse board files and reference constraints. Do not reuse ZedBoard FMC XDC.
The Zmod uses AD9648, two physical 14-bit inputs; this scan uses one input across
25 sequential positions. Its rated maximum is 105 MSPS.

This profile uses **100 MSPS**, a 10 ns sample period. For the current controller:

| Setting or clock | Value |
| --- | --- |
| kZmodID | 0 selects Scope 1410-105 |
| kADC_Width | 14 selected by the module variant |
| kSamplingPeriod | 10000 picoseconds |
| kADC_ClkDiv | 1 for this profile |
| SysClk100 | 100 MHz configuration domain |
| ADC_SamplingClk | 100 MHz capture and calibrated-output domain |
| ADC_InClk | 100 MHz with divider 1; preserve required vendor clock phase and routing |
| ZmodDcoClk | ADC-generated clock; use vendor IDDR and synchronization FIFO |

The vendor clock rule is ADC_InClk / ADC_SamplingClk = kADC_ClkDiv. A reference
project may use divider 4 and different clocks; changing only the nominal period
parameter will not configure those clocks. `eclypse_scope_config.tcl` sets the
controller's variant and 100 MSPS parameters in an existing BD. Configure Clock
Wizard outputs, phase and derived constraints separately, then validate the BD
and measure the acquisition rate. Preserve the vendor clocking and generated
I/O timing implementation for the installed IP version. Do not assume the current
low-level filter example is 100 MSPS; the checked revision configured 40 MSPS.

Keep SysClk100 at 100 MHz if experimenting with a verified sample clock up to
105 MSPS. ADC_SamplingClk, ADC_InClk/divider, sampling-period parameter, XDC and
acquisition Fs must agree. Integer-picosecond rounding is not an exact 105 MHz
clock declaration. Store the actual implemented rate, not the product label.

## Controller configuration and sample format

Use the vendor SPI/configuration logic, IDDR/FIFO data path and factory processed
gain/offset coefficients from SYZYGY DNA for each channel and gain. Enable the
external calibration and relay control interfaces, connect them to the vendor
configuration IP/software, and select the actual gain and coupling. Reset and
wait for initialization and relay settling. Do not feed raw EEPROM float values
directly into the controller's coefficient ports.

The current controller's cDataAxisTdata is `{signed_CH1[15:0],signed_CH2[15:0]}`.
These are calibrated 16-bit results, not right-aligned raw 14-bit ADC codes.
`zmod_scope_adapter` preserves the selected int16 value. The converter is still
14-bit; calibration scaling does not create additional analogue resolution.
Legacy ZmodADC1410_Controller output is a separate data format and is unsupported
at this boundary. Migrate the IP or write and verify an explicit legacy adapter.

Once configured, assert sEnableAcquisition and keep it asserted as required by
the controller. Wait for continuous valid output before arming. Its shallow FIFO
cannot absorb DMA stalls. Our cDataAxisTready is permanently high, accepting and
discarding samples outside the selected echo window. **Never connect downstream
DMA TREADY directly to the Zmod controller.**

## Capture top wiring

All top inputs other than the controller's already synchronous data must also be
synchronous to **ADC_SamplingClk**, connected to `adc_clk`.

| Port | Meaning |
| --- | --- |
| cDataAxisTdata / cDataAxisTvalid | Current controller calibrated data and valid, same sample clock |
| cDataAxisTready | Always high; wire to controller ready |
| receiver_channel | 0 selects physical CH1 upper half; 1 selects CH2 lower half; latched with accepted arm |
| source_ready | Synchronized ADC and relay initialized, clocks locked, reset complete and stream settled |
| source_error | Synchronized controller overflow/configuration/clock failure status |
| rst_n | Capture-domain synchronous reset; coordinate resets with vendor and CDC blocks |
| arm / arm_ready | Command accepted when both high; source status gates readiness |
| record_samples | 1..16384, latched with arm; 8000 for 80 us at 100 MSPS |
| line_id | 0..24, stable with arm; host records measured scan identity |
| trigger / armed | One capture-domain event after armed, tied to the transmit timing reference |
| m_axis_* | Selected signed int16, TKEEP=11, TLAST at end of line, TUSER=line_id |
| busy / line_done / capture_error | Local completion and error state; host must also await DMA completion |

Vendor sInitDoneADC, sInitDoneRelay, sDataOverflow and sConfigError belong to
SysClk100. Synchronize status into the capture domain even if both clocks have
nominally the same rate. Do not directly connect an asynchronous pulse. Use a
request/acknowledgement CDC for PS arm commands and multibit configuration,
synchronize levels appropriately and release resets synchronously in each domain.
The top does not implement that CDC or the PS register bank.

Sample zero is the calibrated word at the trigger edge, including converter,
FIFO, calibration, receive-chain and trigger-path latency. Measure the effective
timing origin with a stationary reflector, repeat at another depth, and assign
latency once to t0 or system_delay. No FMC150/ADS62P49 latency applies here.
Keep capture cadence uniform: a missing valid word occupies its clock index as
zero and sets capture_error. Any source_error while armed/capturing also sets the
error. Discard and reacquire that line, restoring vendor initialization if needed.

## DMA and the mechanical scan

1. Initialize the board, module, calibration, relay state and continuously running
   sample stream. Verify ADC test patterns and a small known sine wave.
2. Move the transducer, wait for settling and record measured x,z. Program a
   DMA-safe S2MM receive buffer before arming and firing.
3. Submit stable channel, line_id and record_samples through the control CDC;
   wait for arm_ready, accept arm and await armed. Issue the shared trigger/TX event.
4. The capture stores all N samples before draining. Use an AXIS Clock Converter
   if DMA runs on another clock and width conversion if required; preserve
   TKEEP/TLAST. Connect DMA to DDR through a PS HP port.
5. Await both local line_done and DMA completion, perform cache maintenance and
   reject controller/capture/DMA errors. Store Fs, gain/coupling, physical channel,
   line identity, positions and calibrated timing alongside the RF.
6. Repeat for all 25 positions, then reconstruct. Basic DMA does not save TUSER
   into DDR; the host must keep and verify scan metadata independently.

Default S2MM length is 16000 bytes per line. At 105 MSPS an 80 us line is
16800 bytes; a 14-bit DMA length field cannot express it. Set the DMA Buffer
Length Register width to at least **16** to support the maximum 32768-byte
16384-sample line (maximum field value must exceed 32768). Set S2MM transfer
length to the actual captured byte count; its TLAST must agree with the final beat.
The full default frame is 400000 bytes selected-channel, or 800000 bytes if
separately recording both calibrated channels in the vendor 32-bit format.

The single reusable buffer drains in about three sample-clock cycles per word,
roughly 240 us for an 80 us record without stalls. It is suitable for mechanical
scans; it is not a continuous recorder. ADC input continues to be accepted while
that line drains. Do not rearm until idle and completed buffers have been handled.

## Optional DAS accelerator

The 16-bit default now matches calibrated Zmod RF. At 25 full-scale contributions,
signed sums range from -819200 to +819175, requiring 21 signed bits. The Q12 core
retains fractional and guard bits then rounds once to signed 32-bit output.
No absolute value occurs before addition. Memory must return signed 16-bit
samples and validate addresses against the actual acquired record length.

Descriptors are pixel-major, z row then x column then line 0..24. Each carries
addr0, addr1, Q12 fraction, validity and line. Descriptor TLAST marks the final
position of **each pixel**; output TLAST marks the final frame pixel. A DMA unpacker
must implement that distinction. One memory request may be outstanding. Hold
requests, responses and output through stalls; reject protocol/address errors.

Stage 1 stores RF in DDR and reconstructs in Python. The default 25x8000 int16
frame contains 3.2 Mbit and is below XC7Z020's nominal 5.16 Mbit BRAM capacity,
but a deliberately implemented 25x8192 layout needs roughly 100 RAMB36 blocks,
before other logic. At 105 MSPS, rounding each 8400-word line up to 16384 would
need about 200 blocks and would exceed 140. Other memory layouts can differ.
Do not enlarge the diagnostic matrix silently; budget the actual mapping.
The optional core still needs DDR access, descriptor unpacking and PS control.
Its real RF sum does not implement analytic envelope or coherence weighting.

## Physical bringup

Use Eclypse board support and module reference constraints for the selected port,
including SYZYGY DNA/power negotiation, voltage standards, returned DCO, DDR lane
order, input timing and vendor generated clocks. Run Vivado DRC, CDC and post-route
timing at the actual sample clock. The OOC script constrains only the downstream
sample domain at 10 ns on xc7z020clg484-1; it is not a board bitstream flow.

Zmod's nominal high-gain range is +/-1 V and low-gain range +/-25 V. Select gain
based on the protected receiver output, and verify analogue bandwidth, anti-alias
filtering, clipping and T/R recovery. The scope input is not a direct connection
for a high-voltage ultrasound pulser. Input gain, coupling and protection must
remain consistent across the scan; include any gain changes in calibration.

Primary references checked 11 October 2026:
[Eclypse](https://digilent.com/shop/eclypse-z7/),
[Scope 1410](https://digilent.com/shop/zmod-scope-1410-2-channel-14-bit-oscilloscope-module/),
[current controller guide](https://github.com/Digilent/vivado-library/blob/f4613fff005b098065fd5d619a2b88e55720a423/ip/Zmods/ZmodScopeController/docs/ZmodScopeController.pdf),
[controller HDL](https://github.com/Digilent/vivado-library/blob/f4613fff005b098065fd5d619a2b88e55720a423/ip/Zmods/ZmodScopeController/src/ZmodScopeController.vhd),
[module variant map](https://github.com/Digilent/vivado-library/blob/f4613fff005b098065fd5d619a2b88e55720a423/ip/Zmods/ZmodScopeController/src/PkgZmodADC.vhd),
[Eclypse low-level reference](https://github.com/Digilent/Eclypse-Z7-HW/tree/5ea221a3fceb430d7b3005d49ce373cb10bea154),
[AMD AXI DMA PG021](https://docs.amd.com/r/en-US/pg021_axi_dma/User-Parameters).
