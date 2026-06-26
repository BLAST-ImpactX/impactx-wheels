#!/usr/bin/env python3
#
# Copyright 2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
"""WASM/Pyodide smoke test + micro-benchmark for the ImpactX wheel.

The import of ``impactx`` is the real pass/fail gate (it loads the compiled
wasm extension and all statically-linked deps). On top of that we run a small
self-contained tracking problem and print the wall-clock time, so that across
the SIMD-on/off CI matrix the ``BENCH ...`` log lines let us compare whether
WebAssembly SIMD actually speeds up a cheap linear element vs a compute-bound
(nonlinear, transcendental-heavy) one.

Kept single-threaded and free of file output so it runs inside the cibuildwheel
Node/Pyodide sandbox. Usage:

    python wasm_smoke.py [npart] [nsteps]
"""
import sys
import time

import impactx
from impactx import ImpactX, distribution, elements, push

print("ImpactX %s imported OK" % impactx.__version__, file=sys.stderr)


def interop_check(sim):
    """Verify that the `impactx` and `amrex` extension modules share ONE AMReX
    runtime. ImpactX hands pyAMReX objects across the module boundary (e.g.
    ``sim.particle_container()`` returns an ``amrex.space3d`` type), which only
    works if both modules link a single shared AMReX -- one copy of the global
    singletons (runtime, arenas, ParmParse, RNG) and one RTTI / pybind11 type
    registry. With AMReX statically linked into each module there are two copies
    and this check fails: that is the long-standing "static AMReX" breakage.
    """
    try:
        import amrex.space3d as amr
    except Exception as e:  # pragma: no cover - module may be absent
        print("INTEROP skip: cannot import amrex.space3d (%s)" % e,
              file=sys.stderr)
        return None
    shared = amr.initialized()
    pc = sim.particle_container()  # impactx returns a pyAMReX type
    print("INTEROP amrex.initialized()=%s particle_container=%s"
          % (shared, type(pc).__module__ + "." + type(pc).__name__),
          file=sys.stderr)
    assert shared, (
        "pyAMReX and ImpactX do NOT share one AMReX runtime "
        "(static-AMReX duplicate-globals bug)"
    )
    return shared


def run(npart=20000, nsteps=100):
    sim = ImpactX()
    sim.particle_shape = 2
    sim.slice_step_diagnostics = False
    sim.init_grids()

    interop_check(sim)

    # reference particle: 2 GeV electrons
    sim.beam.ref.set_species("electron").set_kin_energy_MeV(2.0e3)

    # a waterbag bunch
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
    sim.add_particles(1.0e-9, distr, npart)
    beam = sim.beam
    assert beam.total_number_of_particles() == npart

    # Two hot loops to isolate the SIMD effect (identical work on every CI row,
    # so the SIMD-on vs SIMD-off comparison is fair):
    #   linear  -> a cheap linear map (Drift: x += px*ds), ~memory-bound, little
    #              for SIMD to gain.
    #   compute -> the exact nonlinear sector bend, which evaluates several
    #              sqrt / asin / sincos per particle -> compute-bound, the case
    #              where AMReX vir-simd vectorization should actually pay off.
    dt_lin = _bench(beam, elements.Drift(ds=0.5), npart, nsteps, "linear")
    dt_cmp = _bench(
        beam, elements.ExactSbend(name="b", ds=0.25, phi=2.0), npart, nsteps,
        "compute",
    )

    try:
        sim.finalize()
    except Exception:
        pass
    return dt_lin, dt_cmp


def _bench(beam, element, npart, nsteps, label):
    t0 = time.perf_counter()
    for _ in range(nsteps):
        push(beam, element)
    dt = time.perf_counter() - t0
    # machine-greppable benchmark line for cross-row (SIMD on/off) comparison
    print(
        "BENCH %-8s npart=%d nsteps=%d elapsed=%.3fs" % (label, npart, nsteps, dt),
        file=sys.stderr,
    )
    return dt


def main(argv):
    npart = int(argv[0]) if len(argv) > 0 else 50000
    nsteps = int(argv[1]) if len(argv) > 1 else 200
    run(npart, nsteps)
    print("ImpactX WASM smoke test PASSED", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
