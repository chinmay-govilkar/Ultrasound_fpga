# Ultrasound DAS: repository review and implementation

Prepared for Chinmay Govilkar • 6 October 2026

Repository: chinmay-govilkar/Ultrasound_fpga. Audited base commit:
60ca7e9d2e5efb4c3410f4c75788b38b5ea6b251. All six original Verilog files and the
README were read. There was no Python implementation, Vivado project, CORDIC
configuration, SelectIO configuration, XDC, measured RF dataset or testbench in
that snapshot. The revised Python is runnable; revised RTL is functionally
simulated post-PHY logic. A verified board bitstream remains a separate milestone.

## 1. What the proposed algorithm can build

The proposed gather-and-sum operation is a valid starting point for a mechanically
scanned, monostatic synthetic aperture: one element transmits and receives at each
position, recording one RF trace. The 25 channels are 25 sequential acquisition
records, not 25 simultaneous ADC channels. Each pixel receives a contribution
from each recorded position at the correct two-way echo time.

Assumptions are a stationary target and medium during the full scan, accurately
known transmit/receive positions, coherent and repeatable transmit pulses,
calibrated timing, homogeneous sound speed, and an adequate phase-centre model
for the chosen element. The implementation supports separate TX/RX positions
for bistatic acquisitions, but it does not assume plane-wave transmission.

Mechanically moving one element does not provide ultrafast imaging of moving
anatomy. Frame time includes all moves, settling, firings and transfers. For
example, 25 positions taking 10 ms each already need about 250 ms per scan,
before other costs; that hypothetical scan gives at most about 4 frames/s.
Ultrafast plane-wave imaging needs a different transmit/receive architecture,
usually many simultaneous receivers. Jensen et al. [1] provides synthetic-aperture
background; the present 25 same-element Tx/Rx records are a restricted acquisition.

## 2. Correct timing and intensity equations

For pixel p=(x,z) and monostatic position r_k=(x_k,z_k), define R_k=norm(p-r_k).

```text
ideal_echo_time_k = 2 * R_k / c
fractional_index_k = Fs * (ideal_echo_time_k + system_delay_k - t0_k)
```

For distinct transmit and receive centres, replace 2*R_k by
norm(p-tx_k)+norm(p-rx_k). Coordinate units are metres; Fs is samples per second;
c is metres per second; all timing fields are seconds. Indices are zero-based.

`t0_k` is the time label of stored sample zero relative to the transmit reference.
Positive `system_delay_k` makes the measured echo later than the acoustic flight
time. Include ADC/PHY/analogue latency in one calibrated convention; do not add
it again if the sample-origin value already accounts for it. For a known wire
target, estimate delay from measured arrival time minus predicted acoustic time,
then confirm at another depth. Use the actual sound speed of the medium; 1540 m/s
is an example setting, not a universal value for water, plastics or a layered path.

Multiplying flight time by Fs gives a fractional coordinate, not an exact integer
sample. Default linear interpolation uses j=floor(s), alpha=s-j:

```text
value_k = (1-alpha) * RF[k,j] + alpha * RF[k,j+1]
coherent_pixel = sum_k(weight_k * value_k)
```

Nearest-sample mode uses floor(s+0.5). Negative or beyond-record sample times are
masked to zero. They never wrap around the memory, and no repeated edge sample
is inserted. At the last exact sample, interpolation uses that sample safely.

Keep positive and negative RF values through the sum. Taking absolute value
before addition destroys coherent cancellation. The returned signed_rf is useful
for RTL comparison; a signed oscillatory sum is not itself a displayed intensity.
The software computes the analytic signal of each RF trace, interpolates and
sums those complex values, then takes magnitude for the envelope. B-mode uses
20*log10(envelope/reference), clipped to the selected dynamic range. Squared
envelope would represent power; its logarithm would instead use 10*log10.
Taking absolute value once per real output pixel is not an analytic envelope.

## 3. Concrete numerical checks

Example: 25 positions x_k=(k-12)*1 mm, c=1540 m/s, Fs=250 MSPS, no timing offsets.
For pixel (0,30 mm), the centre trace index is 9740.259740, nearest index 9740.
The outer trace at x=-12 mm has index 10490.580793, nearest index 10491.

| Position magnitude (mm) | Fractional index | Nearest sample |
| --- | --- | --- |
| 0 | 9740.259740 | 9740 |
| 1 | 9745.669493 | 9746 |
| 2 | 9761.880765 | 9762 |
| 3 | 9788.839891 | 9789 |
| 4 | 9826.458409 | 9826 |
| 5 | 9874.614497 | 9875 |
| 6 | 9933.154897 | 9933 |
| 7 | 10001.897273 | 10002 |
| 8 | 10080.632920 | 10081 |
| 9 | 10169.129716 | 10169 |
| 10 | 10267.135260 | 10267 |
| 11 | 10374.380071 | 10374 |
| 12 | 10490.580793 | 10491 |

Both positive and negative positions of each magnitude use the same index for
this centred pixel. General pixels have different channel delays.

For x=-12..12 mm and z=10..50 mm, the longest two-way path is between opposite
lateral extremes at 50 mm depth: 2*sqrt(24^2+50^2) mm. It takes 72.028180 us,
or index 18007.044966. A record starting at zero needs at least 18009 samples
for that grid's interpolation support, before latency uncertainty and pulse-tail
margin. The helper required_samples computes this bound for the configured grid.
An 80 us example capture contains 20000 samples and ends at 79.996 us; that margin
is an example, not a claim about the actual element's ring-down.

## 4. Flaws found in the original repository

| Location | Defect and effect | Resolution |
| --- | --- | --- |
| das_single_channel.v | sqrt(X^2+Z^2) was used directly as a memory address. Length has no sample-time unit. Outward/return travel, c, Fs and latency were absent. | Software computes calibrated two-leg delays and exports integer/fractional descriptors. |
| das_beamformer_top.v | Address slice used [(i+1)*DEPTH_BITS-1 +: i*DEPTH_BITS]; channel zero has zero width and later slices run outside the bus. | Eliminate this invalid packing; explicit scalar line and adjacent-address request fields. |
| das_beamformer_top.v | Only the lower 10 address bits were retained, silently wrapping deeper echoes. | Explicit record bounds in Python/LUT; production data in DDR; no address truncation accepted as range handling. |
| das_beamformer_top.v | RF slices and accumulator were unsigned, making negative echoes large positive numbers. | Signed samples, interpolation products, accumulator and RF output. |
| das_memory_matrix.v and top | 1024 samples at 250 MSPS cover only 4.096 us, about 3.15 mm two-way axial range from time zero. | Whole echo-window capture; matrix retained only as a small-record adapter. |
| das_beamformer_top.v | CORDIC valid was consumed without the synchronous RAM-read latency, so data belonged to earlier addresses. Only one of 25 valids was checked. | One outstanding request, response handshake, interpolation-valid stage, held output. |
| das_channel_math.v | Signed 16-bit micrometre coordinates cannot represent +50 mm. Subtraction and squared sums could overflow. | 18-bit diagnostic coordinates, widened differences/squares/sum, valid/reset pipeline. |
| Position generation | Original pitch was 0.5 mm and origin 0..12 mm, unlike a centred aperture. | Measured configurable positions; example uses -12..12 mm at 1 mm. |
| fmc150_axi_capture.v | aclk was unused while stream outputs were clocked by div_clk: an unhandled clock-domain boundary. | Explicit sample-clock AXIS boundary; external vendor clock converter where needed. |
| fmc150_axi_capture.v | No TREADY, TLAST, echo-window trigger/count or finite capture; zero padding lost sign extension. | Whole-line buffering, sign extension, finite packet, stable AXIS handshake and status. |
| ultrasound_engine_top.v | TVALID/TLAST were dropped during stalls and source pixels were not backpressured. | Acquisition top and optional DAS core hold output until handshake. |
| Envelope/readiness | abs() was described as envelope; missing generated IP/constraints were described as active hardware. | Analytic envelope in software; missing physical integration clearly identified. |
| Repository hygiene | .gitignore.txt is not Git's ignore filename; no executable reference or verification suite. | .gitignore, standalone Python, RF packer, Python/HDL tests and synthesis scripts. |

## 5. Memory, RF bandwidth and arithmetic

At 250 MSPS, 14 raw bits require 3.5 Gbit/s (437.5 MB/s) for one continuously
sampled ADC input. The convenient 16-bit DMA representation needs 500 MB/s if
streamed continuously. Two seconds at one position would require 875 MB packed
or 1 GB padded. There is no need to continuously record through the mechanical
move; capture only the relevant echo window on each firing.

| Capture strategy | Samples across 25 positions | 16-bit storage |
| --- | --- | --- |
| 80 us at 250 MSPS | 500000 | 1000000 bytes (0.954 MiB) |
| Same window after anti-aliased /4 RF decimation | 125000 | 250000 bytes |
| 2 s at each of 25 positions, continuous | 12500000000 | 25 GB |

ZedBoard has 512 MB DDR [3]. XC7Z020 has 140 36-Kbit BRAM blocks [4]. The full
80 us, 25-position dataset has 7 million useful ADC bits before storage padding,
exceeding the chip's nominal BRAM bit capacity. Twenty-five full padded BRAM
banks are therefore the wrong initial storage plan. One reusable line buffer
plus DDR solves this without demanding sustained 500 MB/s DMA during capture.

The new capture controller stores one line at the ADC cadence and drains it
after acquisition. With no downstream stalls, its simple drain takes three
sample-clock cycles per word: approximately 240 us for 20000 words at 250 MHz.
This trades transfer latency for simple correct handshaking and is appropriate
when mechanical settling dominates. It is not a continuous streaming recorder.

For 25 signed 14-bit RF samples, the extreme integer sums are -204800 and +204775.
Nineteen signed bits cover -262144..+262143. The fractional interpolation core
keeps additional Q12 and guard bits through accumulation, then rounds once and
sign-extends the result to 32 bits. No magnitude operation precedes addition.

At 2.25 MHz, 250 MSPS is strong oversampling. Acquisition must satisfy the
received RF bandwidth, not just centre frequency. Optional resample_poly
decimation includes anti-alias filtering and updates Fs while retaining the time
origin. Simply selecting every fourth raw sample is not equivalent. Validate
passband, timing and image error before implementing a hardware decimator.

## 6. Physical image-quality limitations

Wavelength is about 0.684 mm at 2.25 MHz and c=1540 m/s. For this monostatic
point model, narrowband phase is 4*pi*R/lambda. Its spatial derivative has
magnitude 4*pi*sin(theta)/lambda, giving a local Nyquist spacing condition
pitch <= lambda/(4*sin(theta_max)). At 30 degrees this is about 0.342 mm;
at 60 degrees it is about 0.198 mm. Use the highest relevant RF frequency for
a broadband bound. This is a model-derived local sampling guide, not a blanket
guarantee for a finite piston or arbitrary geometry.

Consequently, 0.5 or 1 mm steps risk grating lobes when a wide angular aperture
is used. With 25 positions, decreasing pitch also decreases aperture and can
worsen lateral resolution. Preserve the 24 mm span with more positions if angular
coverage requires finer sampling, or restrict angular coverage based on measured
directivity and accept the corresponding resolution change. Apodisation and
coherence weighting reduce sidelobes/clutter but cannot recover unsampled space.

If the earlier 13 mm diameter, 2.25 MHz disk is still the intended element,
the approximate circular-piston near-field length D^2/(4*lambda) is about 62 mm
in the example medium [9]. Much of the proposed 10..50 mm image then lies in a
nonuniform field. The code's point-centre approximation must be checked with
wire targets and the actual focus/beam response. max_angle_deg is an optional
gate, not a full finite-aperture field correction. A focused element may require
a different virtual-source model. Sound-speed errors, refraction, motion,
out-of-plane scattering and transmit phase changes also defocus the image.

The demonstration deliberately uses 25 positions at 1 mm pitch and point sources.
Targets are (0,30 mm), (-4,22 mm) and (6,40 mm); the brightest target reconstructs
at (0,30 mm). The accompanying comparison shows the strong sparse-aperture
artifacts in plain DAS and their reduction with Hann plus coherence weighting.
Remaining bright lobes are not asserted to be real targets. No measured phantom,
speckle, finite-piston field or clinical image quality is claimed.

![Plain and weighted synthetic DAS](assets/das_comparison.png)

## 7. Hardware/software allocation

| Function | Initial location | Reason and later option |
| --- | --- | --- |
| FMC150 clocks/SPI/LVDS lane recovery | FPGA PHY plus vendor configuration software | Sample-rate operation and physical timing; requires actual BSP and constraints. |
| Trigger/record count/line capture | FPGA | Deterministic echo-window timing; full-line buffer absorbs DMA stalls. |
| Stage move/settle and scan identity | ARM/controller | Mechanical control and acquisition metadata. |
| DMA, cache-safe buffers, DDR storage | FPGA DMA plus ARM driver | Store 25 logical records without 25 full BRAM banks. |
| Calibrated delays and geometry | Python on PC initially | Easy to inspect; includes real positions, c and timing offsets. |
| Filtering, analytic signal, DAS, envelope/log/image | Python | Complete numerical reference before optimising hardware. |
| Optional RF gather/interpolate/sum | Reviewed sequential RTL core | Software-generated delays, DDR or deliberately reduced BRAM data; baseline signed DAS only. |

The optional core has no DDR AXI master or descriptor-DMA adapter. Those board
integration blocks are explicitly still required. It is a tested compute core,
not a replacement for the entire acquisition system. It processes positions
sequentially, not one complete pixel per clock. The 241x401 grid needs 2416025
contributions; even four 100 MHz cycles per valid contribution already cost
roughly 97 ms before additional memory latency and output stalls. Actual throughput must
be measured. Parallelism, caching, tiling and on-chip decimation can be considered
after calibrated images and the dominant bottleneck are established.

For analytic-envelope parity with the Python reference, hardware would need
both analytic I and Q contributions (or a validated equivalent signal pipeline).
The existing optional core returns the real RF sum only. Two appropriately
scaled I/Q passes are a possible extension; that preprocessing/packing is not
provided. Applying abs to real RF does not supply the missing quadrature signal.

## 8. Exact file inventory and interface changes

| File | Delivered role |
| --- | --- |
| beamform_das.py | Complete standalone DAS API and CLI; monostatic/bistatic geometry, calibration, interpolation, analytic envelope, coverage, optional taper/aperture/CF/filter/decimation, synthetic data and LUT export. |
| pack_rf.py | Raw binary DMA to calibrated NPZ, explicit ADC encoding, measured positions/timing and rail count. |
| fmc150_axi_capture.v | Rewritten post-PHY finite capture and stable 16-bit AXIS line packet. |
| ultrasound_engine_top.v | Rewritten acquisition-only wrapper; coordinate/abs beamformer chain removed. |
| das_beamformer_top.v | Rewritten software-delay, external-memory signed core with pixel/frame progress and protocol_error. |
| das_single_channel.v | Rewritten signed Q12 interpolation pipeline; missing CORDIC dependency removed. |
| das_memory_matrix.v | Rewritten small-record matrix with two synchronous reads, held responses and line-range error. |
| das_channel_math.v | Rewritten optional wide squared-distance diagnostic, reset and valid pipeline; not connected to active DAS. |
| tests and hardware/synth_ooc.tcl | Numerical and RTL regression suites, independent integer vectors, synthesis/resource checks and reproducible Vivado synthesis entry point. |
| README, hardware/integration.md, docs | Updated architecture, integration contracts, audit and validation evidence. |

All six Verilog port interfaces changed. Rebuild the block design around the
post-PHY acquisition boundary; do not reconnect old ports by position. No new
unverified physical deserializer or generated vendor IP has been invented.
Stage 1 uses only the acquisition wrapper and capture module. The other four
Verilog modules belong to optional acceleration/diagnostic work.

The LUT is pixel-major and includes addr0, addr1, fractional coefficient and
validity. A full 96641x25 table already occupies tens of MB in its exported
native array representation. Keep it in host/DDR memory or generate it by tiles;
it does not fit in Z7020 BRAM. Inspect hardware/integration.md for descriptor
TLAST convention, memory response protocol and cache/DMA requirements.

## 9. How to run and use the code

```bash
python -m pip install -r requirements.txt
python beamform_das.py simulate --output-dir results/demo
python beamform_das.py reconstruct results/demo/acquisition.npz --output-dir results/tapered --apodization hann --coherence-weight
python pack_rf.py frame.bin --positions 25 --samples 20000 --fs-mhz 250 --output acquisition.npz
python beamform_das.py reconstruct acquisition.npz --output-dir results/real
python beamform_das.py export-lut acquisition.npz --output-dir results/lut
```

For measured data, pack_rf accepts either one line-major frame file or 25 files
listed in acquisition order. Each word is little-endian, sign-extended int16
from the new RTL. Choose an explicit alternative encoding only for unconverted
raw ADC words. Override example pitch using measured CSV positions in metres;
override sound speed and time calibration. NPZ stores those fields with RF and Fs.

Reconstruction outputs signed_rf, analytic_das, envelope, relative bmode_db,
valid_count, weight_sum, coherence_factor and image axes in an NPZ, plus metadata
JSON and a PNG. Unsupported pixels are zero signal and the display floor.
Inspect coverage before interpreting image darkness. Defaults use rectangular,
unnormalised coherent sums matching the stated algorithm; Hann, normalisation,
dynamic aperture and coherence weighting are explicit options. No automatic gain
correction, calibrated acoustic power, attenuation compensation or contrast
metric is silently implied. Reuse preprocessing and options consistently when
comparing acquisitions. Use --help for complete controls.

## 10. Validation completed and limits

Eighteen Python tests passed, covering round-trip/bistatic timing, calibration
signs, the far-corner record bound, interpolation, endpoints, no address wrap,
signed cancellation/extremes, ADC formats, invalid input, CF/normalisation,
chunk equivalence, aperture gates, Q12 carry, NPZ round-trip, anti-aliased
decimation alignment and independent synthetic-target localisation.

Icarus Verilog 12.0 simulations passed for finite capture under random stalls,
signed extremes, one/max record length, missing-word/error handling, invalid
length, rearming, geometry width/valid timing, and 36 pixels of 25-position
Q12 DAS using independently calculated integer expectations. Memory request,
response and output were stalled; pixel/frame TLAST and malformed-descriptor
status were checked. The production 32768-sample acquisition top elaborated.

Yosys 0.33 mapped the recommended acquisition top and optional DAS core to
7-series resources and structural checks passed. Capture mapped to 14 RAMB36E1
blocks; the DAS core used 2 DSP48E1 and no RF storage. Mapping estimates exclude
PHY, clock converter, DMA, PS integration and physical routing. Primitive-port
resizing messages during capture BRAM mapping are not a Vivado DRC/timing result.
The Vivado synthesis script was supplied, but Vivado, post-route timing and
on-board acquisition were not run here.

Test environment: Python 3.12.14, NumPy 2.3.5, SciPy 1.17.0, Matplotlib 3.10.8.
One full 241x401 reference reconstruction of the demonstration took about
0.339 s in this execution environment, excluding loading, plotting and startup.
This is an indicative single run, not a hardware/ARM or real-time performance
claim. Reproduce tests with commands in README and see docs/validation.md.

## 11. Board and ADC decision

| Platform | ADC capability | Compatibility and recommendation |
| --- | --- | --- |
| Existing ZedBoard + FMC150 | Two 14-bit ADC inputs up to 250 MSPS [2,5] | Keep for the first prototype. ZedBoard offers LPC FMC and DDR [3]; FMC150 is LPC/LVDS [2]. Actual carrier/card revision, VADJ, clock pin route and vendor reference design must be verified. No board swap is required by the DAS mathematics. |
| Eclypse Z7 + Zmod Scope 1410-105 | Two 14-bit inputs up to 105 MSPS [6,7] | Documented supported pairing, with vendor acquisition examples; satisfies >60 MSPS. Good alternative if existing FMC150 BSP access is difficult. Use the exact 1410-105 variant when following the older software examples; support differs for other variants. |
| ZC706 + AD-FMCDAQ2-EBZ | Dual 14-bit AD9680 ADC up to 1 GSPS [8] | ADI documents ZC706 support. HPC/JESD204B acquisition and greater data rates add integration effort; unnecessary for the present low-MHz single-element proof of concept. This mezzanine is not a ZedBoard LPC substitute. |

The manufacturer's rated maximum ADC rate is not proof of a particular installed
clock configuration or of timing closure. The software uses the configured and
verified sample rate from the acquisition file. Avoid choosing a board simply
because an ADC chip supports 65/100/250 MSPS: electrical connector compatibility,
clocking, FPGA input bandwidth and a usable reference design matter as much.
No current purchasing availability or price is asserted.

## 12. Next physical milestones

First obtain a single clean trigger-aligned A-scan with ADC test pattern/sine-wave
verification. Then calibrate a known stationary wire at two depths, verify stage
coordinates and repeatability, and acquire all 25 records without clipping or
lost samples. Reconstruct with plain DAS and inspect coverage and target location
before enabling weighting. Compare scan pitches and the measured beam footprint.
Only then evaluate FPGA acceleration, measured image contrast/resolution and
moving-target limitations. Finalise the pin/clock constraints and run Vivado DRC,
CDC and post-route timing before describing the acquisition as board-ready.

## Sources

Primary sources checked 6 October 2026. Geometry, numeric budgets, audit findings
and validation results are derived in this work; product facts below come from
the respective manufacturers or authors.

1. Jensen et al., Synthetic Aperture Ultrasound Imaging, Ultrasonics 44 (2006), e5-e15: https://orbit.dtu.dk/en/publications/synthetic-aperture-ultrasound-imaging/
2. Abaco FMC150 specifications/BSP: https://www.abaco.com/Products-and-Services/Digital-Signal-Processing/FPGA-Mezzanine-Cards/FMC150
3. Digilent/Avnet ZedBoard Hardware User Guide v2.2: https://files.digilent.com/resources/programmable-logic/zedboard/ZedBoard_HW_UG_v2_2.pdf
4. AMD Zynq-7000 Overview DS190: https://docs.amd.com/v/u/en-US/ds190-Zynq-7000-Overview
5. TI ADS62P49 datasheet: https://www.ti.com/lit/ds/symlink/ads62p49.pdf
6. Digilent Eclypse Z7: https://digilent.com/shop/eclypse-z7/
7. Digilent Zmod Scope 1410, including variant rates/support: https://digilent.com/shop/zmod-scope-1410-2-channel-14-bit-oscilloscope-module/
8. ADI AD-FMCDAQ2 hardware and ZC706 Linux support: https://www.analog.com/en/resources/evaluation-hardware-and-software/evaluation-boards-kits/eval-ad-fmcdaq2-ebz.html and https://wiki.analog.com/resources/eval/user-guides/ad-fmcdaq2-ebz/software/linux
9. Evident circular-transducer beam/near-field formula: https://ims.evidentscientific.com/en/learn/ndt-tutorials/flaw-detection/beam-characteristics
10. AMD AXI DMA PG021 user parameters: https://docs.amd.com/r/en-US/pg021_axi_dma/User-Parameters
