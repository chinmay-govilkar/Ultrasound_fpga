#!/usr/bin/env python3
"""Icarus integration tests, with independently computed integer expectations.

Run from repository root. IVERILOG, VVP and IVERILOG_FLAGS may select tool paths.
No vendor PHY is mocked or claimed verified: tests start at signed sample words.
"""
from pathlib import Path
import os
import shlex
import shutil
import subprocess
import numpy as np


def main():
    root=Path(__file__).resolve().parents[1]
    os.chdir(root)
    build=root/"build/hdl"; build.mkdir(parents=True,exist_ok=True)
    rng=np.random.default_rng(234)
    samples=rng.integers(-32768,32768,size=(25,16),dtype=np.int64)
    samples[:,0]=-32768; samples[:,1]=32767
    addr0=rng.integers(0,16,size=(36,25)); addr1=np.minimum(addr0+1,15)
    fractions=rng.integers(0,4096,size=(36,25)); valid=rng.random((36,25))>.15
    addr0[0]=0; addr1[0]=0; fractions[0]=0; valid[0]=True
    addr0[1]=1; addr1[1]=1; fractions[1]=0; valid[1]=True
    valid[2]=False
    # Endpoint, half-tie and coefficients near unity are deliberate cases.
    addr0[3]=15; addr1[3]=15; valid[3]=True
    fractions[4]=2048; fractions[5]=4095; fractions[6]=1
    rows=np.arange(25)[None,:]
    scaled=(samples[rows,addr0]*(4096-fractions)+samples[rows,addr1]*fractions)*valid
    expected=(scaled.sum(axis=1)+2048)//4096
    vectors={"samples":(samples,16),"addr0":(addr0,4),"addr1":(addr1,4),
             "fractions":(fractions,12),"valid":(valid,1),"expected":(expected,32)}
    for name,(a,bits) in vectors.items():
        (build/f"{name}.hex").write_text("".join(f"{int(v)&((1<<bits)-1):x}\n" for v in a.ravel()))
    iv=os.environ.get("IVERILOG",shutil.which("iverilog") or "iverilog")
    vvp=os.environ.get("VVP",shutil.which("vvp") or "vvp")
    flags=shlex.split(os.environ.get("IVERILOG_FLAGS",""))
    suites=[("capture",["adc_line_capture.v","tests/tb_capture.v"]),
            ("zmod",["adc_line_capture.v","zmod_scope_adapter.v","ultrasound_engine_top.v","tests/tb_zmod.v"]),
            ("math",["das_channel_math.v","tests/tb_math.v"]),
            ("das",["das_single_channel.v","das_beamformer_top.v","das_memory_matrix.v","tests/tb_das.v"])]
    for name,files in suites:
        output=build/f"{name}.vvp"
        subprocess.run([iv,*flags,"-g2012","-Wall","-s",f"tb_{name}","-o",str(output),*files],check=True)
        subprocess.run([vvp,str(output)],check=True,timeout=30)
    # Elaborate the actual recommended top with its production default buffer.
    subprocess.run([iv,*flags,"-g2012","-Wall","-s","ultrasound_engine_top","-o",str(build/"top.vvp"),
                    "ultrasound_engine_top.v","adc_line_capture.v","zmod_scope_adapter.v"],check=True)
    print("PASS recommended acquisition top elaboration (16384 calibrated samples)")


if __name__=="__main__": main()
