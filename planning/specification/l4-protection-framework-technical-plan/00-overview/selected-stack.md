# Selected Technical Stack

Versions are exact baseline inputs, not permanent API promises. Updating one requires compatibility tests and a dependency ADR.

## Runtime and build

| Component | Baseline | Status | Rationale |
| --- | --- | --- | --- |
| Language/toolchain | Zig 0.16.0 | Accepted baseline | Current stable release on the research date; native requirement; strong C interop and comptime composition |
| Build | `zig build` + `build.zig.zon` | Accepted baseline | One canonical entry point for libraries, examples, tests, docs, and C adapter compilation |
| Production OS | Linux | Accepted baseline | DPDK and AF_XDP support; CPU affinity, NUMA, huge pages, perf events |
| Architectures | x86-64 and AArch64 | Accepted baseline | Both are common dataplane targets; compile and semantic CI for both, hardware performance CI per available NIC |
| Safe release build | `ReleaseSafe` | Initial production default | Keeps runtime safety while correctness matures |
| Peak build | `ReleaseFast` | Benchmark and opt-in production | Enabled only after differential tests show the same behavior and benchmark evidence justifies lost checks |

Do not track Zig master. Zig generated API documentation is still described as experimental, so the project must not make generated autodoc its only external reference.

## Packet I/O

| Adapter | Version/platform | Order | Role |
| --- | --- | --- | --- |
| `io.synthetic` | Pure Zig | First | Deterministic packets, failure injection, unit/integration tests, benchmarks without NIC effects |
| `io.dpdk` | DPDK 25.11.2 LTS | First production | Highest-confidence high-throughput backend; pinned LTS line through its stated support window |
| `io.af_xdp` | Linux 6.12 LTS minimum; 6.18 LTS recommended; libxdp/libbpf pinned by adapter | After DPDK boundary is stable | Kernel-driver coexistence, XDP steering, copy and zero-copy modes |
| `io.pcap` | Pure Zig reader/writer subset | Test/support | Replay and capture artifacts; not a throughput backend |

The core links none of these. Application build options select adapters. The DPDK adapter uses a very small compatibility header for macros/static inline access and batch calls; it must not copy packet payloads into core-owned buffers. ABI assertions cover imported struct sizes, offsets, and required feature flags.

## Concurrency and memory

- One polling worker per RX queue by default; explicit CPU and NUMA placement.
- C11/Zig release/acquire atomics for generation publication and relaxed atomics for independent metric cells.
- QSBR implementation in Zig with one cache-line-separated epoch cell per worker; DPDK RCU is a behavioral reference, not a core dependency.
- Per-worker fixed scratch: packet slots, active bitset, dispositions, parser cache, output bursts, metric cells, and event ring producer state.
- Per-generation budgeted arena for parsed artifacts and immutable lookup structures.
- General-purpose allocation is permitted in preparation/management contexts and forbidden in `processBatch` unless a processor declares and receives a bounded pool.

## Policy and state

| Concern | Baseline | Why |
| --- | --- | --- |
| Grammar | Hand-written lexer + Pratt/recursive-descent parser | Good source spans and recovery without a parser-generator runtime |
| Semantic model | Typed AST to canonical typed IR | Type and availability errors are preparation-time failures |
| Execution | Immutable compact instruction blocks, scalar per packet initially | Simple semantic oracle; bounded execution; no JIT security cost |
| Sets | Sorted intervals for ports, compressed prefix trie for IP prefixes, fixed hash set for exact values | Representations match access patterns and are selected at preparation |
| Explanation | Reference evaluator over typed IR with trace | No trace branches in production evaluator |
| Stateful map | Fixed-capacity open-addressed table per worker | Explicit memory and exhaustion; no shared lock |
| Expiry | Hierarchical timing wheel advanced by monotonic time | Bounded incremental expiry rather than full-table scans |
| Meter | Integer token bucket/GCRA-style primitives with saturating arithmetic | Deterministic testable time and no floating-point drift |

The first policy engine must not depend on DPDK ACL. A later lowering may use DPDK ACL for eligible N-tuples because DPDK supplies scalar and SIMD classifiers, but eligibility and semantic equivalence must be proven by differential tests.

## Observability

- Framework-owned metric registry with stable numeric handles and build/preparation-time cardinality checks.
- Counter/gauge cells are 64-bit and cache-line grouped by writer, not by metric name.
- Histograms use fixed application-selected boundaries; no runtime-created buckets.
- One SPSC event ring per worker with fixed header and bounded payload bytes.
- First exporter: Prometheus text scrape module outside workers.
- First event consumers: bounded binary file and debug JSON Lines consumers outside workers.
- OTLP is deferred to an exporter module; the core does not adopt the OpenTelemetry SDK data model.

## Verification and tooling

| Tool/form | Use |
| --- | --- |
| `zig test` | Unit, doctest, compile-time contract, deterministic integration tests |
| Custom seeded property runner | Packet parsers, checksums, bitsets, policy equivalence; seed printed on failure |
| Coverage-guided fuzz job | Artifact parsers, packet parsers, mutation finalizer, capture reader; exact engine selected in toolchain spike |
| TLA+ / TLC | Generation publication, worker online/offline, retirement, rollback, and bounded ring state models |
| Scapy | External packet construction/checksum oracle in integration tests only |
| `perf stat`/`perf record` | cycles, instructions, branches, cache misses and hotspots on Linux |
| DPDK `testpmd` and `l3fwd_acl` | I/O ceiling and comparable classifier baselines |
| TRex STL or equivalent calibrated open-loop generator | End-to-end throughput, latency, loss, IMIX, and bursts |
| RFC 2544/3511/9411-derived profiles | Reproducible forwarding, filtering, connection/state, and security-device reporting |

Coverage percentage is diagnostic, not a release gate by itself. Release gates are behavior- and invariant-based.

## Documentation

- Canonical authored format: CommonMark/GitHub Markdown with Mermaid only where topology or ordering is material.
- Public Zig declarations: `///`; module contracts: `//!`.
- Static site: MkDocs-compatible Markdown. The generator is replaceable; directory and link conventions are canonical.
- Versioned public guides for the current minor line and latest stable line.
- ADRs for decisions, module design records for boundaries, TLA+ files for concurrent protocols, and machine-readable requirement/test mapping in YAML.

