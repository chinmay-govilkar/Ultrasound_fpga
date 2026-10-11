#!/usr/bin/env python3
"""Reproduce the report figure after running plain and weighted CLI examples."""
from pathlib import Path
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt


def main():
    root=Path(__file__).resolve().parents[1]
    fig,axes=plt.subplots(1,2,figsize=(9,7.5),layout="constrained",sharey=True)
    for ax,(name,title) in zip(axes,[("demo","Rectangular DAS"),("demo_tapered","Hann + coherence weighting")]):
        with np.load(root/"results"/name/"reconstruction.npz") as d:
            image=ax.pcolormesh(d["x_m"]*1000,d["z_m"]*1000,d["bmode_db"],
                                vmin=-60,vmax=0,cmap="gray",shading="nearest")
        ax.scatter([0,-4,6],[30,22,40],marker="+",s=40,c="#db4380",linewidths=1.3,label="Simulated targets")
        ax.set_title(title,fontsize=11); ax.set_xlabel("Lateral position (mm)")
        ax.set_aspect("equal"); ax.set_ylim(50,10)
    axes[0].set_ylabel("Depth (mm)")
    axes[1].legend(loc="lower right",fontsize=8)
    fig.colorbar(image,ax=axes,label="Amplitude relative to each image peak (dB)",shrink=.85)
    with np.load(root/"results/demo/acquisition.npz") as acquisition:
        fs_mhz=float(acquisition["fs_hz"])/1e6
    fig.suptitle(f"25 positions at 1 mm pitch | 2.25 MHz simulation | {fs_mhz:g} MSPS",fontsize=12)
    path=root/"docs/assets/das_comparison.png"; path.parent.mkdir(parents=True,exist_ok=True)
    fig.savefig(path,dpi=170); plt.close(fig)
    print(path)


if __name__=="__main__": main()
