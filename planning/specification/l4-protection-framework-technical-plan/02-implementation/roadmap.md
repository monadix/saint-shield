# Step-by-Step Implementation Roadmap

Milestones are ordered by dependency and evidence, not calendar promises. Do not begin the main body of a milestone until its predecessor exit gate passes. Small research spikes for later risks may run earlier, but spike code does not silently become production code.

## M0 — Toolchain, risk spikes, and testbed contract

**Build:** Pin Zig 0.16.0; create `build.zig`, package modules, formatting/lint/test/doc commands; establish exact DPDK 25.11.2 build; make tiny Zig programs receive a DPDK virtual burst and import required `rte_mbuf` fields; make an AF_XDP/libxdp setup spike on one supported NIC; evaluate the coverage-guided fuzz integration; define benchmark result JSON and environment manifest.

**Tests/evidence:** Clean builds on Linux x86-64 and AArch64; Debug/ReleaseSafe/ReleaseFast smoke; cross-compile library; C ABI size/offset assertions; DPDK virtual PMD token round trip; exact fuzz crash/reproducer workflow; calibrated generator can exceed planned DUT load without DUT.

**Exit:** D-012 fuzz engine decided by ADR; DPDK shim has no required per-packet function-call boundary; testbed inventory records NIC, firmware, CPU, NUMA, kernel, BIOS, generator, cabling.

**Alternative:** If Zig 0.16 has a blocking regression, pin the newest stable patch/previous stable only with a minimized reproducer and migration ADR. If DPDK imported inline access cannot meet the boundary, generate a batch descriptor adapter and benchmark its copy cost before proceeding.

## M1 — Foundation, packet ownership, and views

**Build:** Stable IDs, bounded errors, budgets, monotonic/deterministic time, adapter token state, packet segments, `PacketView`, `InputOrigin`, receive-order slots, debug lifetime cookie, pure-Zig PCAP subset, and the synthetic input/output queues.

**Tests/evidence:** All read ranges and segment boundaries; checked arithmetic; malformed/truncated descriptors; token state transitions; double/missing completion; capture parser fuzz seed corpus; allocation failure for every constructor; zero payload copy counter.

**Exit:** INV-PKT-001/002 hold in exhaustive small-state synthetic tests; packet bytes can traverse synthetic input/output unchanged for sizes 0 through configured maximum (zero-size rejected where adapter forbids it).

## M2 — Parsing, selection, dispositions, and mutation

**Build:** Active bitset, disposition writer, output grouping, lazy L2/L3/L4 parser, fragment semantics, structured editor, raw-editor capability, mutation journal, software checksum/length finalizer, retention lease API.

**Tests/evidence:** Random selection operations versus set oracle; every header truncation offset; IPv4 options/fragment and IPv6 extensions/fragment; all disposition mixes; Scapy differential checksum and decoded-field comparison; head/tailroom failure atomicity; lease exhaustion and shutdown leak.

**Benchmark:** Parser and no-op disposition cycles/packet for batch sizes 1/4/8/16/32/64; establish non-regression baseline, not a competitive gate yet.

**Exit:** AC-001/002/010 and packet-related invariants pass. No corrupted packet is transmitted after an injected mutation failure.

**Alternative:** If one-`u64` selection becomes a code constraint, switch to comptime fixed word array before public release. Do not expose the internal bitset.

## M3 — Native processor contract and static pipeline

**Build:** Descriptor/capability schema, comptime contract validation, prepared/worker lifecycle, tuple pipeline, stage metadata layout, resource estimates, reverse cleanup, error/default policy, public processor test harness.

**Tests/evidence:** Compile-fail suite for every invalid declaration; three-stage ordering; mixed dispositions; partial construction cleanup under allocation faults; capability denial; random tiny pipelines versus reference runner; `errdefer` cleanup accounting.

**Benchmark:** No-op pipelines with 0/1/2/4/8 processors. Compare direct generated calls with a hand-written monolith and a batch-vtable spike.

**Exit:** Framework tax for a 4-stage no-op pipeline is within the provisional gate in `03-performance/quantitative-gates.md`; AC-003/012 pass; one example application composes custom native processors.

**Alternative:** If code-size/compile-time growth is superlinear or instruction-cache cost is material, use direct calls for small pipelines and one batch-level vtable for declared dynamic groups. Never fall back to per-packet virtual dispatch without new evidence.

## M4 — DPDK adapter and physical ownership loop

**Build:** EAL/port/queue options, capability probe, NUMA-local pools, burst RX/TX, partial TX handling, mbuf segment adapter, checksum/RSS metadata, output queues, link/error stats, orderly shutdown, DPDK virtual and hardware fixtures.

**Tests/evidence:** Virtual/ring PMD conformance; physical two-port forward/drop/redirect; partial TX at every count; mempool exhaustion; link flap; invalid/multi-segment policy; hardware/software checksum modes; repeated start/stop and leak reconciliation; adapter stats reconciliation.

**Benchmark:** Same host/NIC/config: DPDK `testpmd` forwarding ceiling, minimal handwritten Zig-DPDK bridge, framework zero-processor bridge, one native ACL-like processor. Sizes 64..1518 and batch matrix.

**Exit:** Zero-processor framework reaches the adapter-retention gate; no ordinary linear payload copy; token accounting is exact over a one-hour sustained run; DPDK version/driver/firmware documented.

**Alternative:** If adapter translation tax exceeds the gate, profile and change internal packet slots or inline shim. If DPDK operational/device constraints fail the target environment, advance M11 AF_XDP but keep the core milestones unchanged.

## M5 — Worker runtime and core metrics (Product Phase 1)

**Build:** CPU/queue topology, run-to-completion loop, batch-boundary generation fixed at startup, output flush policy, worker progress, core worker-local metrics, snapshot aggregation, startup assembly validation, graceful/fatal shutdown.

**Tests/evidence:** Multiple workers/queues synthetic and physical; partial batches proceed immediately; output congestion/failure policies; worker crash/stall simulation; snapshot under traffic; startup capability rejection; shutdown while outputs complete.

**Benchmark:** Scale 1..N physical cores/queues; NUMA-local versus intentionally remote; batch/latency curve; metrics disabled/enabled; ReleaseSafe versus ReleaseFast.

**Exit:** All Phase-1 source deliverables and AC-001..003/010/012 pass; example static firewall works on synthetic and DPDK; core API documentation published.

## M6 — Formalized generation update and QSBR

**Build first:** TLA+/PlusCal generation/QSBR model with safety invariants and worker online/offline/rollback/stall states. Review model and memory-order mapping.

**Then build:** Artifact/session objects, budgeted generation arena, serialized activation, atomic publication, worker batch-boundary acquire, adoption status, retirement FIFO, QSBR, retained-generation limits, deterministic forced-interleaving hooks.

**Tests/evidence:** TLC exhaustive bounded model; code trace scenarios corresponding to every model action; activate during every pipeline point; worker stall/offline/unregister; allocation/instantiate failure at every step; repeated 10k synthetic updates; leak and use-after-retire detectors; candidate/base conflict.

**Benchmark:** Publication/adoption/retirement distributions under load; packets/sec and tail latency during rapid update; retained memory under stalled worker.

**Exit:** AC-004..006/011/012; INV-GEN-001..005; no throughput stall attributable to preparation; no old-generation destruction before grace.

**Alternative:** If custom QSBR proof/implementation remains uncertain, use the same public contract with DPDK QSBR in the DPDK application as a temporary reference and keep synthetic differential tests. A refcount per batch is an emergency correctness fallback and must meet its performance gate before acceptance.

## M7 — Sources, rollback, and state transition hooks

**Build:** Direct/static sources, source contract/cancellation, revision-policy plug-in, application grouping, rollback as new activation, prepared-part reuse, processor state transition declaration, watched-file source only after atomic file-read semantics are specified.

**Tests/evidence:** Direct/source artifact equivalence; duplicate/stale/out-of-order policies; stop during I/O; watched rename/truncate/write cases; retained target missing/incompatible; reuse lifetime; every state transition mode with dummy processor.

**Exit:** AC-007/011 plus source conformance. Remote source remains out of core and no protocol is implied.

## M8 — Events, exporters, and full local observability (Product Phase 2)

**Build first:** SPSC ring model or exhaustive small ring state test. **Then build:** schema registry, per-worker event rings, policies, drain/fanout, binary and debug JSONL consumers, Prometheus scrape exporter, update/resource diagnostics.

**Tests/evidence:** Ring wrap/full/empty concurrent stress; blocked/failing consumers and exporter; sampling/rate limit determinism; cardinality-budget rejection; scrape golden tests; update failure diagnostics; long consumer outage with bounded memory.

**Benchmark:** Metric increments, snapshot, disabled/enabled event, full ring, drain throughput; dataplane throughput and latency with every mode.

**Exit:** AC-008/009; all Section-6 required metrics; consumers can block indefinitely without worker blocking; overflow is observable.

## M9 — Standard policy language (Product Phase 3)

**Build in sub-increments:** grammar/formatter → parser/spans/limits → resolver/type checker → availability/reference evaluator → sets/predicates/ACLs/rules/actions → compact evaluator → explanation/shadow comparison → specialization.

**Tests/evidence:** Each sub-increment has golden and generated tests. Fuzz parser and artifact decoder continuously. Differential reference/compact evaluation over generated typed policies and packets is the main correctness gate. Run all AC-PL scenarios; test semantic hash and source diagnostic stability.

**Benchmark:** Rule counts 1/10/100/1k/10k where valid; hit positions first/middle/last/miss; IPv4/IPv6; small/large prefix and port sets; native hand-coded equivalent; DPDK `l3fwd_acl` only for eligible N-tuple comparison.

**Exit:** All mandatory PL requirements and AC-PL-001..008; compiled evaluator meets policy gate or a documented optimization experiment is selected; malformed artifacts remain bounded.

**Alternative:** If compact evaluation misses the gate, profile in order: field extraction, set lookup, rule branching, action dispatch. Add common-subexpression extraction/vectorized classification before considering DPDK ACL lowering. JIT requires a separate security ADR.

## M10 — Bounded state and protection primitives (Product Phase 4)

**Build in sub-increments:** fixed table/reference differential → expiry wheel → token bucket/GCRA → flow-key/RSS validation → update transition modes → reusable state processor examples.

**Tests/evidence:** Random map and timer sequences; capacity/probe/expiry boundaries; adversarial hashes with secret seed; deterministic time; every exhaustion policy; generation transitions; flow-affinity violation; one-hour high-churn soak.

**Benchmark:** lookup/update/expire at occupancy 50/80/95/100%; active-key distributions; 1..N cores; state fits/exceeds caches; strict worker-local versus an experimental shared shard.

**Exit:** Phase-4 requirements; bounded work under full table and expiry debt; no universal flow model leaks into core.

## M11 — AF_XDP and optional integration proof (Product Phase 5)

**Build:** AF_XDP adapter with XDP redirect program, copy/zero-copy detection, need-wakeup, UMEM ownership, driver/queue diagnostics, same conformance interface. Add one small optional executor/source/exporter only if it proves a public extension boundary; do not implement all candidate modules for completeness.

**Tests/evidence:** Kernels 6.12/6.18, generic/driver/zero-copy modes where supported; XSKMAP queue mismatch; FILL starvation; completion lag; copy fallback visibility; multi-buffer explicit rejection; same hardware packet corpus as DPDK.

**Benchmark:** AF_XDP versus DPDK on identical NIC/CPU, including CPU efficiency, latency, packet sizes, steering distributions, and operational setup. Do not combine results from different modes.

**Exit:** Adapter-specific support matrix and recommendation; core API unchanged or any discovered flaw fixed before stable 1.0.

## M12 — Production hardening and 1.0 candidate (Product Phase 6)

**Build/evidence:** Compatibility policy; SBOM/reproducible build; all failure injection; update-under-load; 24/72-hour soaks; fuzz campaign and corpus minimization; independent packet/update/policy security review; resource leak proof; driver/kernel/NIC matrix; upgrade/rollback rehearsal; public benchmark report and raw results; unsafe-boundary audit.

**Exit:** Every mandatory requirement maps to a passing test or reviewed manual evidence; all quantitative gates pass or have an explicitly accepted, user-visible limitation; no unresolved critical/high security issue; documentation builds and examples execute from a clean environment.

