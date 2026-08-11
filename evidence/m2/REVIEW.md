# M2 review closure register

Date opened: 2026-08-02

Milestone status: Complete

Scope: hardware-free M2 parsing, dispositions, mutation, finalization, and retention

The review scope is the complete committed tree from baseline
`60f920b3aa6d2f5571d2176959379bcf426ac3a5` through the final declared M2 tip.
All sixteen findings are closed. The mandatory post-High fresh full-diff review
and independent exact-tree gate were subsequently accepted; exact acceptance
evidence is recorded in `evidence/m2/VERIFICATION.md`.

## Received closure evidence

- `parser_reviewer` reported exit 0 from
  `nix develop --command zig build test`,
  `nix develop --command zig build -Doptimize=ReleaseSafe test`,
  `nix develop --command zig build -Doptimize=ReleaseFast test`, and
  `nix develop --command zig build m2-scapy-differential`; all 12 differential
  cases passed.
- Before its final response was interrupted, `core_reviewer` reported the
  M2-PARSER-001 and M2-CORE-003 reproductions fixed in Debug, ReleaseSafe, and
  ReleaseFast, with all three unit commands and expanded Scapy passing. This is
  recorded only for those main-authorized closures; no process finding is
  inferred from the interruption.
- `adapter_reviewer`/`performance_reviewer` closed their listed perspectives
  after `nix develop --command zig build test`, the corresponding ReleaseSafe
  and ReleaseFast commands,
  `nix develop --command zig build m2-scapy-differential`,
  `nix develop --command zig build m2-fuzz-evidence`,
  `nix develop --command zig build -Doptimize=ReleaseFast m2-bench`,
  `nix develop --command python3 tools/m2/benchmark-evidence.py`, both bounded
  AFL++ build steps with zero saved crashes/timeouts, and
  `git diff --check 60f920b3aa6d2f5571d2176959379bcf426ac3a5..HEAD`
  passed on a clean tree.
- At committed tip `cf55d9a` and tree `c441769d`, `core_reviewer` closed
  M2-CORE-002 after all-mode tests, compile-time direct-field rejection, and
  exact token/shutdown balance passed. At the same tip/tree, `parser_reviewer`
  closed M2-PARSER-003 after all-mode tests, the 12-case Scapy differential,
  both bounded AFL++ smokes with exact Zig outcome 6/C-wrapper status 3, and
  the retained fuzz validator passed.
- At committed tip `2e68819` and tree `edf5a82b`, `fresh_reviewer` closed
  M2-FRESH-001 after the keyed owner-private BLAKE3 authority tests rejected
  ordinary conversion, `editor_bits | 0x80`, legacy nonce values 1 through 65,
  arbitrary bits, superseded authority, cross-owner use, and stale use while
  the trusted path succeeded. Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe
  Linux AArch64 passed; the reviewed diff and status remained unchanged.

## M2-PARSER-001: Declared protocol extents ignored during finalization

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-007, FR-PKT-008, INV-PKT-005; mutation
  failure must never transmit corruption.
- Discoverers: `parser_reviewer` and `core_reviewer`; both must independently
  rerun their checks and close this canonical entry.
- Assigned writer: `m2_writer`.
- Concrete evidence: `src/packet/root.zig` `finalizeContext` and
  `checksumRangeWithOverrides` derive transport coverage from the complete
  active frame rather than the declared IPv4 total length, IPv6 payload length,
  and TCP/UDP extents.
- Expected behavior: finalization uses mutually consistent declared protocol
  extents, excludes Ethernet padding/trailers, and fails closed before changing
  bytes when those extents are inconsistent.
- Observed behavior: padded/trailing bytes can enter TCP/UDP checksum and length
  calculations; inconsistent extents are not uniformly rejected.
- Reproduction and seed/trace: deterministic padded IPv4/IPv6 TCP/UDP fixtures;
  no randomized seed or external trace is required.
- Failing layer: packet parser/finalizer boundary.
- Bounded remediation/rechecks: derive and validate network/transport extents,
  preserve IPv4 UDP zero-checksum semantics, and add padded, split-segment, odd
  payload, and zero-checksum Scapy/unit fixtures for IPv4/IPv6 TCP/UDP.
- Addressing evidence: commit `716c250` derives mutually consistent declared
  protocol extents, preserves/restores header bytes transactionally, excludes
  Ethernet padding, and covers split padding, odd IPv4/IPv6 TCP/UDP trims,
  zero-checksum semantics, and inconsistent extents. Commit `9ac72b9` adds the
  corresponding expanded Scapy matrix. Writer rechecks passed in Debug,
  ReleaseSafe, and ReleaseFast plus `m2-scapy-differential`.
- Closure result: closed. `parser_reviewer` reported exit 0 from Debug,
  ReleaseSafe, ReleaseFast, and `m2-scapy-differential` (12 cases), including
  the formerly failing padded-checksum reproduction. `core_reviewer` reported
  the reproduction fixed in all three modes before its final response was
  interrupted; the main session explicitly accepted closure from both
  discoverer perspectives.

## M2-PARSER-002: Parsed cache pointer escapes generation validation

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: INV-PKT-002 lifetime/generation enforcement and
  the public safe packet-view boundary.
- Discoverers: `parser_reviewer` and `core_reviewer`; both must independently
  rerun their checks and close this canonical entry.
- Assigned writer: `m2_writer`.
- Concrete evidence: public `PacketView.parse` returns `!*const ParsedPacket`
  pointing into owner cache storage; dereferencing later does not revalidate
  owner, generation, invalidation, or parser configuration.
- Expected behavior: parsed results are safe values or opaque checked handles
  whose every access validates the live owner/generation/configuration.
- Observed behavior: a cache pointer can escape invalidation and later owner
  generations and remain directly readable.
- Reproduction and seed/trace: deterministic parse, save result, invalidate,
  begin a new generation/configuration, and read the saved pointer; no random
  seed is required.
- Failing layer: public parsing API and owner-cache lifetime boundary.
- Bounded remediation/rechecks: return `ParsedPacket` by value or introduce an
  opaque checked handle; add stale, new-generation, configuration, invalidation,
  and public-surface pointer-audit tests.
- Addressing evidence: commit `be12615` returns `ParsedPacket` by value and
  tests invalidation, stale views, new owner generations/configurations, and
  the immutable saved value. Writer rechecks passed in Debug, ReleaseSafe, and
  ReleaseFast.
- Closure result: closed. `parser_reviewer` reported exit 0 from Debug,
  ReleaseSafe, and ReleaseFast plus return-type/lifetime inspection; the main
  session confirmed the required discoverer closures were received.

## M2-PARSER-003: Differential and finalizer fuzz oracles are incomplete

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: M2 Scapy differential evidence, fuzz/reproducer
  evidence, FR-TEST-003, and INV-PKT-005.
- Discoverer: `parser_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `tools/m2/scapy-differential.py` covers IPv4 UDP/TCP and
  IPv6 UDP only; `test/fuzz/m2_finalizer_fuzz.zig` treats bounded completion as
  success without independently checking semantic bytes or a deliberate
  negative-control failure.
- Expected behavior: the differential matrix exercises IPv6 TCP plus applicable
  VLAN/options/extensions/fragments/padding/odd/zero dimensions, and finalizer
  fuzzing asserts byte atomicity/output readiness with a proven negative control.
- Observed behavior: important protocol dimensions and semantic-oracle wiring
  can regress while the current checks still pass.
- Reproduction and seed/trace: inspect the deterministic fixture list and fuzz
  return paths; existing AFL seed corpus is retained, with no failing random
  seed yet.
- Failing layer: differential/fuzz evidence.
- Bounded remediation/rechecks: expand deterministic Scapy cases, add semantic
  invariants and an intentional negative control to the fuzz workflow, then run
  both differential and bounded AFL++ targets.
- Addressing evidence: commit `9ac72b9` expands the Scapy cases and makes edit
  failure byte-atomicity, finalizer/output readiness, reparsing, and the
  deliberate semantic negative control part of the fuzz oracle. Commits
  `74390b9` and `49c694b` retain and validate the bounded campaign evidence.
  Commit `f0a9bb3` moves both negative controls into Zig semantic postconditions,
  requires exact oracle outcome 6 in the wrapper, snapshots pre-finalizer bytes,
  proves failure restoration/output rejection, and independently validates
  declared IPv4/IPv6/UDP/TCP lengths and applicable checksums after success.
  Writer rechecks passed for the 12-case differential and both fuzz targets.
- Closure result: closed by `parser_reviewer` at `cf55d9a`/`c441769d` after
  Debug, ReleaseSafe, ReleaseFast, the 12-case `m2-scapy-differential`, both
  bounded AFL++ smokes with exact Zig semantic outcome 6/C-wrapper status 3,
  and `m2-fuzz-evidence` passed.

## M2-CORE-002: Retention lease is not bound to the selected packet

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-011, FR-PKT-012, AC-010, INV-PKT-001,
  exact ownership transfer and completion accounting.
- Discoverers: `core_reviewer` and `adapter_reviewer`; both must independently
  rerun their checks and close this canonical entry.
- Assigned writer: `m2_writer`.
- Concrete evidence: `RetentionPool.acquire` accepts an independent raw
  `PacketSlot`, while `DispositionWriter` accepts a pre-existing lease for any
  selection; acquisition and disposition recording are not atomically bound to
  the exact owner/generation/index/token.
- Expected behavior: one acquisition/record operation binds one lease to one
  live packet identity and rejects reuse, duplicate/cross-slot selection,
  owner/pool mismatch, stale generation, and forged values.
- Observed behavior: the same lease can represent a different selected slot or
  cover more than one selected packet, weakening token provenance.
- Reproduction and seed/trace: deterministic two-slot selection with one lease;
  cross-owner/pool and stale/forged lease cases; no random seed required.
- Failing layer: packet disposition/retention ownership boundary.
- Bounded remediation/rechecks: combine or strongly bind acquisition and
  disposition recording, validate exact packet provenance, and test all reject
  cases plus exact token balance and shutdown accounting.
- Addressing evidence: commit `be12615` makes retention acquisition private and
  atomically binds the live owner, generation, packet index, slot, token, and
  pool in `DispositionWriter.retain`. Tests cover duplicate/cross-slot,
  selection, owner/pool, stale/forged, exhaustion, leak, and exact token-balance
  cases in Debug, ReleaseSafe, and ReleaseFast. Commit `f0a9bb3` replaces the
  public writable representation with an owner/batch-generation-bound scalar
  handle whose resolver sees only private preallocated owner state. Direct-field
  API audit, duplicate/cross-slot/cross-owner/stale/forged, and exact-balance
  tests pass in all three modes.
- Closure result: closed. `adapter_reviewer` had closed its perspective after
  Debug, ReleaseSafe, ReleaseFast, and adapter evidence checks passed.
  `core_reviewer` closed the later public-field bypass at
  `cf55d9a`/`c441769d` after all-mode tests, compile-time rejection of direct
  `active`/`values` field access, and exact retention token/shutdown balance
  passed.

## M2-CORE-003: Forged public packet indices can panic selection operations

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-PKT-010, INV-PKT-004, bounded-error public API
  behavior in Debug, ReleaseSafe, and ReleaseFast.
- Discoverer: `core_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: public `PacketSelection.contains` and `without` shift by
  `PacketIndex.raw()` without validating forged enum values 64 through 255.
- Expected behavior: every checked public selection operation returns a bounded
  error for invalid or cross-batch indices in every supported build mode.
- Observed behavior: safe forged `PacketIndex` values can reach a shift cast and
  panic or trap rather than return an error.
- Reproduction and seed/trace: deterministic `@enumFromInt(64)` and `255` plus
  a valid index from a larger batch applied to a smaller selection; no seed.
- Failing layer: public selection API.
- Bounded remediation/rechecks: make membership/removal checked and batch-bound,
  add forged/cross-batch tests, and run them in all three optimization modes.
- Addressing evidence: commit `be12615` makes selection membership/removal
  batch-bound checked operations and tests forged values 64 and 255 plus a
  valid larger-batch index against a smaller selection. Writer rechecks passed
  in Debug, ReleaseSafe, and ReleaseFast.
- Closure result: closed. `core_reviewer` reported the forged-index
  reproductions fixed in Debug, ReleaseSafe, and ReleaseFast; all three unit
  commands exited 0.

## M2-ADAPTER-001: Raw output submission bypasses packet readiness

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-007, FR-PKT-008, FR-TEST-003,
  INV-PKT-001, INV-PKT-005; mutation failure must never transmit corruption.
- Discoverer: `adapter_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: public synthetic `OutputQueue.submit(*const PacketSlot)`
  accepts a raw slot independently of the owner/generation journal and current
  resized owner-held slot; `submitBatch` is not the only public output path.
- Expected behavior: output requires an unforgeable live readiness proof or a
  checked owner/batch/index path and cannot submit unfinalized, raw-invalid,
  failed, stale, or stale-resize packet state.
- Observed behavior: callers can bypass `validateForOutput` and owner-held slot
  selection through raw `submit`.
- Reproduction and seed/trace: deterministic unfinalized, invalid raw edit,
  injected edit failure, invalidated batch, and resized-stale-slot submissions;
  no random seed.
- Failing layer: synthetic output adapter/public API.
- Bounded remediation/rechecks: remove/restrict raw submission or require an
  unforgeable readiness token; add negative cases and exact token-balance checks.
- Addressing evidence: commit `be12615` restricts raw queue submission and
  exposes the checked owner/batch/index path. Negative tests cover unfinalized,
  raw-invalid, injected edit failure, invalidated, and stale-resize states plus
  token return in Debug, ReleaseSafe, and ReleaseFast.
- Closure result: closed by `adapter_reviewer`; Debug, ReleaseSafe, and
  ReleaseFast tests exited 0 with the negative output-capability cases intact.

## M2-ADAPTER-003: Tail trim cannot be finalized transactionally

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-007, FR-PKT-008, INV-PKT-005, structured
  resize correctness and mutation failure atomicity.
- Discoverer: `adapter_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `PacketEditor.trimTail` changes the active frame length,
  then finalization reparses strict stale IPv4/IPv6/UDP lengths and rejects the
  shortened packet before updating those declared lengths.
- Expected behavior: supported payload shortening uses pre-resize/journal
  metadata to derive new legal extents and transactionally update lengths and
  checksums, with unchanged bytes on failure.
- Observed behavior: legal payload tail trim cannot reach an output-ready state.
- Reproduction and seed/trace: deterministic odd-length IPv4/IPv6 TCP/UDP
  payload trim fixtures; no random seed.
- Failing layer: editor journal/finalizer/adapter readiness boundary.
- Bounded remediation/rechecks: retain pre-resize parse metadata, finalize into
  validated transactional bytes, and cover odd payload trims and failure paths.
- Addressing evidence: commit `716c250` retains the pre-resize parsed state and
  frame length, prepares all length/checksum writes before applying them, and
  restores headers if final reparsing fails. Odd IPv4/IPv6 TCP/UDP trims and
  failure paths pass in Debug, ReleaseSafe, ReleaseFast, and the Scapy matrix.
- Closure result: closed by `adapter_reviewer`; Debug, ReleaseSafe,
  ReleaseFast, and the 12-case `m2-scapy-differential` exited 0.

## M2-PERF-001: Cycle artifact is not bound to its measured run

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: M2 batch 1/4/8/16/32/64 parser/no-op cycle
  evidence and benchmark artifact integrity.
- Discoverer: `performance_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `bench/examples/benchmark.m2.json` records
  `m2-writer-preflight` with `dirty: true`; the live benchmark prints fresh
  cycles but validates only positive embedded placeholder values and discards
  its measured summary.
- Expected behavior: a retained raw/machine-readable summary is truthfully bound
  to commit, tree, environment, fixtures, settings, and all required batches,
  with warmup/repeats/hashes or an equivalent reproducible method.
- Observed behavior: the checked artifact does not identify the measured tree
  and live values need not match any retained evidence.
- Reproduction and seed/trace: rerun `zig build -Doptimize=ReleaseFast m2-bench`
  and compare stdout with the embedded artifact; deterministic configuration,
  hardware timing noise, no random seed.
- Failing layer: benchmark instrumentation/artifact binding.
- Bounded remediation/rechecks: generate and retain a machine-readable summary
  with truthful commit/tree/environment/fixture/settings hashes, warmup and
  repeated measurements for all batches, and preserve the non-capacity label.
- Addressing evidence: commit `1494193` adds an explicit warmup, five raw
  samples per batch, a clean-tree capture/validator, and a raw benchmark step.
  Commit `ad9b4a7` retains 30 raw samples and medians bound to clean commit
  `1494193ebc028ce1ee0038af91eb185dcc2f8c3c`, tree
  `1b28027976f2c730385c9a9a8f708be81612a357`, environment, fixture, sources,
  settings, host observation, and raw-output hash. The fresh ReleaseFast run,
  retained validator, and schema checks pass; scope remains non-capacity.
- Closure result: closed by `performance_reviewer` after
  `zig build -Doptimize=ReleaseFast m2-bench`, the standalone benchmark
  validator, and benchmark schema checks passed. The refreshed artifact is
  bound to clean remediation commit `f0a9bb3` and remains non-capacity evidence.

## M2-PERF-002: AFL++ campaign result claims are not retained

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: M2 fuzz corpus/reproducer evidence and truthful
  acceptance-evidence statements.
- Discoverer: `performance_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `tools/m2/fuzz-smoke.sh` deletes its temporary AFL++
  findings/results at exit while `evidence/m2/VERIFICATION.md` records exact
  discovered-item counts from ephemeral output.
- Expected behavior: exact claims are supported by a retained machine-readable
  version/tree/seed-hash/settings/result/failure-path summary, or the claims are
  reduced to what durable artifacts prove.
- Observed behavior: later reviewers cannot reproduce or audit the exact
  campaign counts from the repository.
- Reproduction and seed/trace: run either M2 fuzz smoke and inspect the removed
  `mktemp` findings directory after exit; seed corpus is checked in.
- Failing layer: fuzz evidence retention.
- Bounded remediation/rechecks: retain a deterministic machine-readable summary
  for both targets with tool/version, commit/tree, seed hashes, settings, result,
  and failure path, or remove unsupported exact-count claims.
- Addressing evidence: commit `74390b9` emits source-bound summaries and commit
  `49c694b` retains both target results plus a validator for commit/tree,
  tool/version, sources, seeds, dictionaries, settings, coverage-map hash,
  semantic negative control, zero saved crashes/timeouts, and reproducer
  workflow. Unsupported volatile discovery counts were removed. Both bounded
  workflows and retained validation pass.
- Closure result: closed by `performance_reviewer`; both bounded AFL++ smokes
  reported zero saved crashes/timeouts, `m2-fuzz-evidence` passed, and volatile
  discovery counts remain intentionally unclaimed.

## M2-FRESH-001: Raw editor authority is castable from ordinary packet handles

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-007, FR-PKT-008, FR-PKT-009,
  INV-PKT-002, INV-PKT-005; ordinary processors must not acquire the trusted raw
  mutation capability by converting another public handle.
- Discoverer: `fresh_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: the first remediation encoded raw authority as
  `(monotonic_nonce << 8) | (0x80 | slot_index)`. The nonce starts at one and
  the first batch generation also starts at one, so the private record could
  be reconstructed from ordinary public handle fields.
- Expected behavior: a raw editor carries separately minted private authority
  that is checked on every raw operation; ordinary view/editor conversion,
  arbitrary bits, stale generation, and cross-owner use are rejected.
- Observed behavior: after the first raw mint in the first batch, converting
  `editor_bits | 0x80` to `RawPacketEditor` matched the live nonce authority
  and permitted a trusted raw write.
- Reproduction and seed/trace: first owner, first batch, slot zero, first raw
  mint, then `raw = editor_bits | 0x80` and `raw.write`; deterministic, no
  random seed or external trace.
- Failing layer: public mutation capability boundary.
- Bounded remediation/rechecks: derive an opaque token from setup-only private
  entropy and a keyed monotonic mint counter, retain bounded allocation-free
  collision handling and exact private authority validation, and cover the
  direct forge, enumerated legacy nonce values, ordinary conversion, arbitrary
  bits, stale/superseded/cross-owner use, and valid mint in all build modes.
- Addressing evidence: commit `b7f1669` replaces the predictable nonce formula
  with a setup-secret keyed-BLAKE3 opaque token, bounded collision retry, and
  an exact private `{token, batch generation, slot}` authority scan on every
  raw write. The focused unit covers trusted mint/write/finalize/output,
  ordinary conversion, the discoverer's `editor_bits | 0x80` forge, legacy
  nonce enumeration 1 through 65, arbitrary bits, superseded mint,
  cross-owner use, and reuse after generation invalidation. Formatting,
  Debug, ReleaseSafe, ReleaseFast, and Linux AArch64 cross-compilation pass.
- Closure result: closed by `fresh_reviewer` at `2e68819`/`edf5a82b` after
  the keyed owner-private BLAKE3 tokens rejected ordinary conversion, the
  discoverer's `editor_bits | 0x80` forge, legacy nonce values 1 through 65,
  arbitrary bits, superseded authority, cross-owner use, and stale use while
  the trusted mint/write/finalize/output path succeeded. Debug, ReleaseSafe,
  ReleaseFast, and ReleaseSafe Linux AArch64 passed; the reviewed diff and
  status remained unchanged.

## M2-FRESH-002: Initial UDP fragments reject a complete local header

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-PKT-006, INV-PKT-005, M2 fragment/parser
  semantics and Scapy differential evidence.
- Discoverer: `fresh_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: UDP parsing compares the declared UDP length with the
  fragment-local available bytes before accounting for an offset-zero
  incomplete IPv4/IPv6 fragment.
- Expected behavior: an initial fragment containing the complete eight-byte UDP
  header exposes present ports and declared length with the incomplete-fragment
  marker even when later UDP bytes are in later fragments; non-initial remains
  absent, a partial header is truncated, and declared length below eight is
  malformed.
- Observed behavior: valid offset-zero fragments whose UDP declared length
  exceeds the fragment-local bytes are classified malformed.
- Reproduction and seed/trace: deterministic IPv4 and IPv6 offset-zero UDP
  fragments with a complete header and declared length beyond the local
  fragment; no random seed.
- Failing layer: fragment-aware transport parser.
- Bounded remediation/rechecks: make UDP parsing fragment-aware while retaining
  mutation/finalizer rejection for incomplete transport edits; test initial,
  non-initial, atomic, partial-header, length-below-eight, segment-split, Scapy,
  and all build modes.
- Addressing evidence: commit `00f9cd7` makes the UDP declared-length bound
  fragment-aware only for incomplete offset-zero fragments, keeps atomic and
  complete datagrams strict, and adds IPv4/IPv6 initial, non-initial, atomic,
  partial-header, length-below-eight, every-split, mutation, and finalizer
  cases. Debug, ReleaseSafe, ReleaseFast, and the expanded pinned Scapy 2.7.0
  differential passed.
- Closure result: closed by `fresh_reviewer`; the offset-zero IPv4/IPv6 UDP
  fragment matrix and pinned Scapy cases preserve the required initial,
  non-initial, atomic, truncated, malformed, split, and edit-rejection
  semantics.

## M2-FRESH-003: Complete all-disposition mixture evidence is missing

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-PKT-010, FR-PKT-011, FR-TEST-003,
  INV-PKT-001, INV-PKT-003, INV-PKT-004, and the M2 all-disposition-mixtures
  exit evidence.
- Discoverers: `fresh_reviewer` and `exit_explorer`; the explorer's duplicate
  `M2-CORE-004` is merged into this canonical entry.
- Assigned writer: `m2_writer`.
- Concrete evidence: existing deterministic tests exercise several terminal
  dispositions and retention separately but do not run a bounded seeded
  reference model across Accept, Drop, Redirect, Complete, Retain, and Continue
  under every continue policy with exact final token outcomes.
- Expected behavior: generated bounded mixtures preserve receive order, active
  removal, configured/default output resolution, invalid-operation atomicity,
  retention provenance, and exactly one final token outcome; failures report
  seed, toolchain, and a bounded minimized operation trace.
- Observed behavior: a regression spanning disposition categories, continue
  policies, resolver configuration, and token completion can evade the current
  disjoint tests.
- Reproduction and seed/trace: inspect the current disposition tests; no failing
  random seed exists yet because the required seeded/reference suite is absent.
- Failing layer: disposition property/conformance evidence.
- Bounded remediation/rechecks: add a bounded seeded/reference-model suite for
  all disposition tags and accept/drop/complete continue policies, output and
  default resolution, receive order, invalid atomic operations, retention, and
  exact final token state; use the repository SeededTrace failure format in all
  modes.
- Addressing evidence: commit `103ba6a` adds a 48-case bounded seeded reference
  model whose 12-packet cases each contain all six disposition tags, vary
  operation order/configuration, cover accept/drop/complete leftover policies,
  compare receive-ordered resolved groups, prove five invalid operations
  atomic, and drive every token to its exact final state. Every failure path
  reports the SeededTrace seed, Zig 0.16.0 toolchain, and bounded operation
  prefix; Debug, ReleaseSafe, and ReleaseFast passed.
- Closure result: closed by `fresh_reviewer` and `exit_explorer`; both the
  finding and merged `M2-CORE-004` exit perspective accept the bounded
  all-disposition/reference/token-outcome evidence.

## M2-MUTATION-001: Insufficient-headroom atomicity is not directly evidenced

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-PKT-007, FR-PKT-008, FR-TEST-003,
  INV-PKT-005, and the M2 head/tailroom failure-atomicity exit evidence.
- Discoverer: `mutation_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: insufficient tailroom has an exact byte/descriptor
  snapshot assertion, while the corresponding insufficient-headroom path lacks
  a directly analogous snapshot test.
- Expected behavior: a failed prepend caused by insufficient headroom leaves
  packet bytes, length, descriptor state, and output eligibility unchanged or
  failed closed exactly as specified.
- Observed behavior: the path returns a bounded error but its full atomic-state
  preservation is not directly guarded against regression.
- Reproduction and seed/trace: deterministic mutable single-segment packet with
  zero headroom and a non-empty prepend request; no random seed.
- Failing layer: structured mutation failure evidence.
- Bounded remediation/rechecks: add the exact pre/post byte, length, descriptor,
  journal, and output-rejection snapshot analogous to tailroom and run relevant
  modes.
- Addressing evidence: commit `2724692` adds the zero-headroom prepend case and
  compares the complete backing bytes, packet length, descriptor active range
  and room, storage identity, capabilities, unchanged journal deltas/checksum
  work, explicit failed-closed journal flags, and output rejection. Debug,
  ReleaseSafe, and ReleaseFast passed.
- Closure result: closed by `mutation_reviewer`; the failed prepend preserves
  bytes, length, descriptor state, and journal deltas while failing output
  closed.

## M2-TEST-001: Selection property failures lack SeededTrace minimization

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: M2 selection-versus-oracle property evidence and
  the technical-plan deterministic randomized-failure reporting discipline.
- Discoverer: `test_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: the selection property test drives
  `std.Random.DefaultPrng` directly and relies on ordinary assertions, so a
  failure does not report the repository-standard seed/toolchain/minimized
  bounded operation trace.
- Expected behavior: the property uses `SeededTrace` and `reportFailure`, retains
  a bounded operation history, and minimizes/reports the failing prefix with
  seed and toolchain.
- Observed behavior: the fixed seed is visible in source but a failure lacks a
  self-contained reproducible minimized trace.
- Reproduction and seed/trace: deliberately perturb the selection oracle and
  run the property; current output lacks the required trace envelope.
- Failing layer: randomized test evidence and reproducer path.
- Bounded remediation/rechecks: migrate the property to `SeededTrace`, record
  bounded selection operations, call `reportFailure` with a minimized prefix,
  add a negative self-test of the report path where appropriate, and run all
  modes.
- Addressing evidence: commit `cdecdbc` moves the selection oracle onto one
  bounded SeededTrace per generated case, records each operation through the
  earliest failing prefix, reports seed/toolchain/trace for oracle, count, and
  iterator failures, and exercises the structured report fields in the helper
  negative-path test. Debug, ReleaseSafe, and ReleaseFast passed.
- Closure result: closed by `test_reviewer`; selection-oracle failures now
  emit the fixed seed, Zig toolchain, and bounded earliest-failing operation
  prefix through the repository SeededTrace report path.

## M2-FINAL-001: Retention does not revoke batch-side packet aliases

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PKT-011, FR-PKT-012, AC-010,
  INV-PKT-001; successful retention must transfer exclusive packet access to
  the lease and prevent batch-side access after completion.
- Discoverer: `final_reviewer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `RetentionPool.acquireBound` transfers the adapter token
  to `retained` and copies the same `PacketSlot` storage into the lease record,
  while `PacketView`, `PacketEditor`, `RawPacketEditor`, and batch output paths
  validate only owner/generation/index or raw authority. They do not validate
  current per-slot access ownership.
- Expected behavior: a successful retain atomically revokes every pre-minted
  batch-side handle, prevents new batch aliases and output submission, and
  leaves only bounded lease reads plus exactly-once completion. Revocation
  persists after completion and across stale generations; failed retention is
  atomic and leaves worker access unchanged.
- Observed behavior: pre-minted and newly created views/editors/raw editors can
  read or mutate shared mutable storage after retain and after
  `RetentionLease.complete`, while the batch output path can still reach the
  owner-held slot.
- Reproduction and seed/trace: one mutable packet with view, structured editor,
  and raw editor minted before `DispositionWriter.retain`; access each before
  and after lease completion, mint new aliases after retain, attempt output,
  then recycle the owner generation. Deterministic; no random seed.
- Failing layer: batch/retention ownership and alias-revocation boundary.
- Bounded remediation/rechecks: add per-slot ownership/access revocation or an
  equivalent checked epoch to every batch-side view/editor/raw/output path;
  preserve bounded lease reads, failure atomicity, exactly-once completion,
  reuse/recycle rejection, and exact token balance in Debug, ReleaseSafe,
  ReleaseFast, and ReleaseSafe Linux AArch64.
- Addressing evidence: source/test commit
  `2c725f9a3478a929d3305ce980ada32126bb33bb` (tree
  `2a81b7377a3d24e537d4c2671e4d2e0309fc7bdb`) adds a private per-slot
  `batch_owned`/`retained` access state checked by every view/editor/raw mint
  and use, iterator, journal/current-slot, validation, and synthetic output
  path. `RetentionPool.acquireBound` performs all fallible checks before the
  token transfer, then publishes the lease record and revokes batch access and
  raw authority in a no-failure suffix. The deterministic tests
  `FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 retention revokes all batch aliases through completion and generation reuse`,
  `FR-PKT-011 FR-PKT-012 AC-010 retention exhaustion preserves every batch capability atomically`,
  and
  `FR-PKT-011 FR-PKT-012 AC-010 retained synthetic packet rejects output through completion`
  cover mutable pre-minted/new aliases before and after completion, output,
  stale/recycled generations, lease reads, exact completion/token balance, and
  failure atomicity. Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe Linux
  AArch64 passed. Artifact commit
  `29b7a585907be37b7169550a66e4e21e7d730cec` retains clean source-bound
  parser/finalizer fuzz passes and the 30-sample batch 1/4/8/16/32/64
  ReleaseFast cycle artifact generated from source commit
  `bb5ba9efbfb6e16ab9c0dd9ae8bee4641bf5d1aa`; `m2-fuzz-evidence`,
  `m2-bench`, and schemas passed.
- Successor addressing evidence: the discoverer reproduced a bypass through a
  pre-minted raw `*const PacketSlot` returned by `slotForOutput`, plus the
  intrinsic inability to revoke raw slices already returned by
  `PacketView.contiguous` or `SegmentIterator.next`. Commit
  `66a7dc08884fb08a4bb96ec282d71fd6222a39e9` (tree
  `e7f4f064b831f10bafa8e494145ec34693170102`) removes that pointer-returning
  batch API. `PacketBatch.outputPacket` now returns an opaque
  owner/generation/index `OutputPacket`; every length, segment-count, segment,
  token, and submit operation revalidates current slot access. Issuing a
  non-empty view/iterator slice or raw output segment/token sets a per-slot
  generation-local nonrevocable-access barrier. A later retain returns
  `OutstandingBorrow` before token, disposition, lease, or access mutation;
  copy-only `PacketView.read` remains retainable. The deterministic tests
  `FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 retention revokes all batch aliases through completion and generation reuse`
  and
  `FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 raw slice and token escapes reject retention atomically`
  independently cover a pre-minted output handle after retain, completion,
  invalidation, and same-owner/index reuse; length/count/segment/token/submit
  checks; each raw-slice/token issuance path; failure atomicity; and the
  copy-read negative control. Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe
  Linux AArch64 passed. Artifact commit
  `cc2c6942f2aa012330918714593d7c5cb3f9e27a` retains clean source-bound
  parser/finalizer fuzz passes and the 30-sample batch 1/4/8/16/32/64
  ReleaseFast cycle artifact generated from clean source commit
  `05eb395c91902e41961f7164c18d9a50a5f37d7f` and tree
  `1e16b2e823b6bfb86afb0bc33ac10fef4be4675c`; retained-evidence,
  benchmark, schema, docs/link, coverage, and version checks passed.
- Closure result: closed by successor `final_reviewer` at committed tip
  `1e6bf0efc4590ccc824644605abfc0f8702c8b4c` and tree
  `fd6afdb820d3a13b201e4785b77875cd84c60f12` after rerunning Debug,
  ReleaseSafe, ReleaseFast, ReleaseSafe Linux AArch64, retained fuzz and
  benchmark validators, and the full corrective audit. The reviewer confirmed
  that no batch output path exposes an owner-slot pointer, every pre-minted
  `OutputPacket` operation revalidates current access, each generation-bound
  raw slice/token issuance path blocks later retention atomically, and the
  copy-read retainable control remains valid. The later accepted post-High
  review and final exact-tree gate are recorded in `evidence/m2/VERIFICATION.md`.

## M2-EXIT-001: Public M2 documentation names obsolete entry points and gate

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: M2 public API accuracy and canonical build/gate
  documentation.
- Discoverer: `exit_explorer`.
- Assigned writer: `m2_writer`.
- Concrete evidence: `docs/user/migration-0.2.md` describes a public
  `OutputQueue.submit`; `docs/user/m2-packet-processing.md` describes retention
  acquisition through `RetentionPool.acquire`; and
  `docs/user/m0-v-development.md` labels `zig build ci` as cumulative M1 while
  omitting the independent cumulative-M1 `ci-m1` command.
- Expected behavior: public documentation names readiness-checked
  `OutputQueue.submitBatch`, retention through `DispositionWriter.retain`,
  cumulative M2 `zig build ci`, and independent cumulative M1 `zig build ci-m1`.
- Observed behavior: the documented entry points and current-milestone gate
  labels disagree with the public API and build graph.
- Reproduction and seed/trace: inspect the three authored user guides against
  `src/io/synthetic/root.zig`, `src/packet/root.zig`, and `build.zig`;
  deterministic, no random seed.
- Failing layer: public documentation and exit-gate discoverability.
- Bounded remediation/rechecks: correct only the three public descriptions and
  run authored documentation/link, version, coverage, schema, register, and
  diff checks.
- Addressing evidence: commit
  `bb5ba9efbfb6e16ab9c0dd9ae8bee4641bf5d1aa` (tree
  `4431941ca25e26905f5d562f7704a4e2c0ec4077`) documents the public
  readiness-checked `OutputQueue.submitBatch`, acquisition through
  `DispositionWriter.retain`, cumulative-M2 `zig build ci`, and independent
  cumulative-M1 `zig build ci-m1`. Authored documentation/link checks,
  benchmark/environment schemas, M1/M2 coverage and version validators,
  formatting, register inspection, and `git diff --check` passed.
- Successor addressing evidence: commit
  `05eb395c91902e41961f7164c18d9a50a5f37d7f` (tree
  `1e16b2e823b6bfb86afb0bc33ac10fef4be4675c`) corrects the remaining
  same-class gap in `docs/user/m1-packet-foundation.md`: its command is now
  `zig build ci-m1`, described as the independently invocable cumulative M1
  gate. Authored documentation/link, M1/M2 coverage, coverage negative-control,
  and version-provenance checks passed.
- Closure result: closed by successor `exit_explorer` at committed tip
  `1e6bf0efc4590ccc824644605abfc0f8702c8b4c` and tree
  `fd6afdb820d3a13b201e4785b77875cd84c60f12` after the pinned
  `zig build docs-check`, a nearby public gate/API audit, `git diff --check`,
  and ordinary/ignored status inspection. The explorer confirmed the public
  guides name `OutputQueue.submitBatch`, `DispositionWriter.retain`,
  cumulative-M2 `zig build ci`, and independently invocable cumulative-M1
  `zig build ci-m1` consistently, with no remaining same-class gap.
