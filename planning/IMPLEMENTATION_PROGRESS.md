# Saint Shield Implementation Progress

Last updated: 2026-08-11

This is the canonical implementation ledger. It reports progress and evidence;
it does not override requirements or technical decisions. Update it only when
the corresponding implementation or verification evidence exists.

Keep this ledger compact: record milestone starts, blocked or reopened states,
material gate changes, and final acceptance. Store individual findings,
remediation chronology, and command output in the applicable milestone or
process evidence closure register.

Standalone process maintenance does not update the milestone ledger unless it
changes milestone status, gate or evidence facts, or a recorded
decision/exception.

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
| M0-V - virtual toolchain and risk foundation | Complete | 2026-07-19 | 2026-07-19 | Full isolated-cache CI and standalone all-system flake evaluation pass; exact evidence is recorded in `evidence/m0-v/VERIFICATION.md`. |
| M0-H - physical testbed contract | Not started | - | - | Deferred until hardware exists. |
| M1 - foundation, ownership, and views | Complete | 2026-07-19 | 2026-07-29 | Independent review closure is recorded in [evidence/m1/REVIEW.md](../evidence/m1/REVIEW.md); the gate verifier reproduced both manifests, cumulative CI, and diff checks as recorded in `evidence/m1/VERIFICATION.md`. |
| M2 - parsing, dispositions, and mutation | Complete | 2026-08-02 | 2026-08-11 | All sixteen findings are closed. The mandatory post-High review and independent final exact-tree cumulative gate passed at `bf76210`/`b2609e0`; exact evidence is recorded in `evidence/m2/`. |
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

- [x] `flake.nix` and locked inputs provide the complete development environment.
- [x] Zig 0.16.0 and DPDK 25.11.2 sources/hashes are pinned.
- [x] `build.zig`/`build.zig.zon` and proposed module layout exist.
- [x] Formatting, Debug, ReleaseSafe, ReleaseFast, test, docs, benchmark, fuzz,
      and CI entry points are defined.
- [x] Linux x86-64 clean builds pass in all build modes.
- [x] Linux AArch64 public library cross-compiles.
- [x] Required DPDK C ABI size/offset assertions pass.
- [x] DPDK virtual-PMD burst/token round trip passes with no huge pages.
- [x] Coverage-guided fuzz engine is selected by D-012 ADR with a working
      crash/reproducer/corpus workflow.
- [x] Benchmark result and environment manifest schemas validate examples.
- [x] Dependency and license integrity evidence is recorded.
- [x] M0-V documentation and clean-environment commands pass.

Evidence:

- Commands: `nix build .#dpdk --print-build-logs`; `nix develop --command zig build ci`; exact subcommands in `evidence/m0-v/VERIFICATION.md`.
- Test reports: `evidence/m0-v/VERIFICATION.md`; matching Zig/C ABI report, no-huge virtual token, three-mode clean-cache, and AArch64 evidence.
- ADRs: `docs/adr/0001-project-license.md`,
  `docs/adr/0012-coverage-guided-fuzz-engine.md`.
- Benchmarks/schemas: `bench/schemas/`, `bench/examples/`; validated synthetic regression example only, no capacity claim.
- Known limitations: AArch64 build-tested only; M0-H physical testbed and production performance evidence remain deferred.

### M1 checklist

- [x] Stable identifiers, bounded errors, budgets, and testable time exist.
- [x] Adapter-token state machine and exact completion accounting exist.
- [x] Segment-aware `PacketView`, origin, slots, and lifetime checks exist.
- [x] Synthetic queues provide deterministic failure/backpressure behavior.
- [x] Bounded PCAP support and fuzz corpus exist.
- [x] All ranges, truncations, malformed descriptors, and allocation failures
      are tested.
- [x] Sizes through configured maximum traverse unchanged without payload copy.
- [x] INV-PKT-001 and INV-PKT-002 pass with documented evidence.

Evidence:

- Commands: `nix develop --command zig build ci`; narrow commands and results
  are recorded in `evidence/m1/VERIFICATION.md`.
- Review closure register:
  [evidence/m1/REVIEW.md](../evidence/m1/REVIEW.md).
- Requirement/test mapping: validated `docs/requirements/coverage.yaml`.
- Fuzz/property artifacts: `test/fuzz/pcap-corpus/`; independent exhaustive
  token and queue models in the M1 tests.
- Benchmark delta: first schema-validated M1 synthetic baseline at
  `bench/examples/benchmark.m1.json`; no prior comparable M1 delta.
- Known limitations: synthetic/virtual regression only; 256-byte configured
  regression maximum; AArch64 build-tested only.

### M2 checklist

- [x] Active selection, dispositions, and output grouping exist.
- [x] Lazy Ethernet/IPv4/IPv6/TCP/UDP parsing and fragment semantics exist.
- [x] Structured/raw mutation capability boundary and journal exist.
- [x] Length/checksum finalization is failure-atomic.
- [x] Retention leases are bounded and leak-tested.
- [x] Selection property tests and all header-byte truncations pass.
- [x] Scapy differential packet/checksum tests pass.
- [x] Batch-size parser/no-op baselines are recorded.
- [x] AC-001, AC-002, AC-010, and packet invariants pass.

Evidence:

- Commands, writer preflight, and accepted independent exact-tree gate:
  `evidence/m2/VERIFICATION.md`.
- Review closure register:
  [evidence/m2/REVIEW.md](../evidence/m2/REVIEW.md).
- Requirement/test mapping: validated cumulative
  `docs/requirements/coverage.yaml` with preserved M1 provenance.
- Differential/fuzz artifacts: `test/m2/oracle.zig`, `test/fuzz/m2-*-corpus/`,
  dictionaries/reproducer records, and `tools/m2/` runners.
- Benchmark delta: first host-local M2 batch 1/4/8/16/32/64 cycle baseline at
  `bench/examples/benchmark.m2.json`; no prior comparable M2 delta.
- Known limitations: synthetic/virtual only; bounded fuzz smoke and an expanded
  14-case deterministic Scapy matrix; host-local cycles are not production
  capacity. All sixteen findings are closed, and the retained fuzz/benchmark
  artifacts bind remediation source commit `05eb395`. The accepted final gate
  is synthetic/virtual and does not make a production-capacity claim.

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
| 2026-07-19 | M0-V | Recorded provisional completion before independent review. | Superseded by the review-remediation row below; the original evidence did not satisfy every exit condition. | Reopen M0-V and correct the identified gaps. |
| 2026-07-19 | M0-V | Reopened after independent review found exit-gate gaps. | Remediation must pass all-system flake evaluation, a Zig-observed real mbuf batch boundary with deterministic cleanup accounting, Zig-instrumented AFL coverage, corrected timeout/license/schema evidence, and documentation/API requirements. | Correct M0-V only; do not begin M1 or mark complete before review and project-license reconciliation. |
| 2026-07-19 | M0-V | Completed review remediation and reconciled evidence. | `nix develop --command zig build ci` passed from isolated Zig caches; standalone `nix flake check --no-build --all-systems`, schema, locked-license, DPDK lifecycle, Zig-branch fuzz, documentation, formatting, and diff checks passed. Exact results: `evidence/m0-v/VERIFICATION.md`. | M1 is the next predecessor-gated action; M0-H remains deferred and mandatory before M4. |
| 2026-07-19 | M1 | Began foundation, packet ownership, views, bounded capture, and deterministic synthetic adapter implementation. | Expected gate: exact token completion and stale-view detection for INV-PKT-001/002, full range/segment/descriptor/allocation-failure coverage, fuzzable bounded PCAP parsing, and unchanged zero-payload-copy traversal through the configured maximum in all three build modes. | Implement and verify M1 only; do not begin M2. |
| 2026-07-29 | M1 | Closed the independent review findings: hardened owner lifetime and unique pointer-free provenance, cross-owner/stale/forged-handle rejection, iterator validation, transactional receive, allocation/copy instrumentation, negative controls, artifact binding, coverage validation, and version consistency. | The retrospective closure register is [evidence/m1/REVIEW.md](../evidence/m1/REVIEW.md); commands, artifacts, results, and limitations are retained in `evidence/m1/VERIFICATION.md`. | Final independent ownership review and gate verification. |
| 2026-07-29 | M1 | Accepted M1 after final independent review found no blocking issue and independent gate verification reproduced both immutable manifests, the exact cumulative CI gate, and `git diff --check`. | M1 status is Complete; review closure is recorded in [evidence/m1/REVIEW.md](../evidence/m1/REVIEW.md), and authoritative gate evidence is recorded in `evidence/m1/VERIFICATION.md`. | M2 is the next predecessor-gated action and remains Not started; M0-H remains deferred until required before M4. |
| 2026-08-02 | M2 | Began parsing, selection, dispositions, mutation, and bounded retention implementation. | Expected cumulative gate: both specification manifests; `nix develop --command zig build ci`; `git diff --check 60f920b3aa6d2f5571d2176959379bcf426ac3a5..HEAD`; clean ordinary/ignored status; unchanged commit/tree. | Implement and verify M2 only; do not begin M3 or claim the final independent gate. |
| 2026-08-02 | M2 | Committed the hardware-free implementation, tests, cumulative tooling, documentation, and first synthetic cycle baseline; writer focused preflight passed. | Exact commands, differential/fuzz results, artifact scope, and limitations are recorded in `evidence/m2/VERIFICATION.md`; milestone status remains In progress. | Run independent complete-diff review, remediate and close any findings, then run the exact-tree cumulative gate. |
| 2026-08-02 | M2 | Remediated the public disposition-state bypass and wrapper-only fuzz negative control; refreshed source-bound fuzz and cycle artifacts; seven findings are closed. | Debug, ReleaseSafe, ReleaseFast, the 12-case Scapy differential, both bounded AFL++ smokes, retained-evidence validators, and schemas pass; exact details are in `evidence/m2/REVIEW.md` and `evidence/m2/VERIFICATION.md`. | Obtain fresh core closure for CORE-002 and parser closure for PARSER-003, then run the independent exact-tree cumulative gate. |
| 2026-08-03 | M2 | Closed CORE-002 and PARSER-003 after fresh independent reproduction checks; all nine review findings are closed. | Exact discoverer commands and results at `cf55d9a`/`c441769d` are recorded in `evidence/m2/REVIEW.md`; milestone status remains In progress. | Run the independent exact-tree cumulative gate; do not begin M3 or mark M2 complete beforehand. |
| 2026-08-03 | M2 | Closed FRESH-001 after its successor discoverer rerun and refreshed both retained AFL++ summaries plus the 30-sample batch 1/4/8/16/32/64 ReleaseFast cycle artifact from the post-fix source tip; all fourteen findings are closed. | Raw-authority checks passed at `2e68819`/`edf5a82b`; retained artifact validators, schemas, and non-capacity scope passed for artifacts committed by `171d2af`. Exact evidence is recorded in `evidence/m2/REVIEW.md` and `evidence/m2/VERIFICATION.md`; milestone status remains In progress. | Run the mandatory post-High fresh full-diff review, then the independent final exact-tree cumulative gate; do not begin M3 or mark M2 complete beforehand. |
| 2026-08-11 | M2 | Addressed M2-FINAL-001 retention alias revocation and M2-EXIT-001 public entry-point/gate documentation; refreshed both retained AFL++ summaries and the 30-sample ReleaseFast cycle artifact from the remediation source tip. | Debug, ReleaseSafe, ReleaseFast, ReleaseSafe Linux AArch64, docs/links, schemas, M1/M2 coverage/version, retained fuzz, retained benchmark, formatting, register, and diff checks passed. Exact evidence is recorded in `evidence/m2/REVIEW.md` and `evidence/m2/VERIFICATION.md`; both findings await discoverer closure. | Obtain both discoverer closures, then run the mandatory post-High fresh full-diff review and independent final exact-tree cumulative gate; do not begin M3 or mark M2 complete beforehand. |
| 2026-08-11 | M2 | Re-addressed the discoverer's remaining M2-FINAL-001 output-pointer/raw-slice bypass with opaque checked output handles and atomic retention rejection after nonrevocable raw authority; corrected the remaining same-class M2-EXIT-001 M1-guide command and refreshed retained artifacts. | Debug, ReleaseSafe, ReleaseFast, ReleaseSafe Linux AArch64, docs/links, schemas, M1/M2 coverage/version, retained fuzz, retained benchmark, formatting, register, and diff checks passed. Artifacts bind clean source `05eb395`; exact evidence is recorded in `evidence/m2/REVIEW.md` and `evidence/m2/VERIFICATION.md`. Both findings remain addressed pending discoverer closure. | Obtain both discoverer closures, then run the mandatory post-High fresh full-diff review and independent final exact-tree cumulative gate; do not begin M3 or mark M2 complete beforehand. |
| 2026-08-11 | M2 | Closed M2-FINAL-001 and M2-EXIT-001 after their successor discoverers reran the corrective contracts at `1e6bf0e`/`fd6afdb`; all sixteen findings are closed. | The successor final reviewer passed all three x86 modes, ReleaseSafe Linux AArch64, retained validators, and the full corrective audit. The successor exit explorer passed the pinned documentation check, nearby public gate/API audit, diff check, and status inspection. Exact closure evidence is in `evidence/m2/REVIEW.md`; M2 remains In progress. | Run the mandatory fresh post-High full-diff review, then the independent final exact-tree cumulative gate; do not begin M3 or mark M2 complete beforehand. |
| 2026-08-11 | M2 | Accepted M2 after the mandatory post-High review and independent final exact-tree gate passed at `bf76210`/`b2609e0`; milestone status is Complete. | Both specification manifests passed; cumulative M2 hardware-free CI passed in 30.0 seconds; baseline-to-tip diff, clean status, ignored-status scope, and unchanged commit/tree checks passed. The initial sandboxed Nix fetcher-lock failure was rerun with scoped approval without changing repository state. Exact evidence is in `evidence/m2/VERIFICATION.md`. | M3 is the next predecessor-gated milestone. M0-H remains deferred and mandatory before M4. |
