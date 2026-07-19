# Module: io

## Responsibility

`io` owns adapter namespaces and keeps backend details downstream of the core.
M1 adds the bounded pure-Zig classic-PCAP fixture reader/writer alongside the
synthetic adapter work. The DPDK 25.11.2 virtual-ring compatibility code remains
a private M0-V spike; production DPDK is M4.

It does not define packet semantics, processor behavior, or select a backend
for an application.

## Requirements and invariants

The adapter contract owns the I/O portions of FR-PKT-003..004/011..014 and
INV-PKT-001. PCAP fixture input supports FR-TEST-002 and the M1 bounded-capture
and fuzz-corpus evidence. It is not a live packet input contract.

## Public contract

`pcap.Parser` borrows untrusted bytes and iterates classic-PCAP records without
allocation. `pcap.Capture.parseAlloc` copies validated records into caller-owned
storage. `pcap.writeAlloc` emits deterministic version-2.4 captures. Every entry
point requires `pcap.Limits`, including an explicit zero-length-record policy.
The [PCAP fixture guide](../../user/pcap-fixtures.md) documents the supported
surface. The DPDK compatibility API remains private test evidence.

## Dependencies

PCAP depends only on Zig's standard library. Adapters may depend on core
packet/foundation contracts; those core modules never import an adapter. The
public library has no libc, libpcap, or DPDK dependency.

## Object lifecycle and ownership

`pcap.Parser` owns nothing and every returned record expires with its input
bytes. `pcap.Capture` owns one record table and one packed payload allocation;
`deinit` releases both. The deterministic writer returns one caller-owned byte
slice. The private DPDK smoke context retains its separate EAL/ring/mempool
ownership and cleanup accounting.

## Concurrency

Parser values are independent forward iterators; no internal shared or global
state exists. Sharing input or owned captures between threads follows ordinary
immutable-slice rules. Future queues are single-worker-owned.

## Allocation and work bounds

Parsing is allocation-free and checks record count, aggregate captured bytes,
global snaplen, each record length, and all offset arithmetic. Owned parsing
performs exactly the allocations needed for the record table and packed bytes;
writing performs one exact-size allocation. These off-path fixture operations
do not add packet-path allocation.

## Failure behavior

PCAP reports truncated, malformed, unsupported, configured-limit, and arithmetic
failures as distinct stable categories with detailed error tags. Allocation
failure propagates and every constructor path is cleanup-swept. Existing DPDK
failure injection continues to reconcile all virtual tokens.

## Security boundary

Capture bytes are untrusted. Classic magic/version, timestamps, snaplen, record
length relationships, aggregate counts, payload bounds, and checked additions
are validated before slices are exposed. PCAPNG and other magic/version variants
fail as unsupported. The separate narrow DPDK C view remains layout-asserted.

## Performance budget

Borrowed PCAP parsing performs no payload copy; owned fixture construction copies
once by explicit caller request. PCAP is support tooling rather than a throughput
backend. M4 still benchmarks DPDK translation tax separately.

## Tests and evidence

PCAP unit tests cover every representable structure truncation, four endian and
resolution variants, malformed lengths, timestamps, all limits, both zero-byte
policies, deterministic output, error classes, and allocation-failure cleanup.
`zig build pcap-fuzz-smoke` decodes the reviewed corpus, replays it twice, checks
Zig branch coverage, and runs a bounded AFL++ smoke. `zig build dpdk-smoke`
retains the separate virtual token checks.

## Alternatives and evolution

The classic subset may add an independently bounded PCAPNG reader when fixture
needs justify it; unsupported input must not be silently reinterpreted. M1 uses
synthetic queues as the semantic reference. M4 may change the private DPDK
representation only with ABI, correctness, and benchmark evidence.

## Open questions

PCAPNG block support is intentionally absent until a concrete fixture requires
it. Physical-device and AF_XDP operational questions remain deferred.
