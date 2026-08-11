# M2 packet-processing internals

## Fixed storage

Each live `PacketBatchOwner` preallocates 64 slots, parser cache entries, and
mutation journals. `PacketSelection` is represented by one opaque `u64`.
Disposition values and all resolution groups are fixed arrays. No parse,
selection, disposition, edit, finalization, output grouping, or lease operation
allocates on the packet path.

Read-only `SegmentDescriptor` remains unchanged. Mutability is introduced only
by `MutableSegmentDescriptor`, which carries the writable storage, active
offset/length, independently validated headroom/tailroom partition, and
same-length/resize capabilities. There is no const cast. The synthetic adapter
defaults to the M1 read-only behavior and opts into mutable descriptors and
room explicitly.

## Parser rules

All byte reads are segment-safe and use checked offsets. Ethernet accepts at
most two 802.1Q/802.1ad tags. IPv4 validates version, IHL/options, total length,
and fragment fields. IPv6 validates the fixed header and walks Hop-by-Hop,
Routing, Destination, Fragment, and AH headers under defaults of 8 headers and
256 bytes; caller overrides are capped at 16/1024. ESP and otherwise valid but
unimplemented protocol structures report `unsupported`.

Protocol mismatch and non-initial-fragment transport are `absent`; unavailable
declared bytes are `truncated`; invalid values, lengths, or ordering are
`malformed`; bounded-capability exclusions are `unsupported`. ICMPv4/v6 is
parse-only. There is no tunnel parser or reassembly.

## Mutation and finalization

Editors are scalar owner-identity/generation/index handles, like packet views.
Each successful edit invalidates the cache and journals dirty layers, signed
length delta, checksum/pseudo-header dependencies, and offload eligibility.
Every fallible validation precedes a byte or descriptor update. Resize requires
one mutable segment. A deterministic pre-write injection hook verifies failed
edits leave bytes unchanged.

The software finalizer first parses, rejects invalid journals/incomplete
transport fragments, validates every destination range, and calculates all
projected lengths/checksums before its first write. It then updates lengths and
checksums, reparses, and marks the journal finalized. Output rejects any failed,
invalid, or unfinalized journal and any IPv6 UDP zero checksum.

## Ownership and ordering

Terminal dispositions are validated against the whole active selection before
any slot changes, preserving failure atomicity and INV-PKT-004. Group resolution
walks slots once in receive order. Retention records copy current slot metadata
only after capacity/provenance validation and token transfer. A private
per-slot access state then revokes all batch-side view/editor/raw and output
capabilities in the same no-failure transition. Batch output access uses an
opaque owner/generation/index `OutputPacket`; each descriptor, segment, token,
and submit operation revalidates current access, and no batch method exposes a
pointer to owner-held slot storage. Failed acquisition leaves both worker
ownership and batch access unchanged. Leases encode pool identity, generation,
and bounded record index; completion does not restore batch access, and record
or owner-generation reuse makes older handles stale.

Non-empty slices from `PacketView.contiguous` and `SegmentIterator.next`, plus
raw segments or tokens from `OutputPacket`, cannot carry a revocation check
after return. Issuing any of them sets a generation-local per-slot escape
barrier. `RetentionPool.acquireBound` checks that barrier before capacity,
generation publication, or token transfer and returns `OutstandingBorrow`
without changing disposition, ownership, or batch access. Copy-only
`PacketView.read` does not set the barrier. Synthetic `submitBatch` uses the
checked output handle and transfers the current token exactly once.
