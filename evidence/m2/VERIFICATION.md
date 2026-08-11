# M2 verification evidence

Date: 2026-08-11

Scope: hardware-free parsing, dispositions, mutation, finalization, and retention

Status: Complete; all sixteen findings closed; mandatory post-High fresh
full-diff review and independent final exact-tree gate accepted at commit
`bf76210a318f15f6ab71e6ffcf1a20f1c0bc9277` and tree
`b2609e0020b8a33147ee19e563c7f159039c0beb`

Environment label: synthetic/virtual regression only; no production capacity claim

## Implementation checkpoint

The implementation and remediation commits through `66a7dc0` provide:

- opaque bounded packet selections, terminal dispositions, and receive-order
  output/drop/completion/retention grouping with explicit leftover/default
  output policies;
- lazy, segment-safe Ethernet, up-to-two-VLAN, IPv4/IPv6, TCP/UDP, and
  parse-only ICMP decoding with bounded IPv6 extension traversal and explicit
  fragment semantics;
- owner/generation-bound structured mutation, an explicitly unsafe raw testing
  capability, mutation journaling, failure injection, and output validation;
- length and IPv4/IPv6 TCP/UDP checksum finalization, including rejection of
  incomplete-fragment transport edits and illegal IPv6 UDP zero checksums;
- setup-allocated bounded retention leases with provenance, generation,
  exhaustion, exactly-once completion, stale/double completion, and shutdown
  leak checks;
- cumulative version, coverage, documentation, differential, fuzz, schema,
  and benchmark entry points under the canonical `zig build` interface.
- parsed results returned by value, checked/batch-bound selection operations,
  packet-bound retention acquisition, and output submission restricted to the
  live owner/batch/index capability path;
- declared network/transport extent validation, padding exclusion, preserved
  pre-resize parse state, and transactional finalizer header restoration;
- expanded differential/fuzz semantic oracles and durable source-bound fuzz
  and repeated cycle-regression evidence.
- an owner/batch-generation-bound scalar `DispositionWriter` handle whose
  writable arrays and active selection remain private preallocated owner state,
  including checked resolver access and stale/forged/cross-owner rejection;
- Zig-owned parser/finalizer negative controls, pre-finalizer failure snapshots,
  and an independent declared-length/checksum semantic helper.
- setup-secret keyed-BLAKE3 opaque raw tokens with bounded collision retry and
  private exact owner/slot/generation authority for every trusted raw write,
  rejecting ordinary converted, derivably forged, superseded, stale, and
  cross-owner handles;
- opaque checked output handles with no owner-slot pointer exposure, plus a
  per-slot nonrevocable-access barrier that rejects retention after issuing a
  non-empty raw view/iterator slice or raw output segment/token while leaving
  copy-only reads retainable;
- fragment-aware offset-zero IPv4/IPv6 UDP parsing that exposes a complete
  local header while preserving atomic, non-initial, truncated, malformed,
  mutation, and finalization boundaries;
- direct insufficient-headroom byte/length/descriptor/journal atomicity
  evidence, SeededTrace-backed selection failures, and a bounded seeded
  all-disposition reference model with exact token outcomes.

## Writer focused preflight

The writer ran these affected checks across the committed implementation, the
nine earlier findings, and the five then-new findings:

```sh
nix develop --command zig fmt --check build.zig src test bench
nix develop --command zig build test
nix develop --command zig build -Doptimize=ReleaseSafe test
nix develop --command zig build -Doptimize=ReleaseFast test
nix develop --command zig build m2-scapy-differential
nix develop --command zig build m2-parser-fuzz-smoke
nix develop --command zig build m2-finalizer-fuzz-smoke
nix develop --command zig build m2-fuzz-evidence
nix develop --command zig build -Doptimize=ReleaseFast m1-bench
nix develop --command zig build -Doptimize=ReleaseFast m2-bench
nix develop --command sh tools/m0/validate-schemas.sh
nix develop --command sh tools/m0/docs-check.sh
python3 tools/m1/validate-coverage.py
python3 tools/m1/validate-version.py
python3 tools/m2/validate-coverage.py
python3 tools/m2/validate-version.py
git diff --check
```

Result: pass. This is implementation preflight evidence, not the independent
M2 acceptance gate.

### Raw-capability and retained-evidence follow-up checkpoint

Commit `b7f1669` was checked with the following focused commands after the
discoverer's predictable-token reproduction reopened `M2-FRESH-001`:

```sh
nix develop --command zig fmt --check src
nix develop --command zig build test
nix develop --command zig build -Doptimize=ReleaseSafe test
nix develop --command zig build -Doptimize=ReleaseFast test
nix develop --command zig build -Doptimize=ReleaseSafe cross-aarch64
```

Result: pass. At that checkpoint, the retained fuzz and benchmark artifacts
remained bound to pre-fix commit
`103ba6a38394b62b06c060297d7e691aecbfde31` and tree
`821cad8e83d4594ac6993a16df0ad96a5bfe85f7`; because
`src/packet/root.zig` changed, they required regeneration before the final
review and gate.

The successor `fresh_reviewer` reran the raw-authority closure at committed tip
`2e68819` and tree `edf5a82b`. Keyed owner-private BLAKE3 tokens rejected
ordinary conversion, `editor_bits | 0x80`, legacy nonce values 1 through 65,
arbitrary bits, superseded authority, cross-owner use, and stale use while the
trusted path succeeded. Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe Linux
AArch64 passed; the reviewed diff and status remained unchanged. The reviewer
closed `M2-FRESH-001`, so all fourteen findings are closed.

From that same clean source tip, both canonical bounded AFL++ generators and
the canonical ReleaseFast cycle-evidence generator were rerun. Commit `171d2af`
retains the resulting parser and finalizer summaries plus the 30-sample batch
1/4/8/16/32/64 benchmark. The retained fuzz validator, benchmark validator,
benchmark/environment schemas, and explicit non-capacity-scope check passed.
This is focused evidence refresh, not the mandatory post-High fresh full-diff
review or the final exact-tree gate.

### Retention alias-revocation remediation checkpoint

Commit `2c725f9a3478a929d3305ce980ada32126bb33bb` adds private per-slot
batch/retained access state and checks it across view/editor/raw minting and
use, iterators, journal/current-slot access, readiness validation, and
synthetic output. Successful `DispositionWriter.retain` now publishes the
lease and revokes all batch-side authority in its no-failure suffix; failed
acquisition leaves the worker-owned token and every capability unchanged.
Mutable-storage tests cover pre-minted and newly requested aliases after
retain and completion, stale owner-generation reuse, output rejection,
bounded lease reads, exactly-once completion/token balance, and exhaustion
atomicity.

Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe Linux AArch64 passed. Commit
`bb5ba9efbfb6e16ab9c0dd9ae8bee4641bf5d1aa` corrects the three public API/gate
descriptions. Both bounded AFL++ summaries and the 30-sample ReleaseFast cycle
artifact were regenerated from that clean source commit and retained by
`29b7a585907be37b7169550a66e4e21e7d730cec`; fuzz/benchmark validators,
schemas, docs/links, formatting, and cumulative M1/M2 coverage/version checks
passed. At that checkpoint, both findings remained addressed pending their
discoverers' successor reruns.

### Opaque-output and nonrevocable-access successor checkpoint

The discoverer reproduced a remaining `M2-FINAL-001` bypass through a
pre-minted `*const PacketSlot` returned by `PacketBatch.slotForOutput`, and
identified the intrinsic nonrevocability of raw slices already returned by
`PacketView.contiguous` or `SegmentIterator.next`. Source/test/mapping commit
`66a7dc08884fb08a4bb96ec282d71fd6222a39e9` removes the pointer-returning batch
API and introduces opaque `OutputPacket` handles. Every output length,
segment-count, segment, token, and submit operation now revalidates owner,
generation, index, and current slot access. Successfully returning a non-empty
view/iterator slice or raw output segment/token records a generation-local
barrier; `DispositionWriter.retain` then returns `OutstandingBorrow` before
changing token, disposition, lease state, or batch access. `PacketView.read`
copies and does not set the barrier.

The deterministic alias test pre-mints the output handle before retention and
checks every operation after retain, completion, invalidation, and
same-owner/index reuse. The raw-authority test independently covers contiguous
slices, iterator slices, output token authority, output segment slices,
unchanged failed-retain dispositions/tokens/access, and successful retention
after copy-only `read`. The audited generation-bound raw-return surface is
limited to those four paths; adapter-owned `PacketSlot` access remains the
trusted assembly boundary and synthetic `OutputQueue.borrowedSegment` observes
already accepted output ownership.

The focused commands passed in Debug, ReleaseSafe, ReleaseFast, and ReleaseSafe
Linux AArch64, along with authored docs/links, M1 coverage and negative
controls, M1/M2 version provenance, M2 coverage, retained-evidence validation,
benchmark validation, and schemas. Commit
`05eb395c91902e41961f7164c18d9a50a5f37d7f` also corrects the remaining
same-class M1-guide command to the independently invocable cumulative
`zig build ci-m1` gate. Both canonical bounded AFL++ summaries and the
30-sample ReleaseFast cycle artifact were regenerated from that clean commit
and tree `1e16b2e823b6bfb86afb0bc33ac10fef4be4675c`, then retained by commit
`cc2c6942f2aa012330918714593d7c5cb3f9e27a`. Successor `final_reviewer`
closed `M2-FINAL-001` at committed tip `1e6bf0e` and tree `fd6afdb` after all
three x86 modes, ReleaseSafe Linux AArch64, retained validators, and the full
corrective audit. Successor `exit_explorer` closed `M2-EXIT-001` at the same
tip/tree after the pinned documentation check, nearby public gate/API audit,
diff check, and status inspection. This closure checkpoint is not the fresh
post-High full-diff review or final exact-tree gate.

The coverage validators report 24 exact cumulative claims: the preserved 11
M1 claims remain attributed to `0.1.0-m1`, and 13 M2 claims use `0.2.0-m2`.
The unit suite includes SeededTrace selection-versus-`u64` oracle properties
and forged indices, a 48-case all-disposition reference model, packet-bound
retention and bounded lease exhaustion/leak behavior, output-capability
negative cases,
the disposition direct-field API-surface audit and owner/batch-generation
handle rejection cases,
structured/raw mutation boundaries, allocation-failure cleanup, cross-segment
edits, failure-atomic resize/mutation/finalizer paths, odd payload trims, padded
split packets, and exhaustive proper-prefix truncation fixtures for VLAN, IPv4
options, IPv6 extensions, TCP, UDP, and ICMP headers.

## Differential and fuzz evidence

The pinned Scapy 2.7.0 differential passed base IPv4 UDP/TCP and IPv6 UDP,
odd-payload IPv6 TCP, VLAN IPv4 UDP, IPv4-options TCP, IPv6 hop-by-hop UDP,
padded IPv4 UDP, IPv4/IPv6 UDP-zero, and initial and non-initial IPv4/IPv6
fragment fixtures. Applicable cases compare decoded fields and exact finalized
bytes, covering declared lengths, checksums, intended changed headers, padding,
and unchanged payload bytes.

Both bounded AFL++ smoke workflows passed deterministic corpus replay,
`afl-showmap`, a 500 ms per-execution timeout, a two-second campaign, and the
Zig-owned deliberate semantic negative control with exact outcome 6 and no
saved crash or timeout. Finalizer failure preserves the immediate
pre-finalization bytes and remains output-ineligible; successful mutation
finalization is independently checked for declared IPv4/IPv6 and UDP/TCP
lengths plus applicable IPv4 and transport checksums. Retained
machine-readable summaries under `evidence/m2/` bind clean source commit
`05eb395c91902e41961f7164c18d9a50a5f37d7f` and tree
`1e16b2e823b6bfb86afb0bc33ac10fef4be4675c`, AFL++ version,
source/dictionary/seed hashes, settings, results,
and failure workflow. Volatile discovery counts are intentionally not claimed.

## Synthetic benchmark baseline

Command:

```sh
nix develop --command zig build -Doptimize=ReleaseFast m2-bench
```

Result: pass. The schema-validated artifact
`bench/examples/benchmark.m2.json` records the first host-local serialized
RDTSCP parser/no-op-disposition cycle baseline for batches 1/4/8/16/32/64. It
retains a distinct warmup and five raw samples plus medians for every batch,
bound to clean source commit `05eb395c91902e41961f7164c18d9a50a5f37d7f`,
tree `1e16b2e823b6bfb86afb0bc33ac10fef4be4675c`, environment, fixture,
benchmark sources/settings, host observation, and raw-output hash. The command
runs fresh samples and independently validates the retained artifact. This
baseline is informational regression evidence only; it is neither a production
throughput result nor a capacity promise.

## Independent exact-tree acceptance gate

After all sixteen findings closed and the mandatory post-High fresh full-diff
review was accepted, the independent verifier bound the clean committed
non-WIP milestone tip
`bf76210a318f15f6ab71e6ffcf1a20f1c0bc9277` and tree
`b2609e0020b8a33147ee19e563c7f159039c0beb`. The verifier ran:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop --command zig build ci
git diff --check 60f920b3aa6d2f5571d2176959379bcf426ac3a5..HEAD
git status --short
git status --ignored --short
```

Result: pass. Both immutable specification manifests verified. The cumulative
M2 hardware-free `zig build ci` completed in 30.0 seconds and reported
`complete cumulative M2 hardware-free CI gate passed`. The baseline-to-tip
diff check passed. Commit and tree IDs were unchanged before and after the
gate; ordinary status remained clean, and ignored status remained limited to
`.zig-cache/`, `tools/m1/__pycache__/`, `tools/m2/__pycache__/`, and
`zig-out/`.

The first sandboxed Nix invocation could not acquire its fetcher-cache lock.
The identical command was rerun with narrowly scoped sandbox approval and
passed; no repository file, gate input, commit, tree, or status changed during
that rerun. Main accepted this independent evidence as the final M2 gate. This
acceptance-only wording does not alter a gate input and therefore requires only
focused documentation, schema, coverage, version, register, and diff checks.

## Limitations

- Evidence is synthetic/virtual and local; it makes no physical-NIC or
  production-capacity claim.
- AFL++ smoke campaigns are bounded regression checks, not exhaustive proofs.
- Scapy differential coverage uses a bounded deterministic protocol matrix;
  broader malformed and segmentation cases are covered by Zig unit/property
  tests and fuzzing.
- The cycle artifact is host-local and expected to vary across machines; it is
  the first comparable M2 baseline, so no cross-version delta is claimed.
- M0-H remains deferred and mandatory before M4. M3 work has not started and
  is the next predecessor-gated milestone.
- All sixteen findings are closed, and the retained fuzz/benchmark artifacts
  are refreshed. The accepted gate remains synthetic/virtual and does not
  change the physical-NIC or production-capacity limitations above.
