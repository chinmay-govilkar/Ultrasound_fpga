#!/usr/bin/env python3
"""Package Eclypse echo windows into the calibrated DAS NPZ contract.

signed16: this repository's capture output, one selected calibrated channel.
scope32: Digilent ZmodScopeController output, CH1 [31:16], CH2 [15:0].
raw16: explicitly decoded right-aligned 14-bit ADC words, not calibrated data.
One file contains line-major equal records, or supply one file per position.
Legacy ZmodADC1410_Controller DMA words have a different packing and are not
accepted as scope32. Fs must match the clock actually configured and measured.
"""
import argparse
from pathlib import Path
import numpy as np
from beamform_das import Acquisition, centred_positions, decode_adc, save_acquisition
from eclypse_z7 import (DEFAULT_FS_HZ, PLATFORM, MAX_SAMPLES, CONTROLLER_BITS,
                       ADC_BITS, decode_scope_words, validate_sample_rate)


def read_records(files, positions, samples, sample_format, receiver_channel=1,
                 encoding="twos-complement", adc_bits=ADC_BITS):
    """Read exact-length records; reject padding/truncation rather than guessing."""
    if positions < 1 or samples < 2:
        raise ValueError("positions>=1 and samples>=2 required")
    dtypes = {"signed16":"<i2", "scope32":"<u4", "raw16":"<u2"}
    if sample_format not in dtypes:
        raise ValueError("Unknown sample format")
    dtype = np.dtype(dtypes[sample_format])
    lines = []
    for file in files:
        file = Path(file)
        if file.stat().st_size % dtype.itemsize:
            raise ValueError(f"{file} has an incomplete {dtype.itemsize*8}-bit word")
        lines.append(np.fromfile(file,dtype=dtype))
    if len(lines)==1 and lines[0].size==positions*samples:
        words = lines[0].reshape(positions,samples)
    elif len(lines)==positions and all(row.size==samples for row in lines):
        words = np.stack(lines)
    else:
        raise ValueError("Supply exactly positions*samples words or one equal record per position")
    if sample_format=="scope32":
        return decode_scope_words(words,receiver_channel)
    if sample_format=="signed16":
        return decode_adc(words,CONTROLLER_BITS,"signed")
    return decode_adc(words,adc_bits,encoding)


def main():
    p = argparse.ArgumentParser(description=__doc__,formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("files",type=Path,nargs="+")
    p.add_argument("--output",type=Path,default=Path("acquisition.npz"))
    p.add_argument("--positions",type=int,default=25)
    p.add_argument("--samples",type=int,required=True)
    p.add_argument("--fs-mhz",type=float,default=DEFAULT_FS_HZ/1e6)
    p.add_argument("--format",choices=["signed16","scope32","raw16"],default="signed16")
    p.add_argument("--receiver-channel",type=int,choices=[1,2],default=1,
                   help="Physical Zmod channel; for signed16 this records the FPGA selection")
    p.add_argument("--gain",choices=["high","low"],default="low",
                   help="Metadata only: high is nominal +/-1 V, low +/-25 V")
    p.add_argument("--coupling",choices=["ac","dc"],default="ac",help="Metadata only")
    p.add_argument("--pitch-mm",type=float,default=1.)
    p.add_argument("--positions-csv",type=Path,help="Headerless measured x,z in metres, one row per line")
    p.add_argument("--t0-us",type=float,default=0.)
    p.add_argument("--system-delay-us",type=float,default=0.)
    p.add_argument("--calibration-csv",type=Path,help="Headerless t0_s,system_delay_s per line")
    p.add_argument("--c-m-s",type=float,default=1540.)
    p.add_argument("--encoding",choices=["twos-complement","offset-binary"],default=None,
                   help="Only for --format raw16")
    p.add_argument("--adc-bits",type=int,default=None,help="Only for raw16; default 14")
    a = p.parse_args()
    if a.positions<1 or not 2<=a.samples<=MAX_SAMPLES:
        p.error(f"positions>=1 and 2<=samples<={MAX_SAMPLES} required for this capture profile")
    if a.format!="raw16" and (a.encoding is not None or a.adc_bits is not None):
        p.error("--encoding and --adc-bits apply only to raw16, not calibrated samples")
    try:
        fs = validate_sample_rate(a.fs_mhz*1e6)
        rf = read_records(a.files,a.positions,a.samples,a.format,a.receiver_channel,
                          a.encoding or "twos-complement",a.adc_bits if a.adc_bits is not None else ADC_BITS)
        pos = (centred_positions(a.positions,a.pitch_mm*1e-3) if a.positions_csv is None
               else np.loadtxt(a.positions_csv,delimiter=",",ndmin=2))
        if pos.shape!=(a.positions,2):
            raise ValueError("positions CSV requires one x_m,z_m row per position")
        t0,delay = a.t0_us*1e-6,a.system_delay_us*1e-6
        if a.calibration_csv is not None:
            cal = np.loadtxt(a.calibration_csv,delimiter=",",ndmin=2)
            if cal.shape!=(a.positions,2):
                raise ValueError("calibration CSV requires one t0_s,system_delay_s row per position")
            t0,delay=cal[:,0],cal[:,1]
        acq = Acquisition(fs,pos,a.c_m_s,t0,delay)
    except (ValueError,OSError) as error:
        p.error(str(error))
    bits = (a.adc_bits if a.adc_bits is not None else ADC_BITS) if a.format=="raw16" else CONTROLLER_BITS
    metadata = {"platform":PLATFORM,"sample_format":a.format,"sample_bits":bits,
                "adc_resolution_bits":ADC_BITS,"receiver_channel":a.receiver_channel,
                "gain":a.gain,"coupling":a.coupling,"calibrated":a.format!="raw16"}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    save_acquisition(a.output,rf,acq,metadata=metadata)
    rails = (rf==-(1<<(bits-1))) | (rf==(1<<(bits-1))-1)
    print(f"Saved {a.output}: {rf.shape}, {fs/1e6:g} MSPS; "
          f"{np.count_nonzero(rails)} samples at stored-format rails")


if __name__=="__main__":
    main()
