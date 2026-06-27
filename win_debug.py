#!/usr/bin/env python3
#
# Copyright 2025 The ImpactX Community
#
# Authors: Axel Huebl
# License: BSD-3-Clause-LBNL
#
"""TEMPORARY win64 bring-up probe (remove before merge).

`import impactx` access-violates (0xC0000005) on 64-bit Windows during the
cibuildwheel test step, with no Python traceback (a hard native crash). This
probe localizes it WITHOUT taking the parent process down with it:

  1. Run a staged import sequence (amrex -> impactx -> openpmd_api -> co-load
     round-trip) in a CHILD process under faulthandler, capturing stdout+stderr.
     The last "STEP:" line printed before the child dies names the faulting
     import; faulthandler prints the Python frame of the fault.
  2. If the child crashed and cdb.exe (Windows SDK Debugging Tools) is present,
     run it under cdb to get a NATIVE backtrace -- which names the crashing
     module (amrex_3d / impactx_pybind / bundled openPMD / HDF5), even without
     symbols (module+offset). The venv's python.exe is a LAUNCHER that re-spawns
     the real interpreter as a child, which cdb would not follow, so we debug
     the BASE interpreter directly (sys._base_executable) with the venv
     site-packages injected via PYTHONPATH; plus a child-debugging (-o) fallback.
  3. If the imports survive (e.g. win32, which faults at the HDF5 write rather
     than at import), run the real smoke_example.py so the same Windows test
     command also validates the openPMD/HDF5 co-load round-trip end to end.

Exits with the child's return code so CI still reflects the failure, but only
AFTER all diagnostics have been printed by this surviving parent.
"""
import glob
import os
import subprocess
import sys

# Staged import sequence, run as a child so its crash cannot eat our output.
CHILD = r"""
import faulthandler, sys
faulthandler.enable()


def step(msg):
    print("STEP:", msg, flush=True)


step("python " + sys.version.replace("\n", " "))
step("import amrex.space3d")
import amrex.space3d as amr
step("amrex ok; initialized=%r" % amr.initialized())
step("import impactx")
import impactx
step("impactx ok; version=%s" % getattr(impactx, "__version__", "?"))
step("import openpmd_api")
import openpmd_api as io
step("openpmd_api ok; version=%s" % io.__version__)
step("ALL IMPORTS OK -- co-load survived")
"""


def run(cmd, timeout=900):
    print("\n=== RUN: %s" % " ".join(cmd), flush=True)
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as e:
        print("--- TIMED OUT after %ss ---" % timeout, flush=True)
        print("--- stdout ---\n%s" % (e.stdout or ""), flush=True)
        print("--- stderr ---\n%s" % (e.stderr or ""), flush=True)
        return 0xC0000005
    print("--- stdout ---\n%s" % p.stdout, flush=True)
    print("--- stderr ---\n%s" % p.stderr, flush=True)
    print("--- returncode: %d (0x%08X) ---"
          % (p.returncode, p.returncode & 0xFFFFFFFF), flush=True)
    return p.returncode


def find_cdb():
    pats = [
        r"C:\Program Files (x86)\Windows Kits\10\Debuggers\x64\cdb.exe",
        r"C:\Program Files (x86)\Windows Kits\*\Debuggers\x64\cdb.exe",
        r"C:\Program Files\Windows Kits\10\Debuggers\x64\cdb.exe",
        r"C:\Program Files\Windows Kits\*\Debuggers\x64\cdb.exe",
    ]
    for pat in pats:
        hits = sorted(glob.glob(pat))
        if hits:
            return hits[-1]
    return None


def cdb_backtrace(cdb, label, argv, env):
    """Run argv under cdb, break on the first-chance access violation, dump the
    faulting + all-thread stacks. No symbol server (avoid a network hang) --
    module+offset already names the crashing DLL."""
    cmds = ("sxe av; g; .echo ===CRASH===; .lastevent; .exr -1; .ecxr; "
            "kb 200; .echo ===ALL THREADS===; ~*kb; q")
    full = [cdb, "-g", "-G", "-o", "-c", cmds] + argv
    print("\n=== cdb backtrace [%s]: %s" % (label, " ".join(full)), flush=True)
    try:
        p = subprocess.run(full, capture_output=True, text=True, timeout=900,
                           env=env)
        print(p.stdout, flush=True)
        print(p.stderr, flush=True)
    except subprocess.TimeoutExpired:
        print("(cdb timed out)", flush=True)


def main():
    py = sys.executable
    rc = run([py, "-X", "faulthandler", "-c", CHILD])
    if rc != 0:
        cdb = find_cdb()
        if cdb:
            import site
            no_symsrv = dict(os.environ, _NT_SYMBOL_PATH="")
            # (A) Debug the BASE interpreter directly so cdb owns the crashing
            #     process (the venv python.exe just re-launches it as a child).
            #     Inject the venv site-packages so the imports still resolve.
            base = getattr(sys, "_base_executable", None) or py
            sp = list(site.getsitepackages()) + [
                os.path.join(sys.prefix, "Lib", "site-packages")]
            env_a = dict(no_symsrv, PYTHONPATH=os.pathsep.join(sp))
            cdb_backtrace(cdb, "base-exe+PYTHONPATH",
                          [base, "-X", "faulthandler", "-c", CHILD], env_a)
            # (B) Fallback: debug the venv launcher but follow child processes
            #     (-o), in case (A)'s base/site-packages reconstruction is off.
            if base != py:
                cdb_backtrace(cdb, "venv+childdbg",
                              [py, "-X", "faulthandler", "-c", CHILD], no_symsrv)
        else:
            print("\n(no cdb.exe found; faulthandler output above is the lead)",
                  flush=True)
        return rc
    # Imports survived (the win32 case): run the real co-load smoke -- ImpactX
    # writes an openPMD/HDF5 BeamMonitor, openpmd_api reads it back -- to
    # validate the HDF5 backend end to end.
    smoke = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "smoke_example.py")
    print("\n=== imports OK; running smoke_example.py (HDF5 round-trip) ===",
          flush=True)
    return run([py, smoke])


if __name__ == "__main__":
    sys.exit(main())
