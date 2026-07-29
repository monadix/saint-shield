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

`saint_shield.packet.PacketBatchOwner` is an allocator-owned, address-stable
generation owner kept across processing calls. Construction assigns a
process-unique, monotonic non-pointer identity. `begin` returns an opaque batch
tag containing that identity plus a generation; derived views add an index.
Neither scalar contains the owner address. Operations such as
`batch.len(owner)`, `view.length(owner)`, and `iterator.next(owner)` receive the
valid owner separately and validate identity, generation, and public state
before private storage access. Cross-owner handles are rejected without
changing either owner. Invalidating a batch rejects every alias and iterator,
and a later generation cannot reactivate an older handle. Destroy the owner
only after all derived handles are unreachable.
