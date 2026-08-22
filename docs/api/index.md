# API overview

Applications import `saint_shield` from `src/root.zig`. The M3 public surface
provides `foundation` identifiers/budgets/time, `packet` ownership and
segment-safe views, deterministic `io.synthetic` queues, bounded classic-PCAP
fixtures under `io.pcap`, bounded parsing, selection/dispositions,
mutation/finalization, retention, and reproducible seeded traces under
`testing`, plus native `processor` declarations and generated `pipeline`
composition.
Generated Zig documentation is a symbol index and is not the sole API guide.

The core imports no DPDK type. DPDK compatibility code remains under
`src/io/dpdk` and is compiled only by the explicit smoke command.

`ProcessorDescriptor`, `Pipeline`, `PipelineWithInputMetadata`, and
`ProcessorTestHarness` are the M3 entry points. Generated processor contexts
expose only declared call-scoped capabilities and never return packet ownership
authority. See the [M3 native pipeline guide](../user/m3-native-pipeline.md).

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

The packet-processing additions are documented in the
[M2 guide](../user/m2-packet-processing.md). Public entry points include
`PacketView.parse`, `PacketSelection`, `DispositionWriter`,
`DispositionGroups.resolve`, `PacketBatch.editor`,
`PacketBatch.unsafeRawEditorForTesting`, `PacketEditor.finalize`, and
`RetentionPool`. Mutation-aware output validates through
`PacketBatch.outputPacket` and submits with an opaque checked `OutputPacket`;
the batch API does not expose a pointer to owner-held slot storage.
