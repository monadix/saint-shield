# Required Experiments and Decision Points

| Experiment | Variants | Decision produced |
| --- | --- | --- |
| EXP-001 selection | `u64`, fixed word array, per-slot bool reference | Initial max batch and selection implementation |
| EXP-002 dispatch | direct tuple, batch vtable, per-packet vtable negative control | Static versus hybrid dispatch |
| EXP-003 packet slot | direct adapter fields, normalized slot, batch-normalized fields | Adapter translation layout |
| EXP-004 metrics | relaxed atomic cells, batch-local accumulation + atomic flush, double-buffer handshake | Metric update scheme |
| EXP-005 generation read | once per batch, cached with periodic check, per-batch refcount fallback | Publication overhead/reclamation choice |
| EXP-006 set lookup | flat/sorted/hash/radix/dense port bitset | Preparation representation crossovers |
| EXP-007 policy | reference AST, compact blocks, field pre-extraction, batch classify | Optimization order and gate |
| EXP-008 state table | linear/Robin Hood/backshift/tombstone variants | Fixed table behavior under occupancy/churn |
| EXP-009 expiry | timing wheel levels/tick and min-heap reference | Expiry work/memory parameters |
| EXP-010 DPDK/AF_XDP | same NIC, queues, traffic, CPU budget | Adapter recommendation per deployment |
| EXP-011 safe/fast | ReleaseSafe and ReleaseFast | Production default and unsafe optimization budget |
| EXP-012 batch/latency | sizes 1..64 and optional coalescing | Default max burst and explicit latency mode |

## Experiment rules

Each experiment starts with a written hypothesis, semantic equivalence statement, independent variables, fixed conditions, metrics, and decision threshold. Keep negative results; they prevent repeated speculation. Microbench winners must survive replay and end-to-end tests because cache-isolated structures often lose in the full loop.

Do not merge two implementations behind a permanent abstraction merely because both were benchmarked. Keep the winner and a design note unless deployments truly need both. This limits future maintenance and code paths.

## Re-benchmark triggers

- Zig compiler or optimization backend update.
- DPDK/libxdp/kernel/NIC driver/firmware change.
- Packet slot, selection, parser, generation boundary, metrics cell, or event ring layout change.
- Public processor contract/capability change.
- New CPU architecture or material microarchitecture.
- New offload/multi-segment support.
- Policy IR/evaluator/set representation change.
- State hash/expiry change.

