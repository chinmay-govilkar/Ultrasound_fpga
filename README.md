# Mechanically scanned ultrasound: calibrated DAS reference

One transducer transmits and receives at each of 25 mechanical positions. RF is
stored as 25 **logical acquisition rows**, then reconstructed pixel by pixel.
This is monostatic synthetic-aperture focusing (SAFT). Mechanical scanning limits
frame rate; this acquisition is not simultaneous ultrafast plane-wave imaging.

The corrected delay is `s_k = Fs * (2*distance_k/c + system_delay_k - t0_k)`.
Interpolate signed RF coherently; take the analytic sum's magnitude afterwards.
Use measured positions, sound speed, trigger origin and receiver latency.

## Run the complete Python demonstration

```bash
python -m pip install -r requirements.txt
python beamform_das.py simulate --output-dir results/demo
python beamform_das.py reconstruct results/demo/acquisition.npz --output-dir results/tapered --apodization hann --coherence-weight
```

Defaults: 250 MSPS, 25 positions at 1 mm pitch centred about zero, x=-12..12 mm,
z=10..50 mm, 241x401 pixels, 80 us synthetic record. The original RTL used 0.5 mm
pitch starting at x=0; neither nominal layout replaces measured stage positions.
The 1 mm pitch demonstration intentionally exposes spatial aliasing. Windowing
and coherence weighting help clutter but cannot restore missing spatial data.

## Reconstruct ADC data

Capture one echo window at each position. DMA writes sign-extended little-endian
int16 samples to DDR. Concatenate the 25 equal records in physical scan order:

```bash
python pack_rf.py frame.bin --positions 25 --samples 20000 --fs-mhz 250 --pitch-mm 1 --output acquisition.npz
python beamform_das.py reconstruct acquisition.npz --output-dir results/real
```

`pack_rf.py` also accepts 25 separate files, measured x,z CSV positions (metres),
per-line timing CSV (seconds), and explicit raw ADC encodings. See `--help`.
Do not choose raw-word decoding for data already sign-extended by the new capture
module. NPZ keys: `rf`, `fs_hz`, `rx_positions_m`, optionally `tx_positions_m`,
`c_m_s`, `t0_s`, `system_delay_s`. Shape of RF: `(positions,time_samples)`.

## Hardware status and scope

Recommended Stage 1: FMC150 vendor PHY/configuration -> triggered whole-line
capture BRAM -> AXIS clock converter -> DMA -> DDR -> Python reconstruction.

- `ultrasound_engine_top.v`: acquisition top, post-PHY signed samples.
- `fmc150_axi_capture.v`: finite line capture, error flag, correct AXIS stalls/TLAST.
- `das_beamformer_top.v`: optional sequential signed gather/interpolate/sum core;
  software supplies delays, external memory supplies adjacent RF samples.
- `das_single_channel.v`: signed Q12 interpolation pipeline.
- `das_memory_matrix.v`: optional small-record integration memory; full dataset uses DDR.
- `das_channel_math.v`: optional wide-coordinate squared-distance diagnostic.

All six module interfaces were changed intentionally; they are not drop-in
replacements for the old block design. No missing `cordic_0` or `selectio_wiz_0`
black boxes are asserted to be present. FMC150 BSP, SPI/clock setup, actual pin
constraints, PS control CDC/DMA driver, and board timing closure remain required.
This repository does **not** contain a verified 250 MSPS board bitstream.

## Validation and optional acceleration

```bash
python -m unittest discover -s tests -p 'test_*.py' -v
python tests/run_hdl_tests.py
bash tests/run_synthesis.sh
vivado -mode batch -source hardware/synth_ooc.tcl
python beamform_das.py export-lut acquisition.npz --output-dir results/lut
```

HDL tests require Icarus Verilog; synthesis checks require Yosys (or run the Vivado
script). The exported LUT targets rectangular, unnormalised signed RF DAS. The
optional core is not an analytic-envelope or coherence-weight accelerator.

See [the complete review](docs/review_and_implementation.md),
[hardware integration](hardware/integration.md) and
[validation evidence](docs/validation.md).
