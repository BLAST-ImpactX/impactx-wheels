#!/usr/bin/env python3
#
# Copyright 2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
"""Functional smoke test: run an ImpactX FODO example and analyze its openPMD
beam-monitor diagnostics -- in ONE process.

Running impactx and importing openpmd_api together verifies that the two PyPI
wheels (each shipping compiled C++) load and run in the same process. Reading
the beam monitor with openpmd_api .to_df() then crosses the C++ <-> Python
(numpy/pandas) boundary -- the path that segfaults when a wheel vendors a
private MSVC C++ runtime on Windows (see check_no_vendored_runtime.py).

On macOS importing openpmd_api after impactx currently aborts (duplicate
bundled native libs under dyld); _macos_backtrace() captures a native lldb
backtrace before we hit it in-process, and faulthandler dumps the Python frame.

The read-back needs pandas/openpmd-api, which have no 32-bit wheels; on
platforms where they cannot be installed it is skipped (the example still runs).

Usage:  python smoke_example.py
"""
import faulthandler
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

from impactx import ImpactX, distribution, elements

faulthandler.enable()

_IMPORTS = ("openpmd_api", "pandas")
_PIP = ("openpmd-api", "pandas")


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
    import openpmd_api as io

    series = io.Series("diags/openPMD/monitor.h5", io.Access.read_only)
    steps = list(series.iterations)
    initial = series.iterations[steps[0]].particles["beam"].to_df()
    final = series.iterations[steps[-1]].particles["beam"].to_df()

    assert len(initial) == npart, len(initial)
    assert len(final) == npart, len(final)
    sigx = final["position_x"].std()  # pandas/numpy; no fragile scipy API
    assert np.isfinite(sigx) and sigx > 0.0, sigx
    print("ImpactX+openPMD smoke OK: npart=%d steps=%d sigx=%e"
          % (npart, len(steps), sigx))


def _installed(mods):
    # find_spec checks availability WITHOUT importing (executing) the C
    # extension; importing openpmd_api after impactx aborts on macOS, and we
    # want _macos_backtrace() to capture that first.
    return all(importlib.util.find_spec(m) is not None for m in mods)


def _macos_backtrace():
    """macOS: capture a native lldb backtrace of the impactx + openpmd_api
    co-load fault (the missing piece to debug it). No-op elsewhere / no lldb.
    The fault is at the first HDF5 call (io.Series open), not the import, so the
    traced command opens the Series; stop-on-exec=false lets it run to the fault."""
    if sys.platform != "darwin" or not shutil.which("lldb"):
        return
    code = ("import impactx, openpmd_api as io;"
            "io.Series('diags/openPMD/monitor.h5', io.Access.read_only)")
    print("=== lldb backtrace: impactx + openpmd_api io.Series ===", flush=True)
    subprocess.run(
        ["lldb", "-b",
         "-o", "settings set target.process.stop-on-exec false",
         "-o", "run", "-o", "bt all", "-o", "quit", "--",
         sys.executable, "-c", code],
        check=False,
    )
    print("=== end lldb backtrace ===", flush=True)


def main():
    os.chdir(tempfile.mkdtemp(prefix="impactx-smoke-"))  # diags/ go here
    npart = run_fodo()

    # The openPMD read-back deps have no 32-bit wheels; --only-binary avoids a
    # slow source build there. If still unavailable, skip the read-back.
    if not _installed(_IMPORTS):
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "-q", "--only-binary=:all:", *_PIP],
            check=False,
        )
    if not _installed(_IMPORTS):
        print("smoke_example: pandas/openpmd-api unavailable, "
              "skipping openPMD read-back")
        return 0

    _macos_backtrace()  # diagnostic before the in-process co-load below
    analyze(npart)      # imports openpmd_api in-process (aborts on macOS today)
    return 0


if __name__ == "__main__":
    sys.exit(main())
