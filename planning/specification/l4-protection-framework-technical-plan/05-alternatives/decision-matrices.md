# Alternatives and Decision Matrices

Scores are relative for this product (1 poor, 5 strong) and are not universal technology rankings. Weighted sums are secondary to hard constraints and benchmarks.

## First production packet I/O

| Criterion | Weight | DPDK | AF_XDP | AF_PACKET | netmap |
| --- | ---: | ---: | ---: | ---: | ---: |
| Peak small-packet performance/maturity | 5 | 5 | 4, hardware-dependent | 1 | 4 |
| NIC/PMD and queue control | 4 | 5 | 3 | 2 | 3 |
| Normal Linux stack coexistence | 4 | 2 | 5 | 5 | 3 |
| Operational/privilege simplicity | 3 | 2 | 3 | 4 | 3 |
| Matches batch/run-to-completion design | 5 | 5 | 5 | 3 | 5 |
| Stable LTS/deployment ecosystem | 4 | 5 | 4 (kernel LTS) | 5 | 3 |
| Zig integration surface | 3 | 3 | 3 | 4 | 3 |
| Result |  | **first production adapter** | **planned alternative** | diagnostic fallback only | defer |

DPDK wins the first high-throughput adapter because performance and queue/NUMA ownership are primary requirements. AF_XDP wins deployments that cannot detach the NIC or need normal Linux coexistence. This is why neither appears in public processor types.

## Dispatch

| Option | Packet cost | Flexibility | Type/capability checking | Code/compile cost | Decision |
| --- | --- | --- | --- | --- | --- |
| Comptime tuple/direct batch calls | Lowest expected | Rebuild processor set/order | Strong | Grows with variants | Baseline |
| Vtable once per processor/batch | Low | Startup/runtime selection | Medium | Stable | Fallback/hybrid |
| Vtable per packet | High/branchy | High | Medium | Stable | Rejected |
| Dynamic native plugin ABI | Batch-dependent | Highest | ABI/runtime only | Compatibility heavy | Deferred use-case gate |

## Generation reclamation

| Option | Reader cost | Writer/reclaim complexity | Stall behavior | Decision |
| --- | --- | --- | --- | --- |
| QSBR at batch boundary | One report/check per loop/batch | Moderate; requires online tracking | Stalled worker delays reclaim | Baseline |
| Atomic refcount per batch | Inc/dec shared cache line | Simple conceptually | No global grace wait after zero | Correctness fallback only |
| Hazard pointer | Publication per reader reference | Moderate/high | Stalled hazard delays reclaim | No advantage for one generation pointer |
| Stop-the-world swap | Large pause | Simple | Direct packet disruption | Rejected |
| Leak/timeout free | Low | Incorrect | Use-after-free or unbounded leak | Rejected |

## Policy execution

| Option | Semantic development | Performance potential | Security/operations | Decision |
| --- | --- | --- | --- | --- |
| Typed IR + bounded compact evaluator | Strong oracle/explanation | Medium-high with specialization | Simple, no executable memory | Baseline |
| AST interpreter | Simplest | Low | Simple | Reference only |
| DPDK ACL for entire language | Cannot express general Boolean/actions/availability | High for N-tuples | DPDK coupling | Eligible lowering only |
| JIT native code | Complex equivalence/debug | Highest potential | W^X and untrusted compiler surface | Triggered fallback |
| Wasm as standard language runtime | Adds VM semantics unrelated to policy | Medium | Sandbox/runtime dependency | Optional processor, not core |

## Metrics synchronization

| Option | Hot cost | Snapshot semantics | Complexity | Decision |
| --- | --- | --- | --- | --- |
| Relaxed atomic fixed cells | Atomic per update | Weak, race-free | Low | Baseline |
| Unsynchronized plain cells | Lowest | Language data race/undefined | Low but incorrect | Rejected |
| Mutex/global registry | High contention | Strong | Low | Rejected |
| Worker batch accumulation + atomic flush | Lower per packet | Weak | Medium | Profile-guided optimization |
| Double-buffer handshake | Very low update | Epoch/partial worker metadata | Higher | Fallback if atomic gate missed |

## Stateful ownership

| Option | Correctness assumption | Scaling | Complexity | Decision |
| --- | --- | --- | --- | --- |
| Per-worker table + flow affinity | Key stays on worker | Strong | Moderate | Baseline |
| Shared concurrent global table | None | Cache/lock/NUMA dependent | High | Explicit optional type later |
| Dedicated state owner stage | Routing preserves owner | Extra hops/rings | High | For processors heavy enough to justify |
| Approximate replicated meters | Controlled approximation | Strong | Moderate | Explicit approximate primitive |

