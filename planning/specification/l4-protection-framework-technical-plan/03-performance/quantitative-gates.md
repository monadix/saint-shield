# Provisional Quantitative Gates

These are initial engineering gates, not measured claims. M0 freezes hardware/test noise; M3/M4 may revise a number once, by ADR, before it becomes a regression contract. A gate change must retain old/new raw data and explain why the prior number measured the wrong thing.

## Core gates

| ID | Gate | Comparison | Purpose |
| --- | --- | --- | --- |
| PERF-CORE-001 | 4 no-op processors retain ≥95% median packet rate | framework direct pipeline vs same framework zero-processor synthetic/replay, batches 32/64 | Prevent dispatch abstraction tax |
| PERF-CORE-002 | Framework zero-processor DPDK retains ≥90% zero-loss Mpps | minimal handwritten Zig-DPDK bridge, identical setup, 64-byte frames, one queue/core | Bound adapter/batch/disposition tax |
| PERF-CORE-003 | Framework zero-processor is reported against `testpmd`; no hard pass ratio initially | DPDK ceiling | Expose language/framework/harness gap without conflating bridge design |
| PERF-CORE-004 | No general allocation and zero payload copy in ordinary linear pass/redirect | instrumented counter/profile | Architectural requirement, not just speed |
| PERF-CORE-005 | Scaling efficiency ≥80% from 1 to min(4, available NIC queues/physical cores) before hardware saturation | N-core throughput / (N × one-core) | Detect sharing/NUMA bottleneck |

## Feature overhead gates

| ID | Gate | Comparison |
| --- | --- | --- |
| PERF-OBS-001 | Required core metric updates reduce zero-loss rate by ≤3% at batches 32/64 | metrics compiled out/test mode versus enabled |
| PERF-OBS-002 | Disabled event type overhead is statistically indistinguishable within test noise; enabled successful emit reduces rate by ≤8% for one event/packet | same pipeline |
| PERF-UPD-001 | Update-capable steady state with no updates reduces rate by ≤2% | startup-fixed generation runtime |
| PERF-UPD-002 | Publication does not create packet loss beyond baseline and p99.9 latency during activation stays within 10% of control window | identical offered rate ≤90% saturation |
| PERF-UPD-003 | An online non-stalled worker observes a publication no later than its next batch boundary | semantic/time-independent gate |
| PERF-POL-001 | Standard compiled policy retains ≥70% Mpps of a hand-coded native semantic equivalent for representative 10/100-rule profiles | same parser fields/actions |
| PERF-POL-002 | Optimized evaluator never loses semantic differential equivalence | reference evaluator; correctness gate overrides speed |
| PERF-STATE-001 | At 80% table occupancy, lookup/update p99 cycles are ≤2× median and work respects configured probe bound | same state primitive |
| PERF-STATE-002 | Full-capacity/exhaustion never causes unbounded latency or allocation | overload profile |

## Latency and batch gate interpretation

Absolute microseconds are hardware-specific, so the release gate is relative to the chosen baseline at the same offered load. Publish absolute values. A throughput improvement that increases p99.9 latency by more than 20% needs an explicit throughput/latency mode rather than becoming the universal default.

## Regression thresholds

- PR microbench: informational until at least 30 stable main samples exist.
- Main stable dedicated host: fail on >5% median regression with non-overlapping noise interval in two consecutive reruns.
- Release hardware: fail any gate or >3% regression in a primary profile unless an ADR accepts a user-visible trade-off.
- Never rerun selectively until a preferred sample appears; the controller records all attempts.

## If gates are missed

Profile before redesign. Attribute cost to receive/adaptation, parsing, selection, processor body, finalization, TX, metrics, or generation boundary. Apply the narrowest change and rerun the full correctness corpus. `05-alternatives/reversal-triggers.md` defines architectural switches.

