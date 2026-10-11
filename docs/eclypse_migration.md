# Eclypse Z7 migration on 11 October 2026

The selected hardware is now **Eclypse Z7 + Zmod Scope 1410-105**. The DAS acoustic
model is unchanged: one transducer transmits and receives at each of 25 positions,
and calibrated two-way delays gather/interpolate signed RF before coherent summation.
The acquisition interface, stored-word precision and sample-rate defaults changed.

## Changes applied

| Item | Previous implementation | Current implementation |
| --- | --- | --- |
| Carrier and module | ZedBoard and FMC150 | Eclypse XC7Z020-1CLG484C, 1 GiB DDR3L, SYZYGY Scope 1410-105 |
| Sample-rate default | 250 MSPS | Explicit 100 MSPS configuration; actual Fs stored per acquisition |
| ADC and output format | 14-bit ADS62P49 signed post-PHY words | Physical AD9648 14-bit; current Digilent controller calibrated signed int16 |
| Physical receiver channel | Single scalar sample boundary | CH1 upper 16 bits or CH2 lower 16 bits of controller word, latched at arm |
| Upstream flow control | Generic signed-word input | Controller TREADY always high, including idle/capture/drain |
| Capture module | fmc150_axi_capture.v, 32768 x14 buffer | adc_line_capture.v, 16384 x16 reusable buffer; new adc_error input |
| Top input | adc_data / adc_valid | cDataAxisTdata / cDataAxisTvalid / cDataAxisTready, channel and synchronized source status |
| 80 us selected-channel frame | 20000 samples per position, 1000000 bytes | 8000 samples per position, 400000 bytes at 100 MSPS |
| Optional DAS inputs | Signed 14 bits by default | Signed 16 bits; full-scale 25-position sums -819200 to +819175 |
| Python importer | Raw 16-bit file and encoding selection | Explicit signed16, scope32 and raw16 formats, channel/rate/size validation and source metadata |
| Vivado OOC timing | 4 ns | 10 ns default; FPGA part remains xc7z020clg484-1 |

`eclypse_z7.py` holds the platform constants and checked 32-bit decoder.
`zmod_scope_adapter.v` implements physical channel selection and continuous source
acceptance. `hardware/eclypse_scope_config.tcl` configures the current controller's
variant, divider and sampling-period parameters in an existing block design.
`tests/test_eclypse.py` and `tests/tb_zmod.v` add platform regressions. README,
integration instructions, review, validation and the synthetic image are updated.
The Python reconstruction loader defaults to signed 16-bit stored samples and
retains compatibility with earlier signed 14-bit and floating-point acquisitions.
Existing NPZ files retain their stored Fs and are not converted by relabelling.

## Clock and format decisions

The module's 105 MSPS rating is a maximum, not an automatic clock configuration.
100 MSPS meets the requested >60 MSPS acquisition rate. At explicitly configured
105 MSPS, an 80 us record has 8400 samples, fitting the new 16384-sample capacity.
Reconfigure and verify physical clocks, period parameters and constraints before
using a different Fs. For the default profile use ADC_SamplingClk=100 MHz,
ADC_InClk=100 MHz and kADC_ClkDiv=1, with SysClk100 still 100 MHz.

Use the **current ZmodScopeController**, checked at Digilent vivado-library commit
`f4613fff005b098065fd5d619a2b88e55720a423`. Its calibrated 16-bit words must not be
redecoded or truncated as 14-bit codes. Legacy ZmodADC1410_Controller software
examples use a different packing and need migration or a separately verified
adapter. The checked current low-level filter project ran at 40 MSPS; importing
that example unchanged would not meet the >60 MSPS requirement.

## Acquisition commands

For this repository's selected-channel DMA output:

```bash
python pack_rf.py frame.bin --samples 8000 --fs-mhz 100 --receiver-channel 1 --gain low --coupling ac --output acquisition.npz
python beamform_das.py reconstruct acquisition.npz --output-dir results/real
```

For finite records of the current controller's packed two-channel stream:

```bash
python pack_rf.py scope_frame.bin --format scope32 --receiver-channel 1 --samples 8000 --fs-mhz 100 --output acquisition.npz
```

The recommended hardware path captures one complete selected-channel A-line,
then drains to DMA and DDR. Capture cadence is fixed by ADC_SamplingClk. A missing
word keeps its index as zero and raises an error; reacquire that line. ARM controls
stage motion, settling, identity, timing metadata and cache-safe DMA buffers.
Python calculates delays, analytic RF, DAS, envelope, log display and optional
weighting. FPGA DAS acceleration remains optional until measured images validate.

## Remaining physical integration

Connect the vendor PHY, SPI configuration, calibration and relay controls; use
Eclypse board files and actual SYZYGY-port XDC; transport PS commands and vendor
status across clock domains; connect DMA with a Buffer Length Register width of
at least 16; and implement the shared transmit/capture trigger. Verify gain,
coupling, receiver protection, test patterns, measured Fs and timing calibration.
Run Vivado DRC, CDC and post-route timing and acquire a stationary phantom.
The revised Python and controller-boundary RTL are verified in software; no
on-board acquisition or routed Eclypse bitstream was tested here.

See [validation](validation.md) and the full [integration contract](../hardware/integration.md).
Vendor sources are pinned in that contract and the complete review.
