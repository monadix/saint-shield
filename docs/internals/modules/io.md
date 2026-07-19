# Module: io

## Responsibility

`io` owns adapter namespaces and keeps backend details downstream of the core.
M0-V exposes synthetic/PCAP sentinels and a private DPDK 25.11.2 virtual-ring
compatibility spike. Concrete public queues begin in M1; production DPDK is M4.

It does not define packet semantics, processor behavior, or select a backend
for an application.

## Requirements and invariants

The future adapter contract owns the I/O portions of FR-PKT-003..004/011..014
and INV-PKT-001. M0-V verifies only the ABI and token-lifecycle boundary.

## Public contract

`synthetic` and `pcap` are documented namespaces whose current
`scaffold_ready` values are compile sentinels. The DPDK compatibility API is
private test evidence and is not application API.

## Dependencies

Adapters may depend on core packet/foundation contracts; those core modules
never import an adapter. The public library has no libc or DPDK dependency.

## Object lifecycle and ownership

The private smoke context owns EAL, one mempool, RX/TX rings, one virtual port,
and its prepared token. A batch RX call transfers a ring-owned token to Zig;
Zig reads the asserted view/payload directly. An accepted TX prefix transfers
ownership back to the TX ring. Rejected or locally failed tokens are released
by the current Zig owner. Destruction drains both rings, releases any prepared
token, closes the port, frees rings/pool/EAL, and reconciles allocation,
completion, and mempool counts.

## Concurrency

The M0-V context is single-threaded and process-local. Future queues are
single-worker-owned; cross-queue sharing requires a separate reviewed design.

## Allocation and work bounds

Setup may allocate. Each M0-V batch is bounded to one token; field/payload
access in Zig has no per-field C call. Future maximum batches remain bounded to
64 and packet-path allocation follows INV-RES-001.

## Failure behavior

Deterministic injection covers failures after pool, rings, port, RX enqueue, TX
rejection, and TX acceptance before completion. Every path reconciles RX/TX
rings and restores the mempool count.

## Security boundary

The narrow C view is layout-asserted against `rte_mbuf`; the reference-count
slot is reserved bytes and cannot be accessed by Zig. Payload access relies on
the live context-owned mbuf, validated offsets/lengths, single ownership, and
single-threaded execution.

## Performance budget

The spike permits batch-level RX/TX calls and direct Zig field access, with no
payload copy solely for abstraction. M4 must benchmark translation tax against
a minimal handwritten adapter.

## Tests and evidence

`zig build dpdk-smoke` checks C/Zig layout agreement, direct payload reads,
normal RX/TX completion, every injected cleanup path, and exact pool balance in
no-huge/no-PCI virtual mode.

## Alternatives and evolution

M1 uses synthetic queues as the semantic reference. M4 may change the private
DPDK representation only with ABI, correctness, and benchmark evidence.

## Open questions

Physical-device and AF_XDP operational questions remain in deferred M0-H/M4
gates, not in the M0-V public contract.
