# Migrating from 0.1 M1 to 0.2 M2

The package/API version is now `0.2.0-m2`. Existing M1 identifiers, read-only
segment descriptors, packet views, PCAP fixtures, and synthetic queue defaults
remain available. Their requirement coverage keeps `since: 0.1.0-m1`.

New callers should account for these explicit behaviors:

- use `MutableSegmentDescriptor` or synthetic `InputConfig.mutable` before
  requesting an editor; no read-only storage is promoted with a const cast;
- resolve `Accept(null)` and leftover `Continue` with caller configuration;
- submit mutated packets through the current batch owner and call `finalize`
  first;
- treat every mutation/finalization failure as a caller policy decision and
  never retry output of the invalid journal;
- acquire retention only from a setup-allocated pool and complete each lease
  exactly once before shutdown;
- obtain adapter output access through `PacketBatch.outputPacket`; the returned
  opaque `OutputPacket` revalidates owner identity, generation, slot, and
  current access on every length, segment-count, segment, token, and submit
  operation instead of exposing an owner-held `PacketSlot` pointer;
- acquire retention before requesting a non-empty borrowed slice from
  `PacketView.contiguous` or `SegmentIterator.next`, or before requesting a raw
  output segment/token. Such authority cannot be revoked, so a later retain
  fails atomically with `OutstandingBorrow`; use `PacketView.read` when a copy
  is acceptable and retention may follow;
- pass a bounded `ParserConfig` only when overriding the default IPv6 extension
  limit.

The public synthetic-output path is the readiness-checked
`OutputQueue.submitBatch`. It validates and submits through a checked
`OutputPacket` and rejects stale, retained, failed, or unfinalized state before
any token transfer.
