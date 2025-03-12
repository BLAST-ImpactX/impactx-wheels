# ImpactX

ImpactX enables high-performance modeling of beam dynamics in particle accelerators with collective effects.

## PyPI Build for Pip

This is a distribution of ImpactX specifically for people that prefer the "pip" installation method.

Because of limitations of pip, we limit this package to be a **sequential CPU build**, i.e., it does not make use of *any* of the accelerated features of ImpactX.

If you need advanced features such as:
- multi-core CPU support (OpenMP)
- GPU support (CUDA/HIP/SYCL)
- multi-node support (MPI)

then use *another installation method* [as described in our manual](https://impactx.readthedocs.io/en/latest/install/users.html).

If you have any questions or encounter any issues with installing ImpactX, please do not hesitate to [open an issue](https://github.com/BLAST-ImpactX/impactx/issues) or [start a discussion](https://github.com/orgs/BLAST-ImpactX/discussions) to receive help or share feedback.

## Documentation

Please see the online documentation for detailed examples, references, theory sections on our models, and how-to guides:
https://impactx.readthedocs.io

## Acknowledgements

This work was supported by the Laboratory Directed Research and Development Program of Lawrence Berkeley National Laboratory under U.S. Department of Energy Contract No. DE-AC02-05CH11231.

ImpactX is supported by the CAMPA collaboration, a project of the U.S. Department of Energy, Office of Science, Office of Advanced Scientific Computing Research and Office of High Energy Physics, Scientific Discovery through Advanced Computing (SciDAC) program.
