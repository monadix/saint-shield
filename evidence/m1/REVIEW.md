# M1 retrospective review closure register

Date: 2026-07-29
Milestone status: Complete
Scope: hardware-free M1 foundation, ownership, views, synthetic I/O, and PCAP

This register reconstructs the material M1 review cycles from the accepted
verification evidence and the review history that preceded acceptance. The
stable IDs and explicit status progressions were assigned retrospectively
because the workflow did not require a closure register during those cycles.
They do not change the original findings, remediation, gate, or acceptance.

## M1-CORE-001: Escaped-view owner lifetime

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: High
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: INV-PKT-002 lifetime and stale-view enforcement
- Observed issue: the processing scope could retain caller-frame state, so an
  escaped view could outlive that frame and leave a dangling or bypassable
  lifetime boundary.
- Bounded remediation: move lifetime state into an allocator-owned opaque
  `PacketBatchOwner`, pass the valid owner explicitly to handle operations,
  and add caller-frame escape, alias invalidation, and later-generation tests.
- Closure evidence: the final ownership review reported no blocking finding;
  `evidence/m1/VERIFICATION.md` records the escaped-view and all-mode lifetime
  evidence.

## M1-PERF-001: Mechanical zero-copy and allocation evidence

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: High
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: PERF-CORE-004 and the M1 unchanged
  zero-payload-copy traversal gate
- Observed issue: the original counters were not mechanically connected to
  the packet path and did not prove allocation, copy, or borrowed-segment
  identity behavior.
- Bounded remediation: wrap the actual queue allocators with
  `CountingAllocator`, centralize copy instrumentation, capture pre-receive
  segment identity, add allocation/copy negative controls, and bind runtime
  metrics to the benchmark artifact.
- Closure evidence: the final performance evidence reports zero packet-path
  allocations and abstraction-copy bytes, matching segment identities, both
  negative controls, and `artifact=matched`.

## M1-IO-001: Transactional receive failure atomicity

- Discoverer: not preserved in the accepted retrospective record
- Assigned implementer: `hard_implementer`
- Severity: not preserved in the accepted retrospective record
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: INV-PKT-001 receive failure atomicity
- Observed issue: receive could partially commit token or caller-visible state
  before a later slot descriptor or receive-sequence failure.
- Bounded remediation: preflight the whole burst into temporary slots before
  applying token transitions or publishing caller-visible slots.
- Closure evidence: injected second-slot descriptor failure and
  receive-sequence overflow leave token states, receive/completion counts,
  sequence, cursor, and caller slots unchanged. The accepted Debug,
  ReleaseSafe, ReleaseFast, and cumulative evidence is recorded in
  `VERIFICATION.md`.

## M1-COVERAGE-001: Requirement-map evidence loopholes

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: canonical M1 requirement/test mapping
- Observed issue: the coverage evidence did not strictly prove allowed status
  values, nonempty code evidence, valid paths, and test reachability from the
  executed root.
- Bounded remediation: replace the provisional map with the canonical
  11-claim map, validate paths and reachable test names from `src/root.zig`,
  restrict statuses, require code evidence, and add seven negative self-tests.
- Closure evidence: coverage validation and its negative self-tests pass in
  the accepted cumulative gate.

## M1-VERSION-001: M1 version evidence consistency

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: package, public API, and coverage-claim version
  consistency
- Observed issue: the M1 version was not mechanically consistent across all
  claimed surfaces.
- Bounded remediation: set the exact M1 version and add a validator that
  compares `build.zig.zon`, `src/root.zig`, and every M1 coverage claim.
- Closure evidence: the accepted gate records `0.1.0-m1` consistency across
  all three surfaces.

## M1-CORE-002: Address-bearing public handles

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: High
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: INV-PKT-002 safe public lifetime/provenance boundary
- Observed issue: public scalar batch/view handles encoded an owner address,
  exposing address-bearing provenance and permitting unsafe interpretation.
- Bounded remediation: replace address-derived handles with pointer-free tags,
  require a valid opaque owner argument for operations, and reject forged and
  stale tags before private storage access.
- Closure evidence: the final ownership review accepted the pointer-free
  owner-bound handle design and the accepted evidence records forged-tag tests
  in Debug, ReleaseSafe, and ReleaseFast.

## M1-CORE-003: Mutable iterator-state validation

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: High
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: INV-PKT-002 bounded segment traversal
- Observed issue: mutable iterator progress/range state could reach unchecked
  arithmetic or avoid complete validation on later calls.
- Bounded remediation: revalidate the view tag, range, and progress on every
  `next(owner)` call and recompute segment offsets with checked addition.
- Closure evidence: adversarial mutations now return bounded stale, bounds, or
  overflow errors in all three build modes.

## M1-PERF-002: Benchmark negative-control binding

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: PERF-CORE-004 benchmark integrity
- Observed issue: benchmark booleans were not derived exclusively from
  observing the exact expected negative-control failures.
- Bounded remediation: set each boolean only in the matching expected-error
  branch, fail unexpected success, and compare the derived values with the
  embedded artifact.
- Closure evidence: the accepted ReleaseFast benchmark observes both exact
  guard failures and reports `artifact=matched`.

## M1-CORE-004: Cross-owner provenance collision

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: High
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: INV-PKT-002 owner provenance and stale-handle
  isolation
- Observed issue: owner-local generations could collide between two live
  owners, allowing a handle tag to be ambiguous across owners.
- Bounded remediation: bind each handle to a process-unique monotonic owner
  identity, validate identity before generation/index access, exhaustively
  test two-owner cross-use, and reject identity exhaustion without wrap/reuse.
- Closure evidence: the final ownership review found no blocker; the accepted
  evidence records cross-owner rejection and owner-identity exhaustion tests.

## M1-DOCS-001: Atomic-operation wording

- Discoverer: `reviewer`
- Assigned implementer: `hard_implementer`
- Severity: Low
- Status progression: `open` -> `addressed` -> `closed`
- Affected invariant/gate: internal packet documentation accuracy
- Observed issue: the documentation said the design used no atomics even
  though owner identity assignment uses a setup-only atomic operation.
- Bounded remediation: state that the packet path uses no atomics while
  documenting the setup-only owner-identity atomic.
- Closure evidence: the wording was corrected during completion recording; no
  executable or gate input changed.

## Final verification record: M1-GATE-001

- Discoverer: `gate_verifier`
- Assigned implementer: not applicable; validation-only
- Severity: not applicable; no failure was found
- Status: `closed`
- Gate: complete cumulative hardware-free M1 exit gate
- Verification: both immutable manifests passed, followed by
  `nix develop --command zig build ci` and `git diff --check`.
- Result: the cumulative CI ended with
  `complete cumulative M1 hardware-free CI gate passed`; the gate verifier
  reported M1 acceptable, and the main session accepted it.
- Authoritative evidence: [VERIFICATION.md](VERIFICATION.md).

## Process-review history

Governance findings formerly recorded here have moved to the
[process review register](../process/REVIEW.md). The register preserves the
old M1 workflow IDs as retrospective cross-references. This file retains only
technical M1 findings and the final M1 product gate record.
