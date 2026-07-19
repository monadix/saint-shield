# Assumptions and Open Questions

The source requirements deliberately leave these choices open. The architecture either contains them behind a boundary or schedules a decision gate.

## Baseline assumptions

| Assumption | Consequence if false | Resolution |
| --- | --- | --- |
| First production targets are Linux x86-64/AArch64 | DPDK/AF_XDP stack may not apply | Core remains adapter-neutral; new OS gets adapter/platform ADR |
| Ethernet is the initial link layer | Packet parser/origin needs extension | Keep packet bytes and parser capabilities modular |
| Typical MTU packets are linear on primary path | Multi-segment performance/support moves earlier | Segment-aware API already present; adapter capability rejects unsupported cases |
| Processor set/order changes less often than config | Static pipeline requires rebuild too often | Hybrid batch-vtable trigger |
| Update activation can be serialized | Multi-writer protocol needed | Serialize in app or add compare/exchange session ADR |
| Worker-local state can rely on steering for strict flows | Shared/owner state architecture needed | Explicit M10 affinity gate |
| Native Zig processors are trusted | Need sandbox/process isolation | Use optional Wasm/eBPF/process module; core capability model is not security isolation |

## Decisions needed before physical M4 benchmarking

- Target NIC models, link rates, drivers/firmware, and available queues.
- Minimum packet sizes/MTU/jumbo/encapsulation requirements.
- Required outputs/topology: bridge, router, redirect, hairpin, host stack handoff.
- Whether checksum/RSS/timestamp offloads are acceptable and required.
- Generator hardware and whether it can exceed DUT capacity.
- CPU/NUMA/core budget and whether SMT/turbo/power constraints match production.

Without these, the plan can measure framework tax but cannot define an absolute capacity target.

## Application policy choices, not framework defaults

- Fail-open, fail-closed, default output/drop, and worker-stop behavior.
- Maximum batch and latency/idle mode.
- Retained-generation count/bytes and stalled-worker response.
- Event sampling/overflow and consumer isolation.
- State capacity, affinity key, exhaustion/eviction, update transition.
- Artifact revision ordering, authorization/signing, grouping, and audit.

The framework provides explicit options and safe documented examples; it must not infer one choice from another component.

## M0/M1 technical questions

1. Which coverage-guided fuzz engine integrates cleanly with Zig 0.16 and the DPDK C boundary? Decide by working crash/reproducer, not popularity.
2. Can required DPDK mbuf/ring macros import/inline safely, or is a batch normalization shim faster/safer? Resolve EXP-003.
3. What initial maximum batch range balances compile-time bitsets, DPDK bursts, and latency? Resolve EXP-001/012; public API stays parametric.
4. Which precise packet editor operations are supportable across both DPDK and AF_XDP without copy? Start narrow and capability-probed.
5. Does ReleaseSafe meet provisional performance gates? It remains default until measured otherwise.

## Policy-language questions for M9

- Exact textual syntax and module/import bundling.
- Whether rules can explicitly continue into later rules and/or later processors; define one unambiguous model.
- Field namespace/versioning and conflict policy for extensions.
- Stable semantic hash canonicalization across compiler patch releases.
- Maximum instruction/action model and diagnostic compatibility promise.

These should be resolved with language examples and executable truth tables before parser implementation. Internal grammar is not chosen solely for parser convenience.

## Deferred use-case questions

- Is a dynamic native ABI genuinely required, or can applications rebuild/static-link?
- Which optional executor provides a real user outcome: table, BPF, or Wasm?
- Is remote source transport part of a separate application/controller project?
- Is strict global rate limiting required, and what consistency/latency cost is acceptable?
- Which observability backends besides Prometheus/binary events are actually used?

Do not answer these by implementing all options. Capture the first concrete deployment and make the smallest extension that proves the existing boundary.
