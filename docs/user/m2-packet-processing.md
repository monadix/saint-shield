# M2 packet processing

Saint Shield 0.2 adds bounded parsing, batch selection, terminal dispositions,
mutation, finalization, and explicit retention. This remains a local
synthetic/virtual contract; it is not a production capacity claim.

## Processing a batch

Create a `PacketBatch` from receive-order slots and use `PacketView.parse` for
lazy Ethernet, up-to-two-VLAN, IPv4/IPv6, TCP/UDP, and parse-only ICMP fields.
Each layer reports `unparsed`, `present`, `absent`, `truncated`, `malformed`, or
`unsupported`. IPv4 options and bounded IPv6 extension chains are supported.
Non-initial fragments expose no transport fields. There is no implicit tunnel
decapsulation or reassembly.

`PacketSelection` is an opaque one-`u64` value for batches through 64 packets.
Construction and membership are checked; intersection, removal, count, and
receive-order set-bit iteration allocate nothing. `DispositionWriter` starts
all slots at `Continue`. A terminal write clears active state and cannot be
overwritten or reactivated.

At pipeline end, callers must supply both an explicit leftover-`Continue`
policy and a default output for `Accept(null)`. `DispositionGroups.resolve`
rejects unknown outputs and builds bounded receive-order output groups plus
separate drop, completion, and retention groups.

## Mutation and output

Ordinary processors use owner/generation-bound `PacketEditor` methods for L2
addresses; IPv4 DSCP, TTL, and addresses; IPv6 traffic class, hop limit, and
addresses; TCP flags; and TCP/UDP ports. Same-length writes cross mutable
segments. Prepend, append, and head/tail trim require one mutable linear
descriptor with enough declared room. A failed edit is byte-atomic, marks the
journal invalid, and requires an explicit caller drop/return/completion policy.

`RawPacketEditor` is available only through the explicitly unsafe testing/trust
mint and every write declares invalidated layers or full software validation.
It is not silently checksum-aware.

Call `PacketEditor.finalize` before output after any successful edit. It updates
IPv4 total length/header checksum, IPv6 payload length, UDP length, and TCP/UDP
IPv4/IPv6 checksums. Legal existing IPv4 UDP zero checksums are preserved when
transport dependencies did not change. IPv6 UDP zero, incomplete-fragment
transport edits, failed edits, invalid raw writes, and dirty/unfinalized packets
are rejected by `validateForOutput`. Synthetic output uses the current
owner generation through an opaque `OutputPacket`; every length, segment-count,
segment, token, and submission operation revalidates owner identity,
generation, slot index, and current access. No batch output API returns a
pointer to owner-held `PacketSlot` storage, so a resized descriptor cannot be
replaced by a stale receive copy or observed through a pointer retained across
generation reuse.

## Retention

`RetentionPool` is setup-allocated and bounded. Processors acquire a lease only
through `DispositionWriter.retain`, which checks capacity and worker-token
provenance before transfer; exhaustion leaves ownership and batch access with
the worker. Success revokes batch views, editors, raw authority, and output
access for that slot. The opaque generation lease supports bounded reads and
exactly-once completion. Revocation persists after completion; stale/double
completion is rejected, and `verifyShutdown` reports live lease leaks.

Non-empty slices returned by `PacketView.contiguous` or
`SegmentIterator.next`, and raw segment/token authority returned by
`OutputPacket`, are borrow-scoped to the current `processBatch` call and cannot
themselves be revoked. Request retention before issuing any such authority. A
later `DispositionWriter.retain` fails atomically with `OutstandingBorrow`,
leaving the token worker-owned and all batch access unchanged. `PacketView.read`
copies into caller storage and does not create this barrier, so a packet read
only through `read` remains retainable.

## Verification commands

```sh
zig build ci-m1
zig build m2-scapy-differential
zig build m2-parser-fuzz-smoke
zig build m2-finalizer-fuzz-smoke
zig build m2-fuzz-evidence
zig build -Doptimize=ReleaseFast m2-bench
```

Random/fuzz failures report the seed/path and an `afl-tmin` minimized hex trace.
Replay a raw input with `sh tools/m2/fuzz-smoke.sh parser --reproduce RAW_INPUT`
or the equivalent `finalizer` command.
The retained summaries under `evidence/m2/` bind each clean smoke campaign to
its source commit/tree, AFL++ version, source and seed hashes, settings, result,
and failure workflow. They intentionally do not claim volatile discovery counts.
The checked benchmark artifact covers batches 1/4/8/16/32/64 and is host-local
regression evidence only.
