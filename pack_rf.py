#!/usr/bin/env python3
"""Package line-major 16-bit DMA files into the calibrated DAS NPZ contract.

Supply one binary per mechanical position in the correct order. A single binary
is also accepted with --positions N, if it contains N equal contiguous lines.
FMC150 capture in this repository produces SIGN-EXTENDED LITTLE-ENDIAN int16.
Do not select twos-complement/offset-binary again for that output.
"""
import argparse
from pathlib import Path
import numpy as np
from beamform_das import Acquisition, centred_positions, decode_adc, save_acquisition


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("files",type=Path,nargs="+")
    p.add_argument("--output",type=Path,default=Path("acquisition.npz"))
    p.add_argument("--positions",type=int,default=25)
    p.add_argument("--samples",type=int,required=True)
    p.add_argument("--fs-mhz",type=float,default=250.)
    p.add_argument("--pitch-mm",type=float,default=1.)
    p.add_argument("--positions-csv",type=Path,help="Headerless measured x,z in metres, one row per line")
    p.add_argument("--t0-us",type=float,default=0.)
    p.add_argument("--system-delay-us",type=float,default=0.)
    p.add_argument("--calibration-csv",type=Path,help="Headerless t0_s,system_delay_s per line")
    p.add_argument("--c-m-s",type=float,default=1540.)
    p.add_argument("--encoding",choices=["signed","twos-complement","offset-binary"],default="signed")
    p.add_argument("--adc-bits",type=int,default=14)
    a = p.parse_args()
    if a.positions<1 or a.samples<2:
        p.error("positions>=1 and samples>=2 required")
    dtype = "<i2" if a.encoding=="signed" else "<u2"
    lines=[]
    for f in a.files:
        if f.stat().st_size % 2:
            raise ValueError(f"{f} has an incomplete 16-bit word")
        lines.append(np.fromfile(f,dtype=dtype))
    if len(lines)==1:
        if lines[0].size != a.positions*a.samples:
            raise ValueError("Binary must contain exactly positions*samples 16-bit words")
        rf = lines[0].reshape(a.positions,a.samples)
    elif len(lines)==a.positions and all(len(row)==a.samples for row in lines):
        rf = np.stack(lines)
    else:
        raise ValueError("Supply one contiguous frame or one equal-sized file per position")
    rf = decode_adc(rf,a.adc_bits,a.encoding)
    pos = (centred_positions(a.positions,a.pitch_mm*1e-3) if a.positions_csv is None
           else np.loadtxt(a.positions_csv,delimiter=",",ndmin=2))
    t0,delay = a.t0_us*1e-6,a.system_delay_us*1e-6
    if a.calibration_csv is not None:
        cal = np.loadtxt(a.calibration_csv,delimiter=",",ndmin=2)
        if cal.shape!=(a.positions,2):
            raise ValueError("calibration CSV requires one t0_s,system_delay_s row per position")
        t0,delay=cal[:,0],cal[:,1]
    acq = Acquisition(a.fs_mhz*1e6,pos,a.c_m_s,t0,delay)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    save_acquisition(a.output,rf,acq)
    rails = (rf==-(1<<(a.adc_bits-1))) | (rf==(1<<(a.adc_bits-1))-1)
    print(f"Saved {a.output}: {rf.shape}; {np.count_nonzero(rails)} samples at ADC rails")


if __name__=="__main__":
    main()
