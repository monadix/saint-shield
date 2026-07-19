# API overview

Applications import `saint_shield` from `src/root.zig`. The M1 public surface
provides `foundation` identifiers/budgets/time, `packet` ownership and
segment-safe views, deterministic `io.synthetic` queues, bounded classic-PCAP
fixtures under `io.pcap`, and reproducible seeded traces under `testing`.
Generated Zig documentation is a symbol index and is not the sole API guide.

The core imports no DPDK type. DPDK compatibility code remains under
`src/io/dpdk` and is compiled only by the explicit smoke command.

M1 deliberately does not expose protocol parsing, mutation, dispositions,
retention leases, native processor descriptors, or a pipeline. Those remain
gated to M2 and M3.

M1's first concrete support API is the allocation-free bounded classic-PCAP
parser and deterministic writer under `saint_shield.io.pcap`. See the
[bounded PCAP fixture guide](../user/pcap-fixtures.md) for limits, ownership,
failure categories, and the reproducer workflow.
