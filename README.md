# Ultrasound DAS on Eclypse Z7 and Zmod Scope 1410-105

One transducer transmits and receives at each of 25 mechanical positions. RF is
stored as 25 **logical acquisition rows**, then reconstructed pixel by pixel.
This is monostatic synthetic-aperture focusing (SAFT). Mechanical scanning limits
frame rate; the scene must remain stationary through the scan.

The corrected delay is `s_k = Fs * (2*distance_k/c + system_delay_k - t0_k)`.
Interpolate signed RF coherently, then take the analytic sum's magnitude.
Use measured positions, sound speed, trigger origin and receiver latency.

## Selected platform

Eclypse Z7 has an XC7Z020-1CLG484C and 1 GiB DDR3L. Use Zmod Scope **1410-105**
on a SYZYGY port and Digilent's current **ZmodScopeController**. The physical
AD9648 ADC has two 14-bit inputs and a 105 MSPS rated ceiling. This project's
configured default is **100 MSPS**, which meets the >60 MSPS requirement and
leaves clock margin. Declare the actual configured and verified Fs in each file;
105 MSPS is not automatically the board's sample clock.

The current controller calibrates samples to **signed 16-bit** words, packing
CH1 in `[31:16]` and CH2 in `[15:0]`. Keep this precision. The legacy
`ZmodADC1410_Controller` and its old software-library DMA format are different.

## Run the Python demonstration

```bash
python -m pip install -r requirements.txt
python beamform_das.py simulate --output-dir results/demo
python beamform_das.py reconstruct results/demo/acquisition.npz --output-dir results/demo_tapered --apodization hann --coherence-weight
```

Defaults: 100 MSPS, 25 positions at 1 mm pitch centred about zero, x=-12..12 mm,
z=10..50 mm, 241x401 pixels, 80 us record = **8000 samples per position**.
The full selected-channel frame is **400000 bytes**. An explicitly configured
105 MSPS, 80 us acquisition uses 8400 samples and 420000 bytes.
The example 1 mm pitch exposes spatial aliasing; use measured stage coordinates.
Windowing and coherence weighting reduce clutter but cannot restore missing data.

## Reconstruct acquired RF

The new FPGA top selects a physical receiver channel, captures its whole echo
window, then outputs little-endian signed int16 samples for DMA. Concatenate the
25 records in scan order. For the default CH1, low gain, AC coupling configuration:

```bash
python pack_rf.py frame.bin --samples 8000 --fs-mhz 100 --receiver-channel 1 --gain low --coupling ac --output acquisition.npz
python beamform_das.py reconstruct acquisition.npz --output-dir results/real
```

If you instead record the current controller's two-channel 32-bit stream:

```bash
python pack_rf.py scope_frame.bin --format scope32 --receiver-channel 1 --samples 8000 --fs-mhz 100 --output acquisition.npz
```

Gain, coupling and channel flags document the actual capture; they do not change
hardware. `--format raw16 --encoding twos-complement --adc-bits 14` is reserved
for explicitly right-aligned uncalibrated ADC words. Never apply 14-bit decoding
to calibrated controller output. The importer rejects rates above 105 MSPS and
records above this profile's 16384-sample capacity.

The packer also accepts 25 files, measured x,z CSV positions in metres and
per-line timing CSV in seconds. NPZ stores RF, Fs, geometry, calibration and source
metadata. Reconstruction uses the file's Fs; older 250 MSPS data are not relabelled.

## Hardware path and status

Digilent ZmodScopeController -> physical-channel adapter -> finite line BRAM ->
AXIS clock/width conversion -> S2MM DMA -> PS DDR -> Python reconstruction.

- `zmod_scope_adapter.v`: CH1/CH2 selection latched with arm; controller TREADY stays high.
- `adc_line_capture.v`: 16384 x16 line buffer, missing-word/error handling and stable AXIS packet.
- `ultrasound_engine_top.v`: Eclypse controller boundary and acquisition status gating.
- `das_beamformer_top.v`: optional sequential signed 16-bit RF gather/interpolate/sum.
- `das_single_channel.v`: signed Q12 interpolation with guard bits.
- `das_memory_matrix.v`: optional small-record memory; initial dataset stored in DDR.
- `das_channel_math.v`: optional wide squared-distance diagnostic.

`fmc150_axi_capture.v` has been replaced by the board-independent capture module.
The top's ports changed to the current Zmod controller interface. Follow
[hardware/integration.md](hardware/integration.md) for the exact clock, status,
calibration, channel, DMA and trigger wiring. The vendor PHY/SPI/relay/calibration
IP and actual board XDC must be integrated into an Eclypse Vivado project.
No routed bitstream or physical board acquisition was verified here.

## Validation and optional acceleration

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
python tests/run_hdl_tests.py
bash tests/run_synthesis.sh
vivado -mode batch -source hardware/synth_ooc.tcl
python beamform_das.py export-lut acquisition.npz --output-dir results/lut
```

HDL tests need Icarus; synthesis checks need Yosys or Vivado. The OOC script
uses the Eclypse FPGA part and a 10 ns default sample period. The optional DAS
core implements rectangular unnormalised real RF sums; the analytic envelope,
coherence weighting and image formation remain in Python.

See [the complete updated review](docs/review_and_implementation.md),
[the platform migration](docs/eclypse_migration.md) and
[validation evidence](docs/validation.md).
