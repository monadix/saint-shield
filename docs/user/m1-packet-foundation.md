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
A live `PacketBatch` preserves receive order and provides read-only views.
`contiguous` borrows a range when it lies in one segment. `segments` iterates
borrowed pieces. `read` performs an explicit caller-requested copy for ranges
that need a destination buffer.

Every range uses checked addition and bounds. Call `PacketBatch.invalidate` at
the end of processing; subsequent use of an existing view reports `StaleView`.
Keep the batch address stable until every attempted access has ended.

## Synthetic queues

`io.synthetic.InputQueue` owns setup fixture bytes and offers immediately
available partial batches without waiting for the requested maximum. Its fixed
script can inject idle polls or input failures. `OutputQueue` can accept,
delay completion, report backpressure, or report an output failure. Rejected
submissions leave the token worker-owned so the caller can apply its configured
policy.

Zero-length behavior is explicit in `InputConfig.zero_length`; M1 tests cover
both allowing and rejecting it. Setup copies fixture bytes into queue-owned
storage, while receive-to-output traversal borrows them. The packet-path copy
counters remain zero for ordinary traversal.

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
```

The complete cumulative milestone gate is recorded in
`evidence/m1/VERIFICATION.md`. Synthetic results are regression evidence only,
not production capacity claims.
