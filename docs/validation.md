# Validation evidence, 6 October 2026

Audited upstream: `60ca7e9d2e5efb4c3410f4c75788b38b5ea6b251`.
The following results concern the revised numerical/post-PHY logic, not a board bitstream.

## Python

Python 3.12.14; NumPy 2.3.5; SciPy 1.17.0; Matplotlib 3.10.8.

`python -m unittest discover -s tests -p 'test_*.py' -v`

18 tests passed. Independent synthetic target localised within one 0.1 mm image
grid cell. Signed extremes produced -204800 and +204775 with 25 channels.
RF and its negative cancelled coherently. No wrapped or clipped-edge
contribution occurred outside the record. /4 anti-aliased decimation retained
the timing origin and 2.25 MHz test sinusoid.

Complete CLI paths exercised: simulate, reconstruct, Hann/CF reconstruction and
Q12 delay-table export. Example 401x241 image peak: row 200, column 120, (0,30 mm).
Single full numerical reconstruction: approximately 0.339 seconds here; excludes
load/plot/startup and is not an ARM, throughput or real-time claim.

## RTL simulations and elaboration

Icarus Verilog 12.0: `python tests/run_hdl_tests.py`.

| Suite | Result |
| --- | --- |
| Capture | PASS: sign extension, 1/maximum length, random AXIS stalls, stable TDATA/TLAST/TUSER, missing sample preserved at zero with error, invalid lengths, rearm |
| Geometry | PASS: widened signed differences, coordinate extremes, 50 mm in micrometres, three-stage valid pipeline |
| DAS + synchronous matrix | PASS: 36 pixels x25 positions, independently calculated Q12 arithmetic, signed limits, fractional edges, invalid masks, request/response/output stalls, frame TLAST, malformed descriptor status |
| Recommended acquisition top | PASS elaboration with default 32768-sample buffer |

The optional core has one outstanding memory request. Test expectations are
calculated independently with integer interpolation and summed before rounding.
The vendor LVDS PHY is not stubbed and represented as tested: it is outside the
signed-sample boundary used by these tests.

## Resource synthesis

Yosys 0.33: `bash tests/run_synthesis.sh`, target family `xc7`.

| Design | Selected mapped resources | Structural check |
| --- | --- | --- |
| ultrasound_engine_top / capture, 32768 x14 line buffer | 14 RAMB36E1, 74 FDRE, 14 CARRY4 | 0 problems |
| das_beamformer_top / interpolation | 2 DSP48E1, 150 FDRE, 29 CARRY4, no RF BRAM | 0 problems |

Capture BRAM mapping produced primitive-port resizing messages. These estimates
exclude PHY, DMA, PS, clock conversion and physical routing. Vivado may choose a
different RAM organisation. Synthesis is not post-route 250 MHz timing closure.
`hardware/synth_ooc.tcl` was delivered but was not executed because Vivado is
not available here. No measured analogue data or on-board test was supplied.

## Required physical validation

Complete vendor PHY/configuration and actual XDC; verify ADC patterns, clocks and
encoding; calibrate a stationary target; verify all 25 record identities and
mechanical positions; inspect signal clipping/coverage; validate phase-centre
model and grating lobes; run Vivado DRC, CDC and post-route timing. The review
document and hardware integration contract describe these concrete next steps.
