# Saint Shield Implementation Progress

Last updated: 2026-07-19

This is the canonical implementation ledger. It reports progress and evidence;
it does not override requirements or technical decisions. Update it only when
the corresponding implementation or verification evidence exists.

## Status rules

- **Not started:** no production implementation work has begun.
- **In progress:** production implementation or verification work has begun for
  the active milestone.
- **Blocked:** a specific unmet dependency or failed gate prevents meaningful
  progress; record evidence and the authority needed to unblock it.
- **Complete:** every archived exit condition and the local additions in
  `LOCAL_EXECUTION_PLAN.md` pass, with commands/results linked below.

Never mark a milestone complete because code exists or happy-path tests pass.
Never skip a predecessor gate. Later risk spikes must be labelled as spikes and
do not change milestone status.

## Milestone ledger

| Milestone | Status | Started | Completed | Evidence summary |
| --- | --- | --- | --- | --- |
| M0-V - virtual toolchain and risk foundation | In progress | 2026-07-19 | - | Expected gate: complete reproducible virtual foundation exit in `LOCAL_EXECUTION_PLAN.md` and archived M0 virtual evidence. |
| M0-H - physical testbed contract | Not started | - | - | Deferred until hardware exists. |
| M1 - foundation, ownership, and views | Not started | - | - | - |
| M2 - parsing, dispositions, and mutation | Not started | - | - | - |
| M3 - native processor contract and static pipeline | Not started | - | - | - |
| M4 - DPDK adapter and physical ownership loop | Not started | - | - | Requires M0-H. |
| M5 - worker runtime and core metrics | Not started | - | - | - |
| M6 - generation update and QSBR | Not started | - | - | - |
| M7 - sources, rollback, and state transitions | Not started | - | - | - |
| M8 - events, exporters, and local observability | Not started | - | - | - |
| M9 - standard policy language | Not started | - | - | - |
| M10 - bounded state and protection primitives | Not started | - | - | - |
| M11 - AF_XDP and optional integration proof | Not started | - | - | - |
| M12 - production hardening and 1.0 candidate | Not started | - | - | - |

## Current target: M0-V through M3

### M0-V checklist

- [ ] `flake.nix` and locked inputs provide the complete development environment.
- [ ] Zig 0.16.0 and DPDK 25.11.2 sources/hashes are pinned.
- [ ] `build.zig`/`build.zig.zon` and proposed module layout exist.
- [ ] Formatting, Debug, ReleaseSafe, ReleaseFast, test, docs, benchmark, fuzz,
      and CI entry points are defined.
- [ ] Linux x86-64 clean builds pass in all build modes.
- [ ] Linux AArch64 public library cross-compiles.
- [ ] Required DPDK C ABI size/offset assertions pass.
- [ ] DPDK virtual-PMD burst/token round trip passes with no huge pages.
- [ ] Coverage-guided fuzz engine is selected by D-012 ADR with a working
      crash/reproducer/corpus workflow.
- [ ] Benchmark result and environment manifest schemas validate examples.
- [ ] Dependency and license integrity evidence is recorded.
- [ ] M0-V documentation and clean-environment commands pass.

Evidence:

- Commands: _pending_
- Test reports: _pending_
- ADRs: _pending_
- Benchmarks/schemas: _pending_
- Known limitations: _pending_

### M1 checklist

- [ ] Stable identifiers, bounded errors, budgets, and testable time exist.
- [ ] Adapter-token state machine and exact completion accounting exist.
- [ ] Segment-aware `PacketView`, origin, slots, and lifetime checks exist.
- [ ] Synthetic queues provide deterministic failure/backpressure behavior.
- [ ] Bounded PCAP support and fuzz corpus exist.
- [ ] All ranges, truncations, malformed descriptors, and allocation failures
      are tested.
- [ ] Sizes through configured maximum traverse unchanged without payload copy.
- [ ] INV-PKT-001 and INV-PKT-002 pass with documented evidence.

Evidence:

- Commands: _pending_
- Requirement/test mapping: _pending_
- Fuzz/property artifacts: _pending_
- Benchmark delta: _pending_
- Known limitations: _pending_

### M2 checklist

- [ ] Active selection, dispositions, and output grouping exist.
- [ ] Lazy Ethernet/IPv4/IPv6/TCP/UDP parsing and fragment semantics exist.
- [ ] Structured/raw mutation capability boundary and journal exist.
- [ ] Length/checksum finalization is failure-atomic.
- [ ] Retention leases are bounded and leak-tested.
- [ ] Selection property tests and all header-byte truncations pass.
- [ ] Scapy differential packet/checksum tests pass.
- [ ] Batch-size parser/no-op baselines are recorded.
- [ ] AC-001, AC-002, AC-010, and packet invariants pass.

Evidence:

- Commands: _pending_
- Requirement/test mapping: _pending_
- Differential/fuzz artifacts: _pending_
- Benchmark delta: _pending_
- Known limitations: _pending_

### M3 checklist

- [ ] Descriptor/capability schemas and comptime validation exist.
- [ ] Prepared/worker lifecycle and reverse cleanup exist.
- [ ] Tuple pipeline performs one direct call per processor per batch.
- [ ] Stage metadata, resource estimates, and error/default policies exist.
- [ ] Public processor test harness and example application exist.
- [ ] Compile-fail suite covers every invalid declaration category.
- [ ] Ordering, mixed dispositions, allocation faults, capability denial, and
      tiny reference-pipeline comparisons pass.
- [ ] 0/1/2/4/8 processor benchmarks and negative-control spikes are recorded.
- [ ] PERF-CORE-001, AC-003, and AC-012 pass.

Evidence:

- Commands: _pending_
- Requirement/test mapping: _pending_
- Compile-fail/property artifacts: _pending_
- Benchmark report: _pending_
- Known limitations: _pending_

## Active blockers

None. M0-H and later physical work are deferred dependencies, not blockers for
M0-V through M3.

## Decision and exception log

| Date | Milestone | Decision/exception | Evidence or ADR |
| --- | --- | --- | --- |
| 2026-07-19 | M0 | Split M0-V from M0-H; M0-V unlocks M1-M3 only. | `LOCAL_EXECUTION_PLAN.md` L-001 |
| 2026-07-19 | Release | x86-64 production first; AArch64 build/semantic support until hardware certification. | `LOCAL_EXECUTION_PLAN.md` L-002 |

## Progress update template

For each material update, append a row and update the relevant checklist and
ledger status. Keep command output in test/benchmark artifacts, not pasted here.

| Date | Milestone | Change | Verification | Next action |
| --- | --- | --- | --- | --- |
| 2026-07-19 | Planning | Initialized verified specification, local execution plan, and progress ledger. | Both archive manifests passed `sha256sum -c`. | Start M0-V. |
| 2026-07-19 | M0-V | Began reproducible virtual foundation implementation. | Expected gate: three-mode x86 build/test, AArch64 library cross-compile, exact dependency integrity, DPDK ABI and no-huge virtual token round trip, deterministic fuzz workflow, and schema/docs validation. | Create and verify the M0-V scaffold. |
