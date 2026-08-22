# Saint Shield Implementation Progress

Last updated: 2026-08-22

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
| M3 - native processor contract and static pipeline | Complete | 2026-08-13 | 2026-08-23 | All findings through M3-GATE-001 are closed. The mandatory fresh review and independent final exact-tree retry passed and main accepted M3 at `9c008e5`/`18d2c7d`; exact evidence is recorded in `evidence/m3/`. |
| M4 - DPDK adapter and physical ownership loop | Not started | - | - | Requires M0-H. |
| M5 - worker runtime and core metrics | Not started | - | - | - |
| M6 - generation update and QSBR | Not started | - | - | - |
| M7 - sources, rollback, and state transitions | Not started | - | - | - |
| M8 - events, exporters, and local observability | Not started | - | - | - |
| M9 - standard policy language | Not started | - | - | - |
| M10 - bounded state and protection primitives | Not started | - | - | - |
| M11 - AF_XDP and optional integration proof | Not started | - | - | - |
| M12 - production hardening and 1.0 candidate | Not started | - | - | - |

## Completed target: M0-V through M3

M0-H remains Not started and is mandatory before M4. M4 is not activated.

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

- [x] Descriptor/capability schemas and comptime validation exist.
- [x] Prepared/worker lifecycle and reverse cleanup exist.
- [x] Tuple pipeline performs one direct call per processor per batch.
- [x] Stage metadata, resource estimates, and error/default policies exist.
- [x] Public processor test harness and example application exist.
- [x] Compile-fail suite covers every invalid declaration category.
- [x] Ordering, mixed dispositions, allocation faults, capability denial, and
      tiny reference-pipeline comparisons pass.
- [x] Fresh 0/1/2/4/8, diagnostic-control, and terminal-heavy benchmark
      evidence is recorded after authority-return acknowledgment.
- [x] PERF-CORE-001 current-source writer and cumulative gates pass; focused
      AC-003 and AC-012 remediation checks pass.
- [x] PERF-002/003/004 closed by the discovering performance reviewer.
- [x] M3-FRESH-001/002, M3-FRESH2-001, and M3-FINAL-001 are closed, the
      exact-context authority inventory is acknowledged, and current-source
      retained evidence plus the cumulative writer gate pass.
- [x] Mandatory fresh full-diff review and independent final exact-tree gate
      pass; main-session acceptance is recorded.

Evidence:

- Commands: focused remediation, exact reviewer acknowledgment,
  current-source capture, and the latest 463.24-second cumulative
  writer gate are recorded in `evidence/m3/VERIFICATION.md`.
- Requirement/test mapping: 51 exact cumulative claims in validated
  `docs/requirements/coverage.yaml`, with 27 M3 claims and preserved M1/M2
  provenance.
- Compile-fail/property artifacts: one legitimate external pipeline, 28
  declaration/public-authority rejection cases, 21 dedicated M3 runtime
  scenarios, and one benchmark-constructor allocation scenario, including
  authority forgery, schema,
  lifecycle, cleanup/failure sweeps, exact resource/work bounds, and a fixed
  seed reference comparison.
- Benchmark report: `bench/examples/benchmark.m3.json` has SHA-256
  `6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`,
  binds post-acknowledgment closure source `332aa44`/`1166318`, is committed
  alone by `0613106`, retains seven independent runs and 35 samples per
  variant, and passes ratios 0.994024/0.998583 at batches 32/64.
- Known limitations: synthetic/virtual host-local regression only; AArch64 is
  build-tested; live update/observability, sources, production adapters, and
  policy execution remain out of scope. Local integration remains pending
  separate direction. M0-H is mandatory before M4, which remains Not started.

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
| 2026-08-13 | M3 | Began the native processor contract, static pipeline, public synthetic harness, and deterministic example implementation. | Expected cumulative gate: both immutable specification manifests; Debug, ReleaseSafe, and ReleaseFast semantics; processor compile-fail contracts; native example; ReleaseSafe AArch64 concrete pipeline compile; M3 coverage/version, schemas, docs, benchmark/evidence, cumulative `nix develop --command zig build ci`; `git diff --check 8da41e27b385fd07f703a9f03c2de2ae38b0e696..HEAD`; clean ordinary/ignored status; unchanged committed tip/tree. | Implement M3 only, obtain independent review and closure of any findings, then run the final exact-tree gate; do not mark Complete or integrate beforehand. |
| 2026-08-13 | M3 | Committed the native processor/pipeline vertical slice, public synthetic harness/example, 16-case compile-fail suite, eight runtime scenarios, 51-claim cumulative mapping, documentation/version surface, fixed-anchor predecessor compatibility, and retained dispatch artifact; cumulative writer preflight passed. | `nix develop --command zig build ci` reported the complete cumulative M3 hardware-free gate passed. The retained ReleaseFast artifact binds clean source `73a5a60`/tree `70f04cf`; direct-4/direct-0 ratios are 0.993884 at batch 32 and 1.005086 at batch 64. Exact checks and non-capacity limitations are in `evidence/m3/VERIFICATION.md`; this is writer evidence only. | Run independent complete-diff review of `8da41e2..TIP`, remediate and close any findings, then run the final clean committed exact-tree gate. Keep M3 In progress and do not integrate or begin M4. |
| 2026-08-13 | M3 | Completed Critical remediation, both renewed authority-inventory acknowledgments, and the reviewed current-source artifact/cumulative writer gate; all API/resource and PERF-001/005/006 findings are closed. | Retained evidence binds `978cf09`/`5d98a71`, contains seven independent runs and 35 samples per variant, and passes PERF-CORE-001 at 1.005036/0.991626. The complete cumulative M3 gate passed in 478 seconds and its own fresh ratios were 1.007751/0.996709; exact evidence and limitations are in `evidence/m3/REVIEW.md` and `evidence/m3/VERIFICATION.md`. | Obtain discovering performance-reviewer closure for PERF-002/003/004, then run the mandatory post-High full-diff review and independent final exact-tree gate. Keep M3 In progress; do not integrate or begin M4. |
| 2026-08-13 | M3 | Recorded discovering performance-reviewer closure of PERF-002/003/004 at `933128b`/`90aeb35`, then addressed post-High M3-FRESH-001/002 source-only. | Pre-callback disposition/application/default validation, raw-authority rejection, post-callback batch-generation revocation, exact caller token reconciliation, and benchmark-constructor reverse unwind pass root/M3 tests in all modes plus compile-fail, example, AArch64, benchmark compile-only, docs, coverage, version, and diff checks. The retained artifact is unchanged at SHA-256 `630b7434ed89b6cce70425214f0f8774caa97bacf0f65029b46ac103d63a9941` and is stale for the new source. | Obtain exact `m3_api_review` re-audit/closure and renewed authority-inventory acknowledgment. Only then refresh the source-bound artifact and rerun its authorized gates; keep M3 In progress and do not integrate or begin M4. |
| 2026-08-13 | M3 | Recorded `m3_api_review` closure of M3-FRESH-001/002 and renewed authority-inventory acknowledgment at source `1839df61`/tree `8c367eac`, then retained and committed the reviewed current-source benchmark artifact. | Artifact commit `ea052dc3` binds that source, has SHA-256 `88a81ca196a99d3d8cac92d3ee6a018609deab2748f46f2ae933f60efa37010a`, preserves seven independent runs and 35 samples per variant, and passes ratios 0.997824/1.015560. Schemas, retained validation, ten negatives, and cumulative `zig build ci` pass; CI completed in 466.66 seconds and its fresh ratios were 0.993155/0.988615. | Run the mandatory post-High fresh full-diff review, then the independent final exact-tree gate. Keep M3 In progress; do not integrate or begin M4. |
| 2026-08-22 | M3 | Recorded `m3_resource_review` closure of M3-FRESH2-001 and renewed authority-inventory acknowledgment at source `8828ab7`/tree `ad390d9`, then retained and committed the reviewed current-source benchmark artifact. | Artifact commit `53b6c63` binds post-acknowledgment source `075b3f7`/tree `204d23d`, has SHA-256 `1073d68dea8bd43476d3f9122b8df265f0a11208540c9d1e08f57351dc7e50d2`, preserves seven independent runs and 35 samples per variant, and passes ratios 0.990147/0.998627. Schemas, retained validation, ten negatives, and cumulative `zig build ci` pass; CI took approximately 399 seconds and its fresh ratios were 0.996907/0.997095. | Run the mandatory post-High fresh full-diff review, then the independent final exact-tree gate. Keep M3 In progress; do not integrate or begin M4. |
| 2026-08-23 | M3 | Recorded `m3_api_review` closure of M3-FINAL-001 and exact-context authority-inventory acknowledgment at source `1dd6614`/tree `11d25fb`, then retained and committed the reviewed current-source benchmark artifact. | Closure commit `332aa44` is evidence-only. Artifact commit `0613106` binds that closure tree, has SHA-256 `6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`, preserves seven independent runs and 35 samples per variant, and passes ratios 0.994024/0.998583. Schemas, retained validation, ten negatives, and cumulative `zig build ci` pass; CI took 463.24 seconds and its fresh ratios were 0.998523/0.995566. | Run the mandatory fresh full-diff review, then the independent final exact-tree gate. Keep M3 In progress; do not integrate or begin M4. |
| 2026-08-23 | M3 | Accepted M3 after the mandatory fresh review and independent final exact-tree retry passed; `m3_final_gate` closed M3-GATE-001 and main accepted exact gate tip `9c008e5`/tree `18d2c7d`. | Both immutable manifests and canonical cumulative `nix develop --command zig build ci` passed; baseline-to-tip diff, unchanged commit/tree, clean ordinary status, retained artifact SHA `6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`, and accepted ratios 0.994024/0.998583 were verified from epoch 1787434127 through capture 1787434187. M3 status is Complete. | Do not activate M4. M0-H remains the mandatory predecessor and must be completed before M4; integration awaits separate main-session direction. |
