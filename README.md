# nvcomp-iofilter

This is a pluggable I/O filter for HDF5 that compresses data using the
[nvCOMP CUDA library](https://github.com/NVIDIA/nvcomp). This initial
prototype uses the Snappy byte-level compressor. Future versions may
expose other algorithms supported by nvCOMP.

