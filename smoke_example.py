#!/usr/bin/env python3
#
# Copyright 2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
"""Functional smoke test (all platforms incl. wasm/Pyodide): run an ImpactX
FODO example and read its openPMD beam-monitor diagnostics back -- in ONE
process.

Each wheel ships its own compiled HDF5 and crosses the C++ <-> Python (numpy)
boundary by reading the monitor -- the path that crashed on macOS when impactx
re-exported its bundled openPMD/HDF5 (fixed by impactx#1538) and on Windows
when a wheel vendored the MSVC runtime (see check_no_vendored_runtime.py). It
also asserts that impactx and pyAMReX share one AMReX runtime.

Two modes, run the script twice:
  python smoke_example.py              2-way co-load (impactx + openpmd_api).
  python smoke_example.py --with-h5py  3-way co-load (+ h5py).
On native both tear down cleanly on normal exit. On wasm the multi-HDF5 teardown
is flaky (Pyodide's single namespace), so we verify the co-load works and then
os._exit(0) past it.
"""
import gc
import os
import sys
import tempfile

import numpy as np

from impactx import ImpactX, distribution, elements


def _assert_shared_amrex():
    """impactx and pyAMReX must share ONE AMReX runtime (native: one shared
    AMReX library; wasm: the single Emscripten namespace), else pyAMReX objects
    handed across the module boundary break."""
    import amrex.space3d as amr

    assert amr.initialized(), "pyAMReX and ImpactX do not share one AMReX runtime"


def run_fodo():
    """Track a 2 GeV electron Waterbag beam through a FODO cell with monitors."""
    sim = ImpactX()
    sim.space_charge = False
    sim.slice_step_diagnostics = True
    sim.init_grids()
    _assert_shared_amrex()

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
    """Read the beam-monitor openPMD output back via openpmd_api (numpy)."""
    import openpmd_api as io

    series = io.Series("diags/openPMD/monitor.h5", io.Access.read_only)
    steps = list(series.iterations)
    beam = series.iterations[steps[-1]].particles["beam"]
    x = beam["position"]["x"].load_chunk()
    series.flush()
    series.close()  # release HDF5 objects before exit (clean library teardown)

    assert len(x) == npart, len(x)
    assert np.all(np.isfinite(x)), "non-finite position data"
    sigx = float(np.std(x))
    assert sigx > 0.0, sigx
    print("ImpactX+openPMD smoke OK: npart=%d steps=%d sigx=%e"
          % (npart, len(steps), sigx))


def check_h5py():
    """Co-load a THIRD independently-bundled HDF5 (h5py) in the same process and
    round-trip a file -- exercises impactx + openpmd_api + h5py co-loaded."""
    import h5py

    with h5py.File("h5py_check.h5", "w") as f:
        f["x"] = np.arange(8, dtype=np.float64)
    with h5py.File("h5py_check.h5", "r") as f:
        assert f["x"].shape == (8,), f["x"].shape
    print("h5py co-load OK: h5py %s (HDF5 %s)"
          % (h5py.__version__, h5py.version.hdf5_version))


def main():
    with_h5py = "--with-h5py" in sys.argv
    os.chdir(tempfile.mkdtemp(prefix="impactx-smoke-"))  # diags/ go here
    npart = run_fodo()
    # run_fodo()'s ImpactX + BeamMonitor locals are out of scope now; force their
    # collection so ImpactX's bundled-openPMD HDF5 handler (and its custom types:
    # bool enum, complex *, long double) is destroyed HERE, while HDF5 is alive --
    # not at interpreter teardown, when the co-loaded openpmd_api HDF5 is also
    # unwinding and H5Tclose would fault ("not a datatype" -> wasm OOB).
    gc.collect()
    analyze(npart)
    # likewise release openpmd_api's read Series + HDF5 handler now, while HDF5 is
    # still alive, rather than at interpreter teardown alongside the co-loaded
    # second HDF5 (where H5Tclose faults: "not a datatype" -> wasm OOB).
    gc.collect()

    if with_h5py:
        # 3-way co-load: additionally co-load h5py. h5py ships no 32-bit wheels
        # (wasm32 is 32-bit but Pyodide provides it), so skip on 32-bit native.
        on_32bit_native = sys.maxsize < 2**32 and sys.platform != "emscripten"
        if on_32bit_native:
            print("32-bit native -- h5py ships no 32-bit wheel; skipping h5py co-load")
        else:
            check_h5py()

    # The co-load worked (above). On wasm the multi-HDF5 teardown is flaky: in
    # Pyodide's single namespace, H5Tclose of openPMD's custom types (bool enum,
    # complex *, long double) can fault at interpreter exit even after a clean
    # run -- heap-layout-dependent, and it hits the 2-way impactx+openpmd_api case
    # too (H5dont_atexit + the gc.collects reduce but don't eliminate it). So exit
    # past the teardown on wasm; native tears down normally.
    if sys.platform == "emscripten":
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(0)
    return 0


if __name__ == "__main__":
    sys.exit(main())
