# API overview

Applications import `saint_shield` from `src/root.zig`. The M0-V surface exposes
the accepted module dependency skeleton without claiming later semantics.
Generated Zig documentation is a symbol index and is not the sole API guide.

The core imports no DPDK type. DPDK compatibility code remains under
`src/io/dpdk` and is compiled only by the explicit smoke command.

