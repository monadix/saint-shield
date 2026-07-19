# Risk Register

| Risk | Likelihood/impact | Early evidence | Mitigation/fallback | Gate |
| --- | --- | --- | --- | --- |
| Zig compiler/API churn | Medium/high | Stable upgrade compile failures | Exact pin, downstream corpus, planned migrations | M0/release |
| DPDK C macro/layout integration tax | Medium/high | Per-packet calls or slot conversion hotspot | Inline compatibility header, batch adapter, ABI assertions | M0/M4 |
| Public packet API accidentally assumes contiguous buffers | Medium/high | Multi-segment spike requires break | Segment-aware view from M1; linear fast path | M1/M11 |
| QSBR online/offline race | Medium/critical | Model counterexample/stress stale read | TLA+ first, refcount fallback | M6 |
| Stalled worker retains too many generations | High/medium | Retire bytes/grace age | Hard retained budget, reject/coalesce updates, worker policy | M6 |
| Policy language grows into general programming language | Medium/high | Unbounded functions/side effects | Pure typed expressions, bounded actions, scope review | M9 |
| Policy evaluator too slow | Medium/high | PERF-POL-001 miss | Ordered optimization/lowering triggers | M9 |
| Metrics cardinality/resource attack | High/high | Artifact creates excessive cells | Finite domains/cell budget at preparation | M5/M8 |
| Event consumer loss surprises users | High/medium | Overflow under outage | Explicit policy/counter, per-consumer isolation, docs | M8 |
| Flow affinity invalidates state semantics | High/high | Same key reaches multiple workers | Validate steering/hash, document or choose shared/owner model | M10 |
| Benchmark is generator/hardware limited | Medium/high | Ceiling equals generator/preflight fails | 120% headroom, testpmd ceiling, isolated topology | M0/M4 |
| ReleaseFast hides memory/overflow bugs | Medium/critical | Safe/fast differential | ReleaseSafe default, sanitizer/fuzz, explicit unsafe audit | All/M12 |
| Optional modules couple core dependencies | Medium/medium | core imports DPDK/OTel/VM | build dependency audit and separate modules | Every PR |
| Scope expands into fleet control plane | Medium/high | auth/storage/consensus proposed | Reject to application/external systems per product definition | Architecture review |

Risks are reviewed at each milestone. Closing a risk requires evidence, not just completed code.

