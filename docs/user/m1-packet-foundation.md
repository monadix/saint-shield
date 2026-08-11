# M1 packet foundation

M1 is the hardware-free ownership and packet-view layer. It is useful for
adapter authors and deterministic fixture tests; it is not yet a processor
pipeline.

## Ownership

An adapter creates a fixed `packet.TokenTracker`, registers input-owned tokens,
and transfers each received token to worker ownership. A worker must then do
exactly one of the following:

- submit it to an output and let that output complete it;
- return it to the input or pool;
- transfer it into a retention obligation and later complete that obligation.

Invalid transitions, a second completion, and an outstanding shutdown
obligation are separate errors. `verifyReceivedCompleted` is the shutdown gate.

## Packet views

A `PacketSlot` validates a declared total against up to 16 backing segments.
An allocator-owned, address-stable `PacketBatchOwner` holds the generation and
copied slot metadata across processing-call frames. A live opaque `PacketBatch`
handle preserves receive order and provides opaque read-only view handles.
Batch handles contain a process-unique non-pointer owner identity plus a
generation tag; view handles add an index. They never contain or reveal the
owner address. Every operation receives the valid opaque owner separately and
validates owner identity, generation, and index in that order before accessing
slot metadata.
`contiguous` borrows a range when it lies in one segment. `segments` iterates
borrowed pieces. `read` performs an explicit caller-requested copy for ranges
that need a destination buffer.

Every range uses checked addition and bounds. Construct the owner during
adapter/worker setup, keep it alive longer than all derived handles, and end
each generation deterministically:

```zig
const batch_owner = try packet.PacketBatchOwner.init(allocator);
defer batch_owner.deinit(); // only after every derived handle is unreachable

const batch = try batch_owner.begin(origin, slots);
defer batch.invalidate(batch_owner) catch unreachable;

const view = try batch.view(batch_owner, 0);
const packet_len = try view.length(batch_owner);
```

Copying `PacketBatch` does not fork liveness: every copy and derived
view/iterator observes the same owner-controlled generation. After
`PacketBatch.invalidate`, batch access reports `BatchReleased` and every
existing view or iterator operation reports `StaleView`. A later `begin`
advances a monotonic generation and cannot reactivate an older handle. Public
batch/view values contain no owner pointer or mutable fields. Owner construction
uses a thread-safe setup-only monotonic identity allocator; identities are
never reused, and exhaustion returns `OwnerIdentityExhausted` without wrapping.
Safe construction of zero, random, modified, or another live owner's scalar tag
followed by an operation with a valid owner returns `BatchReleased`,
`StaleView`, or `Bounds`; it cannot select an arbitrary address or access the
other owner. Forging the opaque owner pointer itself remains unsafe, and using
any handle after owner destruction violates the owner-lifetime contract.

`SegmentIterator.next(batch_owner)` revalidates its view tag, range, and
progress on every call. It recomputes the segment offset from validated
descriptors with checked arithmetic, so arbitrary or maximum public numeric
state produces a bounded error rather than unchecked indexing or overflow.

## Synthetic queues

`io.synthetic.InputQueue` owns setup fixture bytes and offers immediately
available partial batches without waiting for the requested maximum. Its fixed
script can inject idle polls or input failures. `OutputQueue` can accept,
delay completion, report backpressure, or report an output failure. Rejected
submissions leave the token worker-owned so the caller can apply its configured
policy.

Zero-length behavior is explicit in `InputConfig.zero_length`; M1 tests cover
both allowing and rejecting it. Setup copies fixture bytes into queue-owned
storage, while receive-to-output traversal borrows them. The centralized
abstraction-copy path and explicit `read` site increment distinct real
counters. A `CountingAllocator` wrapper records actual queue allocator calls.
The regression snapshots queue-owned segment identities before receive and
compares them after output submission. Ordinary linear and segmented traversal
keeps abstraction-copy bytes and allocator activity at zero; intentional copy
and allocation negative controls prove both guards can fail. Synthetic receive preflights all
descriptor, token-state, and arithmetic checks before changing any token or
queue cursor, so an injected later-slot failure leaves the entire receive
attempt unchanged.

## Classic PCAP fixtures

`io.pcap` supports bounded classic PCAP version 2.4 in both byte orders and
microsecond/nanosecond timestamp variants. It rejects PCAPNG and unknown magic,
and applies configured limits to snap length, record count, captured bytes, and
zero-length records. Parser errors distinguish truncation, malformed input,
unsupported format, configured limit, and arithmetic overflow.

The streaming parser borrows source bytes without allocation. `Capture` creates
owned fixture storage with a caller allocator. The writer produces deterministic
classic-PCAP bytes with explicit byte order, timestamp resolution, link type,
and limits.

## Verification

From the pinned development shell, run:

```sh
zig build -Doptimize=Debug test
zig build -Doptimize=ReleaseSafe test
zig build -Doptimize=ReleaseFast test
zig build pcap-fuzz-smoke
zig build coverage
zig build coverage-self-test
zig build version-consistency
zig build -Doptimize=ReleaseFast m1-bench
zig build ci-m1
```

The independently invocable cumulative M1 gate is recorded in
`evidence/m1/VERIFICATION.md`. Synthetic results are regression evidence only,
not production capacity claims.
