# Memory, Ownership, and Mutation

## Ownership states

Every backend packet storage token is in exactly one state:

```text
input-owned -> worker-owned -> output-owned
                         \-> returned-to-input/pool
                         \-> retained-by-contract
```

The packet slot is a non-owning view of a worker-owned token. `PacketBatch` and every view/editor borrow the slot for the `processBatch` call. Native processors cannot store these types in ordinary long-lived state because lifetimes are represented by scoped/generic context types; any escape via pointer casts is an explicitly unsafe contract violation.

Retention is not a boolean disposition. The processor requests a `RetentionLease` from a configured bounded pool; only success transfers a backend token and records a completion obligation. Exhaustion returns a bounded error immediately. Shutdown verifies that all leases completed or reports a leak.

## Packet storage abstraction

`PacketStorage` is internal and adapter-specific. `PacketView` exposes:

- total length;
- `contiguous(range) -> ?[]const u8` fast path;
- `read(range, destination) -> result` for cross-segment access;
- bounded segment iteration;
- framework metadata.

No public API promises one contiguous mutable slice. Phase 1 may reject multi-segment input at adapter assembly with an explicit unsupported capability; the interface is already segment-safe so support can be added without API breakage.

## Prepared and worker memory

- Candidate preparation receives a `BudgetAllocator` that accounts current and peak bytes and refuses the hard limit.
- Each generation normally has an arena; individual frees are unnecessary and destruction is deterministic.
- Shared immutable data uses explicit generation ownership/reference records, not hidden allocator sharing.
- Worker state is allocated before activation and aligned to avoid false sharing.
- Hot scratch is fixed for the assembled `max_batch` and output count.
- Adapter pools (DPDK mempool, AF_XDP UMEM) retain their native ownership rules and are not general framework allocators.

## Mutation capabilities

1. `PacketView`: read-only.
2. `PacketEditor`: structured supported fields and bounded prepend/append/trim requests.
3. `RawPacketEditor`: trusted byte writes and segment operations.
4. `BackendNativeAccess`: unsafe, adapter-specific, non-portable escape hatch.

Structured edits update a mutation journal containing changed layer, length delta, checksum needs, and offload eligibility. The finalizer applies or verifies IPv4 header and TCP/UDP pseudo-header checksums, packet lengths, DPDK offload flags, and output headroom/tailroom. A failed edit is atomic at API level where feasible; otherwise the packet becomes invalid and must receive the configured failure disposition. It never continues with silently inconsistent headers.

## Bounds and parser safety

All offsets use checked integer arithmetic. Parsers return absent/truncated/malformed distinctly. IPv6 extension traversal and nested encapsulation have configured maximum headers/bytes. Fragments are identified; processors never receive fabricated L4 fields from non-initial fragments. Network byte order is explicit in types or conversion functions.

## Debug instrumentation

Debug/ReleaseSafe tests add a batch-generation cookie to packet handles, poison released slot metadata, track token state, and assert exactly one completion. These checks are removable from ReleaseFast but their behavior is also covered by synthetic-backend ownership tests.

