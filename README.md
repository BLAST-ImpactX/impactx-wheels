# ImpactX

ImpactX enables high-performance modeling of beam dynamics in particle accelerators with collective effects.

## PyPI Build for Pip

This is a distribution of ImpactX specifically for people that prefer the "pip" installation method.

Because of limitations of pip, we limit this package to be a **sequential CPU build**, i.e., it does not make use of *any* of the accelerated features of ImpactX besides some light-touch vectorization.

If you need advanced features such as:
- multi-core CPU support (OpenMP)
- GPU support (CUDA/HIP/SYCL)
- multi-node support (MPI)

then use *another installation method* [as described in our manual](https://impactx.readthedocs.io/en/latest/install/users.html).

If you have any questions or encounter any issues with installing or running ImpactX, please do not hesitate to [open an issue](https://github.com/BLAST-ImpactX/impactx/issues) or [start a discussion](https://github.com/orgs/BLAST-ImpactX/discussions) to receive help or share feedback.

## Supported CPUs

Because the vectorized wheels are compiled for a baseline instruction set, they require a
reasonably modern CPU (year 2016 or newer):

- **x86-64** Linux/Intel macOS/Windows: Intel CPU of the Haswell generation (2013) or newer,
  or an AMD CPU of the Excavator (2015) / Zen (2017) generation or newer.
- **arm64 / aarch64** Linux/Apple Silcon macOS: all ARMv8-A and newer supported
- **x86-32** 32-bit Linux: all CPUs supported (no SIMD)

## WebAssembly (Pyodide / browser)

We also publish a **WebAssembly** wheel (`wasm32-emscripten`) under the
[PEP 783 `pyemscripten`](https://peps.python.org/pep-0783/) platform tag, so ImpactX can run
in the browser and in Node.js via [Pyodide](https://pyodide.org):

```python
import micropip
await micropip.install("impactx-noacc")
```

This build includes openPMD/HDF5 I/O and the FFT-based solvers (IGF space charge, CSR).

Limitations of the WebAssembly wheel:

- **Single core only.** Stock Pyodide cannot load thread-enabled (`-pthread`) modules, so the
  wheel is built `IMPACTX_COMPUTE=NOACC` (no OpenMP). Multi-threading would require a custom
  from-source, threaded Pyodide served with cross-origin-isolation (COOP/COEP) headers.
- **No explicit SIMD.** Although [WebAssembly SIMD](https://emscripten.org/docs/porting/simd.html)
  (128-bit, part of the WebAssembly 3.0 standard) is widely available, it lacks vectorized
  transcendentals, so `ImpactX_SIMD=ON` is *slower* than scalar on WASM (CI benchmark: ~2.6x
  slower on a compute-bound nonlinear element). The wheel therefore ships as baseline wasm.
- No MPI (multi-node) and no GPU support — as for the other pip wheels above.

## Documentation

Please see the online documentation for detailed examples, references, theory sections on our models, and how-to guides:
https://impactx.readthedocs.io

## Acknowledgements

This work was supported by the Laboratory Directed Research and Development Program of Lawrence Berkeley National Laboratory under U.S. Department of Energy Contract No. DE-AC02-05CH11231.

ImpactX is supported by the CAMPA collaboration, a project of the U.S. Department of Energy, Office of Science, Office of Advanced Scientific Computing Research and Office of High Energy Physics, Scientific Discovery through Advanced Computing (SciDAC) program.
