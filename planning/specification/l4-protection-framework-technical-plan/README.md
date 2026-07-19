# L4 Protection Framework: Technical Architecture and Delivery Plan

Status: proposed implementation baseline, 2026-07-18.

This archive turns the normative product specification in `source-requirements/` into an implementable technical plan. The source requirements remain authoritative. This plan makes concrete, reversible implementation choices and defines the evidence required to keep or replace them.

## Recommended baseline

- Zig 0.16.0, pinned exactly for the first development line.
- Linux on x86-64 and AArch64 as the first production platform family.
- An I/O-neutral core with three initial adapters, in this order: synthetic, DPDK 25.11 LTS, then AF_XDP.
- A run-to-completion worker per RX queue, pinned to a CPU, with NUMA-local memory and no shared mutable packet state by default.
- Compile-time pipeline composition and capability checking; no per-packet universal vtable.
- Immutable prepared generations published with release/acquire atomics and reclaimed with batch-boundary quiescent-state-based reclamation (QSBR).
- Bounded worker-local metrics and one SPSC event ring per worker; exporters and consumers run outside packet workers.
- A hand-written policy parser, typed intermediate representation, bounded scalar evaluator, specialized set representations, and a later optional classification lowering.
- Fixed-capacity worker-local state tables and a hierarchical timing wheel in the stateful phase.
- Markdown design documentation, Zig doc comments for public symbols, ADRs for decisions, invariant/safety comments for low-level code, and TLA+ models for publication/reclamation protocols.

The core deliberately does **not** depend on DPDK, libxdp, Prometheus, OpenTelemetry, a policy language, or a dynamic plugin loader. These are separately linked modules. Logical packet, update, and observability responsibilities do not imply separate processes.

## Reading order

1. `00-overview/executive-summary.md`
2. `00-overview/selected-stack.md`
3. `01-architecture/architecture.md`
4. `01-architecture/invariants.md`
5. the relevant file in `01-architecture/modules/`
6. `02-implementation/roadmap.md`
7. `02-implementation/testing-strategy.md`
8. `03-performance/methodology.md`
9. `05-alternatives/reversal-triggers.md`

## Archive map

| Path | Purpose |
| --- | --- |
| `00-overview/` | Chosen stack, scope, topology, and repository layout |
| `01-architecture/` | Cross-cutting design and recursive module specifications |
| `02-implementation/` | Ordered implementation, test gates, CI, and release strategy |
| `03-performance/` | Benchmark methodology, comparison baselines, and quantitative gates |
| `04-documentation/` | Internal and external documentation standards and templates |
| `05-alternatives/` | Rejected options, viable fallbacks, and objective reversal triggers |
| `06-research/` | Primary-source notes, assumptions, and open questions |
| `source-requirements/` | Unmodified supplied normative specification |

## Decision status vocabulary

- **Accepted baseline**: implement unless its reversal trigger fires.
- **Provisional**: build a spike and decide at the named gate.
- **Deferred**: public boundaries must allow it, but no implementation work is authorized yet.
- **Rejected for now**: do not add without a new use case and ADR.

## Definition of implementation complete

A milestone is complete only when its code, tests, requirement links, user documentation, benchmark delta, and cleanup/failure behavior are all present. A fast happy-path implementation without the corresponding overload and retirement tests is incomplete.

