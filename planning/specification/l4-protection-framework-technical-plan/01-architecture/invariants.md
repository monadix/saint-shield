# System Invariants

These are code-review and test obligations, not aspirations. Each invariant receives a stable ID used in comments, tests, TLA+ models, and incidents.

| ID | Invariant | Primary enforcement |
| --- | --- | --- |
| INV-PKT-001 | Every received storage token has exactly one final completion or live retention lease | Ownership state machine, synthetic backend, shutdown assertions |
| INV-PKT-002 | Packet and batch views do not outlive their processing call | Scoped types, debug cookies, unsafe-boundary review |
| INV-PKT-003 | Batch order equals receive order until an explicit routing/reorder operation | Conformance tests |
| INV-PKT-004 | A terminal packet is absent from later processor active selections | Bitset/disposition tests |
| INV-PKT-005 | Finalized output headers/length/checksum metadata are internally consistent | Differential packet oracle |
| INV-GEN-001 | One batch refers to one complete generation | Single acquire at boundary, TLA+ and stress tests |
| INV-GEN-002 | Published generation data is immutable | API/type ownership and review |
| INV-GEN-003 | No generation is destroyed while a worker can reference it | QSBR model and forced-interleaving tests |
| INV-GEN-004 | Candidate failure cannot alter active behavior | Failure-injection tests |
| INV-GEN-005 | Rollback is a new coherent activation | Update conformance tests |
| INV-RES-001 | Hot-path allocation is impossible or uses a declared bounded pool | Capability types, allocator fault injection |
| INV-RES-002 | Preparation and worker memory never silently exceed accepted budgets | Budget allocator tests |
| INV-OBS-001 | Exporter/consumer delay cannot block packet workers | Thread topology and blocked-consumer test |
| INV-OBS-002 | Metric cardinality is bounded before activation | Registry validation |
| INV-OBS-003 | Event overflow follows declared policy and increments a bounded counter | Ring saturation test |
| INV-POL-001 | Optimized policy evaluation is semantically equal to reference evaluation | Differential/property tests |
| INV-POL-002 | Unavailable fields cannot become a match merely through negation | Truth-table tests |
| INV-STATE-001 | State capacity and exhaustion behavior are fixed/declared | Fixed table and saturation tests |
| INV-STATE-002 | New configuration never silently reinterprets incompatible state | Generation compatibility validation |

## Comment forms

Use only when the statement is non-obvious and testable:

```zig
// INVARIANT(INV-GEN-003): `old` remains in retire_queue until all online
// workers have reported an epoch greater than old.retire_epoch.

// SAFETY: `token` was produced by this adapter and remains worker-owned;
// alignment and length were validated when the RX descriptor was adapted.

// PERF: one relaxed RMW per batch, not per packet. Benchmark BENCH-OBS-003
// guards regression.
```

Every `SAFETY` comment states provenance, lifetime, alignment/bounds, aliasing, and concurrent-access facts relevant to the unsafe operation. Restating the code is not documentation.

