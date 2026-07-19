# Decision Register

| ID | Status | Decision | Detailed location |
| --- | --- | --- | --- |
| D-001 | Accepted baseline | Pin Zig 0.16.0, never master, for the first line | `00-overview/selected-stack.md` |
| D-002 | Accepted baseline | Core is I/O-neutral; synthetic first, DPDK first production | `01-architecture/modules/io-backends.md` |
| D-003 | Accepted baseline | Static typed pipeline with one direct call per processor per batch | `01-architecture/modules/pipeline-runtime.md` |
| D-004 | Accepted baseline | One worker per RX queue and run-to-completion | `01-architecture/hot-path.md` |
| D-005 | Accepted baseline | Batch-boundary QSBR generation publication/reclamation | `01-architecture/concurrency-and-updates.md` |
| D-006 | Accepted baseline | Opaque packet storage and segment-aware access | `01-architecture/modules/core-packet.md` |
| D-007 | Accepted baseline | Structured mutation capability; raw mutation is trusted/explicit | `01-architecture/memory-and-ownership.md` |
| D-008 | Accepted baseline | Fixed worker metrics and bounded SPSC events | `01-architecture/modules/observability.md` |
| D-009 | Accepted baseline | Typed policy IR and reference-first evaluator; no initial JIT | `01-architecture/modules/policy.md` |
| D-010 | Accepted baseline | Worker-local fixed-capacity state, no universal flow model | `01-architecture/modules/state.md` |
| D-011 | Accepted baseline | Markdown + Zig docs + ADR/module/invariant records | `04-documentation/` |
| D-012 | Provisional | Exact coverage-guided fuzz engine | `02-implementation/roadmap.md` M0 |
| D-013 | Deferred | AF_XDP becomes co-equal supported production adapter | `05-alternatives/reversal-triggers.md` |
| D-014 | Deferred | Dynamic native plugin ABI | `05-alternatives/reversal-triggers.md` |
| D-015 | Rejected for now | Separate management binary as a framework requirement | `01-architecture/architecture.md` |
| D-016 | Rejected for now | Mandatory Wasm/eBPF/table executor in core | `01-architecture/extension-model.md` |

Each change to an accepted baseline requires an ADR containing benchmark/correctness evidence and a migration plan. A decision whose documented reversal trigger fires is expected to change; preserving it for consistency would be a defect.

