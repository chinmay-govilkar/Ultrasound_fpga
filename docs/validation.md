# Validation evidence on 11 October 2026

Selected target: Eclypse Z7 + Zmod Scope 1410-105, 100 MSPS configured profile.
Original audited main: `60ca7e9d2e5efb4c3410f4c75788b38b5ea6b251`.
Migration parent: `01683703dcfa6a246d1433a0b3a4e0e5ecb868c0`.
Results concern numerical and current-controller-boundary logic, not a board bitstream.

## Python and complete CLI paths

Python 3.12.14; NumPy 2.3.5; SciPy 1.17.0; Matplotlib 3.10.8.

`python -m unittest discover -s tests -p 'test_*.py' -v`: **23 tests passed**.
The original 18 DAS regressions remain; five new Eclypse tests cover packed CH1/CH2
selection, calibrated int16 limits, exact-length single/multi-file imports,
100/105 MSPS record bounds, complete packer CLI, metadata and invalid-rate rejection.
The full-scale 25-position sums are -819200 and +819175. Signed cancellation,
fractional timing, no wrapping, calibration, aperture gates, coherence weighting,
anti-aliased decimation and independent target localization remain covered.
Earlier 250 MSPS signed acquisitions retain their stored rate and remain readable;
the platform-specific importer rejects new Zmod rate declarations above 105 MSPS.

At 100 MSPS the default 80 us RF shape is 25x8000. The 10..50 mm depth,
-12..12 mm lateral grid requires 7204 samples before pulse/latency margin.
At 105 MSPS the corresponding figures are 25x8400 and 7564 minimum samples.
Both records fit the 16384-sample buffer. The centre trace index for (0,30 mm)
is 3896.103896 at 100 MSPS, rather than 9740.259740 at the old 250 MSPS setting.

Complete simulate, rectangular reconstruction, Hann/CF reconstruction and Q12
LUT export passed at 100 MSPS. The brightest target was at row 200, column 120,
(0,30 mm), with no unsupported grid pixels. The report figure was regenerated. One full numerical reconstruction took
about 0.293 s here, excluding loading, plotting and startup; this is not a
hardware or ARM throughput claim.
The packer CLI was tested with calibrated int16 values outside the raw 14-bit
range so accidental 14-bit truncation or reinterpretation would fail.

## RTL simulation and elaboration

Icarus Verilog 12.0: `python tests/run_hdl_tests.py`.

| Suite | Result |
| --- | --- |
| Generic capture | PASS: int16 limits, 1/max length, random AXIS stalls, stable TDATA/TLAST/TUSER, zero slot and error for missing valid word, invalid lengths and rearm |
| Eclypse current-controller top | PASS: CH1 upper/CH2 lower, int16 extremes, channel latched at arm, always-high source TREADY during all states and output stalls, initialization/error gating, missing words, source overflow error and reacquisition |
| Geometry | PASS: signed coordinate extremes, 50 mm in micrometres, widened squares and valid pipeline |
| DAS and synchronous matrix | PASS: 36 pixels x25, independently computed int16/Q12 expectations, signed rails, fractional endpoints, invalid contributors, memory request/response/output stalls, frame TLAST and malformed descriptor |
| Production acquisition top | PASS elaboration with default 16384x16 line buffer |

The vendor physical IDDR/FIFO/SPI/relay/calibration IP is outside these simulation
suites. Tests start at its documented calibrated output interface. Clock-domain
crossing, actual pin timing and calibration coefficients are not emulated as
verified board behavior.

## Resource synthesis

Yosys 0.33: `bash tests/run_synthesis.sh`, family xc7, both structural checks passed.

| Design | Selected mapped resources | Structural check |
| --- | --- | --- |
| Current Zmod acquisition top with 16384x16 line buffer | 8 RAMB36E1, 74 FDRE, 13 CARRY4 | 0 problems |
| Optional int16 DAS compute core | 2 DSP48E1, 154 FDRE, 29 CARRY4; no RF BRAM | 0 problems |

The reusable buffer mapped to eight RAMB36 blocks, reduced from the prior
32768x14 capture's fourteen. These estimates exclude the vendor controller,
PS, DMA, clock conversion, configuration, control CDC and physical routing.
Capture BRAM mapping produced 40 primitive-port resizing warnings; these are
not Vivado DRC or timing results. A truncated local ABC executable caused an
initial tool failure; mapping passed with a fresh complete tool extraction.

`hardware/synth_ooc.tcl` selects xc7z020clg484-1 and a 10 ns default clock.
The controller configuration helper uses parameters checked against Digilent
vivado-library commit `f4613fff005b098065fd5d619a2b88e55720a423`; it was not executed
in Vivado here. The checked Eclypse low-level filter reference configured 40 MSPS,
so the migration explicitly requires reconfiguring its clocks and variant.
Vivado OOC, board DRC/CDC/post-route timing and physical acquisition were not run.

## Required physical validation

Integrate the current controller, actual SYZYGY-port XDC, calibration/relay control,
PS command/status CDC and S2MM DMA. Verify test patterns and the configured sample
rate, protected receiver gain/coupling and clipping, shared trigger origin and
stationary-reflector timing. Acquire and identify all 25 mechanical records,
check repeatability, validate the point-centre model and spatial sampling,
and run board DRC, CDC and post-route timing before claiming a working bitstream.
