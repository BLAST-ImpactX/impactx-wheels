#!/usr/bin/env python3
#
# Copyright 2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
"""Functional smoke test: run an ImpactX FODO example and analyze its openPMD
beam-monitor diagnostics -- in ONE process.

Importing impactx AND openpmd_api together verifies that the two PyPI wheels
(each shipping compiled C++) load and run in the same process. Reading the beam
monitor with openpmd_api .to_df() then crosses the C++ <-> Python (numpy/pandas)
boundary -- the path that segfaults when a wheel vendors a private MSVC C++
runtime on Windows (see check_no_vendored_runtime.py).

Usage:  python smoke_example.py
"""
import os
import sys
import tempfile

import numpy as np
import openpmd_api as io  # co-load the openPMD-api wheel alongside impactx
from scipy.stats import moment

from impactx import ImpactX, distribution, elements


def run_fodo():
    """Track a 2 GeV electron Waterbag beam through a FODO cell with monitors."""
    sim = ImpactX()
    sim.space_charge = False
    sim.slice_step_diagnostics = True
    sim.init_grids()

    sim.beam.ref.set_species("electron").set_kin_energy_MeV(2.0e3)
    distr = distribution.Waterbag(
        lambdaX=3.9984884770e-5,
        lambdaY=3.9984884770e-5,
        lambdaT=1.0e-3,
        lambdaPx=2.6623538760e-5,
        lambdaPy=2.6623538760e-5,
        lambdaPt=2.0e-3,
        muxpx=-0.846574929020762,
        muypy=0.846574929020762,
        mutpt=0.0,
    )
    npart = 10000
    sim.add_particles(1.0e-9, distr, npart)

    monitor = elements.BeamMonitor("monitor", backend="h5")
    ns = 25
    sim.lattice.extend(
        [
            monitor,
            elements.Drift(name="drift1", ds=0.25, nslice=ns),
            monitor,
            elements.Quad(name="quad1", ds=1.0, k=1.0, nslice=ns),
            monitor,
            elements.Drift(name="drift2", ds=0.5, nslice=ns),
            monitor,
            elements.Quad(name="quad2", ds=1.0, k=-1.0, nslice=ns),
            monitor,
            elements.Drift(name="drift3", ds=0.25, nslice=ns),
            monitor,
        ]
    )
    sim.track_particles()
    sim.finalize()
    return npart


def analyze(npart):
    """Read the beam-monitor openPMD output back via openpmd_api + pandas."""
    series = io.Series("diags/openPMD/monitor.h5", io.Access.read_only)
    steps = list(series.iterations)
    initial = series.iterations[steps[0]].particles["beam"].to_df()
    final = series.iterations[steps[-1]].particles["beam"].to_df()

    assert len(initial) == npart, len(initial)
    assert len(final) == npart, len(final)
    sigx = moment(final["position_x"], moment=2) ** 0.5
    assert np.isfinite(sigx) and sigx > 0.0, sigx
    print("ImpactX+openPMD smoke OK: npart=%d steps=%d sigx=%e"
          % (npart, len(steps), sigx))


def main():
    print("co-loaded impactx with openpmd_api", io.__version__)
    os.chdir(tempfile.mkdtemp(prefix="impactx-smoke-"))  # diags/ go here
    analyze(run_fodo())
    return 0


if __name__ == "__main__":
    sys.exit(main())
