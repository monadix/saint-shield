# Testing Strategy

## Evidence ladder

| Layer | Finds | Runs |
| --- | --- | --- |
| Comptime/compile-fail | Contract and capability misuse | Every PR |
| Unit | Local boundary and error behavior | Every PR |
| Seeded property/differential | State-space and optimized/reference divergence | Every PR with short budget; nightly long |
| Model checking | Publication/reclamation/ring interleavings | On model change; bounded PR, expanded nightly |
| Deterministic integration | Whole semantic path and forced failures | Every PR |
| Virtual adapter | C ABI and adapter lifecycle without hardware | Every PR/main |
| Physical conformance | Driver/NIC/offload/ownership behavior | Main/nightly hardware |
| Performance | Regressions and comparison | Main micro; scheduled hardware |
| Soak/fault/security | Leaks, rare races, overload, parser abuse | Nightly/release |

No single layer substitutes for another. Fuzzing cannot prove QSBR safety; a TLA+ model cannot prove the code matches it; hardware throughput cannot validate ownership.

## Determinism

All randomized tests print seed, toolchain, target, and minimized operation trace. Time comes from a test clock. The synthetic adapter exposes a deterministic scheduler hook at meaningful boundaries, not arbitrary instruction-level scheduling. Failure injection counts allocations, queue operations, output slots, event slots, and update steps.

## Packet differential testing

For generated and fixture packets:

1. Framework parses fields/status.
2. An independent integration oracle (initially Scapy plus small RFC-derived fixtures) parses/recalculates.
3. Compare only semantics both claim, with special cases for fragments and malformed packets.
4. Apply structured/random valid mutation; serialize output.
5. Reparse independently and validate lengths/checksums/changed fields/unchanged bytes.

The test corpus includes minimum Ethernet IPv4/IPv6 TCP/UDP, VLAN, IPv4 options, IPv6 extensions, fragments, max MTU, truncation at every header byte, zero checksums where protocol permits, odd payload lengths, chained segments, and hardware offload metadata variants.

## Concurrency testing

Generation code carries explicit test hooks for:

- before/after publish store;
- before/after worker acquire;
- before/after first/last processor;
- before quiescent report;
- worker online/offline/unregister;
- before retire check and destruction.

Tests enumerate meaningful orderings for two workers/two generations and randomly stress larger cases. Generation-stamped output verifies coherence. Arena poison and delayed destruction catch stale reads. The TLA+ action names and code hooks share identifiers to make drift reviewable.

## Allocation and cleanup testing

Every constructor/preparation path is run with failure at allocation N for N from 1 through successful count. After each failure, allocator live bytes, adapter tokens, processor instances, event queues, retained leases, and generation records must return to the baseline. Repeat for prepare, instantiate, validate, source delivery, exporter creation, and shutdown.

## Policy testing

- Grammar golden tests and invalid diagnostics with spans/codes.
- Explicit three-valued truth tables for every Boolean operator.
- Generated well-typed ASTs evaluated by reference and compiled engines.
- Metamorphic properties: formatting/reparse and normalization preserve semantic hash/result; predicate inlining preserves result; set representation changes preserve membership.
- Generated ill-typed/cyclic/over-budget artifacts always fail preparation.
- Optimized DPDK/table lowering, if added, runs shadow differential tests before it can be default.

## State testing

A simple map and priority-queue expiry oracle consumes the same generated operations as the fixed table/wheel. Check occupancy, lookup, expiration, eviction outcome, meter result, and generation compatibility after every operation. Add adversarial collision keys, wraparound ticks, saturation arithmetic, idle time leaps, and full capacity.

## Sanitizing and fuzzing

M0 selects a coverage-guided engine compatible with Zig 0.16 and C adapters. Required targets: packet parser, policy lexer/parser/compiler, PCAP reader, mutation finalizer, event decoder, and any remote artifact framing. Each target has byte/time/memory limits and a deterministic reproducer. Run safe/instrumented Zig builds and DPDK's supported AddressSanitizer configuration where compatible. Sanitizer incompatibility is documented per adapter, not used to skip pure-core instrumentation.

## Test acceptance rule

A flaky test is a product defect. Quarantine is allowed only with an owner, issue, captured evidence, and expiry. Retrying until green cannot be the default. Hardware environmental failures are classified separately from DUT failures using generator/link health checks.

