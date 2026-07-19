# Module: Core Packet and Batch API

## Responsibility

Define backend-neutral, borrow-scoped packet access; ordered batches; active selection; structured mutation; disposition recording; origin/output identities; and final completion accounting. It does not receive/transmit packets or choose worker scheduling.

## Public types

```text
InputId, QueueId, OutputId, GenerationId, PacketIndex
InputOrigin { input_id, queue_id, adapter_metadata_id? }
PacketBatch<Capabilities, MaxBatch>
PacketView
PacketEditor
RawPacketEditor (unsafe capability)
PacketSelection
DispositionWriter
DropReasonId, CompletionId
```

The concrete Zig API uses iterator/select methods rather than exposing mutable disposition arrays. A processor can apply one disposition to a selection, update individual indices, intersect selections, or iterate set bits. All operations are bounds-checked in safe builds and construction guarantees valid indices in fast builds.

## Packet parse cache

Parsing is lazy and batch-scoped. The built-in parser can expose Ethernet/VLAN, IPv4, IPv6 with bounded extension walk, TCP, UDP, ICMP metadata needed by L4 processors. Cache entries distinguish `unparsed`, `present`, `absent`, `truncated`, `malformed`, and `unsupported`. A later processor reuses earlier parsing; cache memory is preallocated.

Fragment policy is explicit:

- IPv4 non-initial fragments have no accessible transport ports.
- IPv6 fragment headers follow the same absent-aware rule.
- Reassembly is a separate stateful processor and never implicit.

## Disposition resolution

Internally every slot begins `active/Continue`. Terminal operations set a tag and remove the bit from `active`. `Accept(null)` resolves through the input/application default output. `Redirect` must target a configured compatible output. `Complete` invokes a registered bounded completion handler. `Retain` is recorded only after a lease succeeds.

At pipeline end, unresolved `Continue` maps through an explicitly configured pipeline default. Exactly one adapter completion then consumes the token.

## Mutation API

Structured supported fields initially include IPv4 DSCP/TTL, IPv6 traffic class/hop limit, TCP flags where semantically valid, and L2/L3 addresses when output capabilities permit. Address/port mutation records checksum dependencies. Length-changing edits are requests so an adapter can reject insufficient headroom, tailroom, or segment capability before partial mutation.

Raw mutation is not silently checksum-aware. The caller marks invalidated layers or requests full software validation; otherwise finalization fails closed according to assembly policy.

## Internal representation

- `PacketSlot`: adapter token pointer/index, total length, first-segment fast slice, segment descriptor reference, metadata flags.
- `active`: `u64` for initial maximum 64.
- dispositions: tag byte plus union-like side arrays for output/reason/completion.
- parse cache: fixed per-slot header offsets, status, and selected decoded fields.
- mutation journal: per-slot dirty flags and signed length delta.

This layout is internal and benchmark-driven.

## Tests

- Every batch size from 1 through maximum, especially partial batches.
- Random selection/disposition sequences against a simple set-model oracle.
- Truncated/malformed headers at every byte boundary.
- IPv4 options, IPv6 extension bounds, fragments, VLAN stacks within limit.
- Structured and raw mutation with Scapy checksum/length oracle.
- Chained-segment reads split at every header byte; multi-segment mutation when implemented.
- Double completion, missing completion, stale handle, and failed-retention injection.

## Requirement ownership

Primary: FR-PKT-001..013, FR-TEST-002..003, AC-001, AC-002, AC-003, AC-010. Shared: FR-PKT-014, processor capability and mutation quality gates.

