#!/usr/bin/env bash
set -euo pipefail
mkdir -p build/hdl
yosys -q -l build/hdl/capture_synthesis.log -p \
  'read_verilog fmc150_axi_capture.v ultrasound_engine_top.v; synth_xilinx -family xc7 -top ultrasound_engine_top -noclkbuf -noiopad; check; stat'
yosys -q -l build/hdl/das_synthesis.log -p \
  'read_verilog das_single_channel.v das_beamformer_top.v; synth_xilinx -family xc7 -top das_beamformer_top -noclkbuf -noiopad; check; stat'
# These are structural/resource checks. They do not measure routed timing,
# build a board bitstream, or verify FMC150 electrical I/O and ADC lane training.
