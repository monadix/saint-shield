# M3 verification evidence

Date: 2026-08-23

Scope: hardware-free native processor contract, static pipeline, public
synthetic harness, deterministic example, and host-local dispatch regression

Status: Complete. All review findings through M3-GATE-001 are closed, the
exact-context authority-return inventory is acknowledged, the current-source
retained benchmark passes, the independent final exact-tree retry passed, and
the main session accepted M3 at exact gate tip/tree `9c008e5`/`18d2c7d`.
Post-acceptance M3-INTEGRATION-001 is addressed pending independent closure;
local squash integration is incomplete.

Environment label: synthetic/virtual regression only; no production-capacity
claim

## Writer startup preflight

Before creating `milestone/m3`, the writer verified:

- local `main` and `HEAD` were exactly
  `8da41e27b385fd07f703a9f03c2de2ae38b0e696`;
- `milestone/m3` did not exist;
- ordinary tracked/untracked status was clean;
- ignored status contained only `.zig-cache/`, `zig-out/`,
  `tools/m1/__pycache__/`, and `tools/m2/__pycache__/`;
- both immutable specification manifests passed;
- baseline `nix develop --command zig build ci` passed in 30.0 seconds after a
  sandbox-only Nix fetcher-lock failure was retried with scoped authorization.

This is writer preflight evidence. It is not independent review, milestone
acceptance, or the final exact-tree gate.

## Implemented contract

- `ProcessorDescriptor` records stable processor/API identity, packet access,
  dispositions/outputs, artifacts, typed metadata, services, bounded work,
  exact processing errors and policy, update modes/default, and resource
  categories. Twenty-eight compile-fail fixtures cover missing, duplicate,
  invalid, type/signature-inconsistent, and unavailable public authority
  declarations.
- Generated call-scoped contexts store only an opaque cookie and expose only
  declared copies, value metadata, structured/raw actions, dispositions, and
  outputs. They do not return an owner, token, handle, pointer, slice, writer,
  or retained borrow.
- Assembly validates application capabilities and checked aggregate estimates,
  including worker multiplication and overflow, before the first `prepare`.
  Address-stable counted allocators enforce declared prepared/worker limits.
- Prepared and worker tuples construct in application order and clean partial
  or complete prefixes in exact reverse order. Allocation-failure sweeps return
  live accounting to zero.
- Static execution performs one direct call per non-empty stage, removes prior
  terminal packets from later selections, preserves prior terminal outcomes,
  applies only explicit error policies, and resolves remaining `Continue`
  packets only through the caller policy.
- Typed metadata uses a fixed compile-time layout, inline bounded values, and
  one validity selection per key. The packet path performs no allocation.
- `ProcessorTestHarness` owns one prepared generation and worker over public
  synthetic queues. Results own copied final bytes and expose dispositions,
  trace, completion, cleanup, and resource accounting. Failure paths reconcile
  every received token.
- The deterministic example composes metadata production/read, worker-local
  filtering, mixed dispositions, and final acceptance. Its result is four
  packets, two accepted, and two dropped.

## Requirement and semantic evidence

The cumulative coverage validator accepts 51 exact claims: 11 M1 claims retain
`0.1.0-m1`, 13 M2 claims retain `0.2.0-m2`, and 27 M3 claims use
`0.3.0-m3`. The M3 set covers FR-COMP-001..003/005..006,
FR-PROC-001..009, FR-EXT-001..003, FR-PKT-014/015, FR-STATE-001/004,
FR-TEST-001, INV-RES-001/002, AC-003/012, and PERF-CORE-001.

Twenty-one dedicated M3 runtime scenarios pass in Debug, ReleaseSafe, and
ReleaseFast. They cover these eight contract groups:

1. exact limits, one-byte excess, overflow, worker multiplication, and
   runtime underestimation;
2. capability rejection before preparation;
3. partial prepared/worker reverse cleanup;
4. allocation-failure sweeps with zero residual bytes;
5. AC-003 ordering, mixed outcomes, and empty-selection short-circuiting;
6. every explicit error policy, prior-terminal preservation, and stop behavior;
7. partial typed metadata validity, fixed scratch, and zero hot allocation;
8. fixed-seed tiny direct pipelines against a simple reference model.

The external contract suite compiles one legitimate static pipeline and rejects
28 invalid/public-authority cases. The example and a concrete ReleaseSafe Linux
AArch64 pipeline compile pass. AArch64 is build-tested only.

## Retained benchmark evidence

After `m3_api_review` closed M3-FINAL-001 and acknowledged the exact-context
authority inventory at source `1dd66147c8102de034bb4f9ee9930c05db973aec`,
tree `11d25fb9d49beee8fc2c0df73503c59536087f8c`, the reviewer-authorized
controller ran once nonselectively and retained the current artifact.
`bench/examples/benchmark.m3.json` has SHA-256
`6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`
and raw-output SHA-256
`2d154b742be0943c9c6fd7e60eedd4a9e0a1863cee6bdef08dd191b1d267e553`.
Its generation digest is
`9ab13989b8da1098ad4f555e07592038126eb324b7817497a8ab9d7b8f817278`.
It binds source commit
`332aa4483d859e28976016da8c6c7990581add48`, tree
`11663183dd90abb65cd4e2b964b0e76f9c2c963a`; the runtime, build, tooling,
schema, and authority source remained identical to the acknowledged source,
with only the evidence closure record added. The artifact was committed alone
by `0613106d444c3568e7c5667e25400626b62ffc98`, tree
`93a2bb8874eccd6d34157d1b1bc0a316da9b9734`, before cumulative CI.

The run used seven independently launched warmed ReleaseFast processes, five
samples per run, and 35 retained samples for every direct 0/1/2/4/8, terminal,
monolith, and batch-vtable variant at batches 32 and 64. It ran on an
uncontrolled host-local Intel Xeon E5-2666 v3, x86_64 Linux 6.18.44, using
`CLOCK_MONOTONIC_RAW` and serialized RDTSCP. Complete order permutations, raw
elapsed/cycle arithmetic, all per-run and combined statistics, commit/tree,
source/environment/generation hashes, schema, and thresholds were recomputed.

PERF-CORE-001 passes:

| Batch | Direct-4/direct-0 packet-rate ratio | Gate |
| ---: | ---: | --- |
| 32 | 0.994024 | pass (`>= 0.95`) |
| 64 | 0.998583 | pass (`>= 0.95`) |

Retained direct-path dispersion:

| Batch | Variant | Packet-rate median | Packet-rate population stdev | Cycles/packet median | Cycles/packet population stdev |
| ---: | --- | ---: | ---: | ---: | ---: |
| 32 | direct0 | 1,206,151.698 | 56,417.796 | 2,404.307 | 128.637 |
| 32 | direct4 | 1,198,943.663 | 55,038.627 | 2,418.763 | 127.237 |
| 64 | direct0 | 1,992,397.168 | 38,819.739 | 1,455.515 | 28.735 |
| 64 | direct4 | 1,989,574.072 | 34,449.777 | 1,457.562 | 25.456 |

This host-local synthetic result is regression evidence only. The monolith and
batch-vtable are not product executors and omit portions of the production
context/authentication/accounting path. Their retained measurements are
non-comparable diagnostic-only data and cannot contribute to PERF-CORE-001 or
an architecture decision.

## Cumulative gate compatibility

The M1 and M2 coverage/version checks preserve exactly their historical claim
sets under current version `0.3.0-m3`. M2 retained fuzz and benchmark evidence
crosses the canonical squash through fixed anchors: source commit `05eb395` is
required to be in the exact accepted pre-squash history ending at
`bf76210`/`b2609e0`, while `aaa406a`/`a0b8d91` is required to be an ancestor of
current `HEAD`. Every artifact record is hashed from both its source object and
the accepted squash anchor. Current hashes remain mandatory for every M2 fuzz
path and the M2 benchmark implementation/C path; only cumulative `build.zig`
and the validator's self-bound path may evolve. Negative controls reject the
post-squash M3 tip as an unrelated artifact source.

## Writer checks

### Post-M3-FINAL-001 acknowledged-source artifact and cumulative writer gate

The discovering reviewer `m3_api_review` closed M3-FINAL-001 and acknowledged
the complete exact-context authority-return inventory at clean source
`1dd66147c8102de034bb4f9ee9930c05db973aec`/tree
`11d25fb9d49beee8fc2c0df73503c59536087f8c`, with no additional material
finding. The closure and acknowledgment were recorded alone by
`332aa4483d859e28976016da8c6c7990581add48`/tree
`11663183dd90abb65cd4e2b964b0e76f9c2c963a`. No source, tool, build, schema,
or authority surface changed after acknowledgment.

From that clean committed tree, the reviewed controller ran once
nonselectively:

```sh
nix develop --command python3 tools/m3/benchmark-gate.py \
  --retain bench/examples/benchmark.m3.json
```

It passed seven independently launched warmed runs, five samples per run, 35
samples per variant, complete raw/source/generation/commit/tree binding,
schema and arithmetic recomputation, and PERF-CORE-001 at both required batch
sizes. The retained ratios and dispersion are recorded above. Artifact-only
commit `0613106d444c3568e7c5667e25400626b62ffc98`, tree
`93a2bb8874eccd6d34157d1b1bc0a316da9b9734`, contains only
`bench/examples/benchmark.m3.json`.

The committed artifact then passed:

```sh
nix develop --command zig build schemas
nix develop --command zig build m3-bench-evidence
nix develop --command zig build m3-bench-evidence-self-test
time -p nix develop --command zig build ci
```

Schemas, retained evidence, and all ten validator negative controls passed.
The cumulative hardware-free M3 gate passed in 463.24 seconds (`user 488.21`,
`sys 27.69`). It reproduced both immutable manifests; cumulative M0-V, M1,
and M2 gates; Debug, ReleaseSafe, and ReleaseFast root/M3 semantics; one valid
external pipeline plus 28 compile failures; the deterministic example;
ReleaseSafe Linux AArch64; 51-claim coverage; version, schemas, retained
evidence, and docs. Its independent seven-launch performance gate passed at
direct4/direct0 ratios `0.998523` for batch 32 and `0.995566` for batch 64.
This is writer evidence, not the mandatory final fresh full-diff review,
independent exact-tree verification, or main-session acceptance.

### Post-M3-FRESH2 acknowledged-source artifact and cumulative writer gate

The discovering reviewer `m3_resource_review` closed M3-FRESH2-001 and
acknowledged the complete renewed authority-return inventory at exact clean
source commit `8828ab7460e8bddfd389692d090496b8d6da8f3d`, tree
`ad390d93d8fd0af7dec1e8058d5387d5bf46a3d1`. The evidence-only closure and
acknowledgment commit is `075b3f7438057ce86d525fd0f78af093ce9af4fe`,
tree `204d23d231a59bd08f9c9cc95e0cc5156795aea6`. No runtime, tool, build,
schema, or authority surface changed between those trees.

At the clean evidence commit, the writer ran the reviewed controller once and
retained its result:

```sh
nix develop --command python3 tools/m3/benchmark-gate.py \
  --retain bench/examples/benchmark.m3.json
```

It passed seven independently launched warmed ReleaseFast runs, five samples
per run, 35 samples per variant, and PERF-CORE-001 at both required batch
sizes. The current artifact details and dispersion are recorded above. The
artifact-only commit is `53b6c63e3c2c8703f06a783bf24be060035fc42d`,
tree `15f575b232afe9a62a2adf419a26763b85d1c2db`.

The following current-artifact checks then passed at that clean commit/tree:

```sh
nix develop --command zig build schemas m3-bench-evidence \
  m3-bench-evidence-self-test
nix develop --command zig build ci
```

The focused checks reported canonical schemas, retained-evidence
authentication/recomputation, and all ten forged-artifact negative controls
passing. The cumulative gate completed in approximately 399 seconds of
tool-observed wall time and reported
`complete cumulative M3 hardware-free CI gate passed`. Its independent fresh
seven-launch sample passed with direct4/direct0 ratios `0.996907` at batch 32
and `0.997095` at batch 64. It also passed both immutable specification
manifests and all M0-V, M1, M2, and M3 hardware-free checks, including
three-mode root/M3 semantics, one legitimate external pipeline plus 27 compile
failures, the four-packet example, ReleaseSafe Linux AArch64, 51-claim
coverage, version consistency, schemas, docs, retained artifacts,
fuzz/differential evidence, and virtual DPDK checks.

The first sandboxed documentation precheck hit the known read-only Nix
fetcher-lock condition; the narrowly authorized retry passed without changing
repository state. This section is writer evidence, not the mandatory fresh
full-diff review, independent final exact-tree gate, or main-session
acceptance.

### Post-High source-only remediation checkpoint

M3-FRESH-001/002 were addressed without regenerating or validating the retained
artifact and without running `m3-bench-gate`, `schemas`, cumulative `ci`, an
acceptance gate, integration, or remote mutation. Both immutable specification
manifests passed. Root and M3 semantics passed in Debug, ReleaseSafe, and
ReleaseFast; `m3-test` now includes the benchmark constructor allocation sweep.
The following source-only checks passed:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256

nix develop --command zig build test -Doptimize=Debug
nix develop --command zig build m3-test -Doptimize=Debug
nix develop --command zig build test -Doptimize=ReleaseSafe
nix develop --command zig build m3-test -Doptimize=ReleaseSafe
nix develop --command zig build test -Doptimize=ReleaseFast
nix develop --command zig build m3-test -Doptimize=ReleaseFast
nix develop --command zig build m3-compile-fail
nix develop --command zig build m3-example -Doptimize=Debug
nix develop --command zig build m3-example -Doptimize=ReleaseSafe
nix develop --command zig build m3-example -Doptimize=ReleaseFast
nix develop --command zig build m3-cross-aarch64
nix develop --command zig build m3-bench-compile -Doptimize=ReleaseFast
nix develop --command zig build fmt-check
nix develop --command zig build docs
nix develop --command zig build docs-check
nix develop --command zig build m3-coverage
nix develop --command zig build m3-version-consistency
git diff --check
```

The compile-fail gate reported one legitimate external pipeline plus 27
expected failures; the example reported four packets, two accepted and two
dropped in every mode; coverage retained 51 exact cumulative claims and version
remained `0.3.0-m3` with M1/M2 provenance preserved. The benchmark binary was
compiled only: no timing sample was executed.

The first sandboxed Nix invocation hit the known read-only fetcher-lock cache
and was rerun with narrow approval. The first Debug M3 run then exposed an
existing test fixture that configured `output_id` without declaring it in
application capabilities; all three fixture construction paths were corrected
and the exact suite passed. A manual direct Zig+C benchmark-test invocation had
invalid CLI ownership (`C source file ... has no parent module`); it changed no
source result, and the benchmark test then passed without C because timing
externs are unreachable in tests. Canonical `m3-bench-compile` now proves the
actual C-linked benchmark binary without execution.

At that source-only checkpoint, the retained artifact remained byte-for-byte
unchanged at SHA-256
`630b7434ed89b6cce70425214f0f8774caa97bacf0f65029b46ac103d63a9941` and
bound prior acknowledged source `978cf09`/`5d98a71`; it was stale for the fresh
source remediation. M3-FRESH-001/002 remained addressed pending exact
discoverer re-audit, including acknowledgment of the renewed authority-return
inventory. The later final checkpoint below supersedes that pending state.

### Final acknowledged-source artifact and cumulative writer gate

`m3_api_review` closed M3-FRESH-001/002 and acknowledged the complete renewed
authority-return inventory at exact clean source commit
`1839df61e63530ce30a1554a8a1c895f25932ce5`, tree
`8c367eacabe8e1b7f218a2fa1cad19613cce004a`. No source, tool, build, schema, or
authority surface changed after that acknowledgment. The reviewed controller
then ran nonselectively:

```sh
nix develop --command python3 tools/m3/benchmark-gate.py \
  --retain bench/examples/benchmark.m3.json
```

It passed seven independently launched warmed runs with five samples per run,
35 samples per variant, and the `>= 0.95` threshold at both required batch
sizes. The retained artifact details and dispersion are recorded above. The
artifact-only commit is `ea052dc3eb2f965c4d37e76b6dfa01f728de4691`, tree
`1f080fe53276dc91f43926c80b8a6835f4b42b5d`; it contains only
`bench/examples/benchmark.m3.json`.

The following current-artifact gates then passed:

```sh
nix develop --command zig build schemas
nix develop --command zig build m3-bench-evidence
nix develop --command zig build m3-bench-evidence-self-test
```

They reported canonical benchmark/environment schema success, retained M3
evidence success, and all ten benchmark-validator negative controls passing.
At the same clean artifact commit and tree, the cumulative writer gate ran:

```sh
time -p nix develop --command zig build ci
```

It reported `complete cumulative M3 hardware-free CI gate passed` in 466.66
seconds (`user 490.39`, `sys 27.69`). Its independently generated fresh M3
controller sample passed with direct4/direct0 ratios `0.993155` at batch 32 and
`0.988615` at batch 64. The cumulative gate also passed both immutable
specification manifests and all M0-V, M1, M2, and M3 hardware-free checks,
including three-mode semantics, the legitimate external pipeline plus 27
compile failures, the four-packet example, ReleaseSafe Linux AArch64,
51-claim coverage, version consistency, schemas, docs, retained artifacts,
fuzz/differential evidence, and virtual DPDK checks.

An initial controller invocation outside the Nix environment stopped before
artifact generation because `zig` was unavailable. A first timing wrapper also
stopped before CI because `/usr/bin/time` was unavailable; the shell timing
form above then passed. Neither command-context failure changed the tree or
required a source/tool/build/schema/authority change. This entire section is
writer evidence, not the reserved mandatory fresh full-diff review,
independent final exact-tree gate, or main-session acceptance.

### Renewed post-acknowledgment artifact and cumulative gate

Both original reviewers acknowledged the authority-return inventory at source
`978cf0937ab6cf93a060b5a18866c17260542e90`/tree
`5d98a718451d516c2894aaf845265d1d1fda3acd`. The reviewed retained capture above
passed, followed by canonical schemas, retained-evidence validation, and ten
validator negative controls. The artifact-only commit restored the clean-tree
precondition, then:

```sh
nix develop --command zig build ci
```

passed in 478 seconds. It completed the M0-V, M1, and M2 predecessor gates;
Debug, ReleaseSafe, and ReleaseFast root and M3 semantics; one legitimate
external pipeline plus 27 compile failures; example, ReleaseSafe AArch64,
coverage/version, schemas, and docs; retained M3 evidence; and its own fresh
seven-launch gate. The cumulative fresh gate reported direct4/direct0 ratios
`1.007751` at batch 32 and `0.996709` at batch 64. This is writer evidence, not
the reserved independent final exact-tree gate or main-session acceptance.

### Second critical remediation checkpoint

The first remediation inventory was not acknowledged. The writer internalized
invocation/capability installation, replaced pointer-bearing worker handles,
expanded allocation and benchmark-validator adversarial coverage, classified
incomparable controls, revised the inventory, and recorded the supplied finding
closures. Focused source-only checks passed without running the retained
artifact schema gate, fresh benchmark gate, cumulative CI, or integration:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop --command zig build m3-test -Doptimize=Debug
nix develop --command zig build m3-test -Doptimize=ReleaseSafe
nix develop --command zig build m3-test -Doptimize=ReleaseFast
nix develop --command zig build m3-compile-fail
nix develop --command zig build m3-example -Doptimize=Debug
nix develop --command zig build m3-cross-aarch64
nix develop --command zig build m3-coverage m3-version-consistency \
  docs-check fmt-check
nix develop --command zig build m3-bench-evidence-self-test
nix develop --command check-jsonschema --check-metaschema \
  bench/schemas/m3-benchmark-result.schema.json
nix develop --command zig build-obj -OReleaseFast --dep saint_shield \
  -Mroot=bench/micro/m3_static_pipeline.zig \
  -Msaint_shield=src/root.zig -femit-bin=/tmp/saint-shield-m3-bench.o
python3 -m py_compile tools/m3/benchmark-evidence.py \
  tools/m3/benchmark-gate.py tools/m3/compile-fail.py
sh -n tools/m0/validate-schemas.sh tools/m3/ci.sh
git diff --check
```

Results include 16 M3 runtime scenarios in all three modes, one legitimate
external static-pipeline compile plus 27 external compile failures, the
four-packet deterministic example, ReleaseSafe Linux AArch64, 51 exact
cumulative coverage claims, version/docs/format checks, ten benchmark-validator
negative controls, M3 schema metaschema validation, and a ReleaseFast
benchmark-source compile without execution. The validator rejects duplicate
orders and raw elapsed/cycle arithmetic inconsistencies and requires controls
to remain non-comparable diagnostic-only data excluded from acceptance and
architecture decisions.

The first combined coverage/docs rerun found one stale coverage reference to a
removed internal-capability mutation test and one misplaced public declaration
doc comment. Both source-only issues were corrected; the exact focused command
then passed. The retained artifact remains byte-for-byte unchanged at SHA-256
`683756bcd290a1a05ba2c2cf763333928480123854a1078b07e288b55f3c4287`.
At that checkpoint the revised inventory was not yet acknowledged. The renewed
acknowledgments and current evidence are recorded in the later section above.

### First critical remediation checkpoint

The writer recorded all 18 independent findings and the complete mandatory
authority-return inventory in `evidence/m3/REVIEW.md`. Focused remediation
checks passed without running the retained benchmark, refreshing its artifact,
running `schemas`, or running cumulative CI:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop -c zig build m3-test -Doptimize=Debug
nix develop -c zig build m3-test -Doptimize=ReleaseSafe
nix develop -c zig build m3-test -Doptimize=ReleaseFast
nix develop -c zig build m3-compile-fail
nix develop -c zig build m3-example -Doptimize=Debug
nix develop -c zig build m3-cross-aarch64
nix develop -c zig build m3-coverage m3-version-consistency docs-check fmt-check
nix develop -c zig build m3-bench-evidence-self-test
nix develop -c check-jsonschema --check-metaschema \
  bench/schemas/m3-benchmark-result.schema.json
nix develop -c zig build-obj -OReleaseFast --dep saint_shield \
  -Mroot=bench/micro/m3_static_pipeline.zig \
  -Msaint_shield=src/root.zig -femit-bin=/tmp/saint-shield-m3-bench.o
python3 -m py_compile tools/m3/benchmark-evidence.py \
  tools/m3/benchmark-gate.py tools/m3/compile-fail.py
sh -n tools/m0/validate-schemas.sh tools/m3/ci.sh
git diff --check
```

Results include 17 M3 runtime scenarios in all three modes, 25 compile-fail
cases, the four-packet deterministic example, ReleaseSafe Linux AArch64,
51 exact cumulative coverage claims, version/docs/format checks, seven
benchmark-validator negative controls, M3 schema metaschema validation, and a
ReleaseFast benchmark-source compile without execution. The Nix evaluation
cache occasionally reported a concurrent SQLite `busy` warning during parallel
focused checks; every affected command completed successfully.

The next allowed action is independent inventory audit and acknowledgment. Only
after acknowledgment may the writer refresh `bench/examples/benchmark.m3.json`
with seven independently launched warmed runs and run the cumulative gate.

### Initial implementation checkpoint

Focused commands passed:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop --command zig build fmt-check docs-check m3-coverage \
  m3-version-consistency m3-compile-fail m3-test m3-example m3-cross-aarch64
nix develop --command zig build schemas m3-bench-evidence
python3 tools/m1/validate-coverage.py
python3 tools/m1/validate-coverage.py --self-test
python3 tools/m2/validate-coverage.py
python3 tools/m2/validate-fuzz-evidence.py
python3 tools/m2/benchmark-evidence.py
python3 tools/m3/validate-coverage.py
python3 tools/m3/benchmark-evidence.py
```

The complete cumulative writer preflight also passed:

```sh
nix develop --command zig build ci
```

It reported `complete cumulative M3 hardware-free CI gate passed` after the
full M0-V, M1, and M2 predecessor gates; Debug, ReleaseSafe, and ReleaseFast
root and M3 semantics; all compile-fail/example/cross/coverage/version checks;
a fresh ReleaseFast M3 benchmark execution; retained M3 evidence; schemas; and
authored documentation/link checks. The retained artifact bytes used by that
preflight are the artifact committed by this writer. This remains writer
evidence, not the required independent final exact-tree gate.

## Accepted independent final exact-tree gate

After the mandatory fresh full-diff review reported no additional material
finding, `m3_final_gate` ran the independent exact-tree retry at committed
non-WIP tip `9c008e59243d148bcf4f85efcf8fd20f8d6ea4af`, tree
`18d2c7d4246775e69573c2ed98c6824038d7b7cd`. The verification window began at
epoch `1787434127`; the unchanged-tree/status capture completed at epoch
`1787434187`.

The retry passed:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop --command zig build ci
git diff --check 8da41e27b385fd07f703a9f03c2de2ae38b0e696..HEAD
```

Both immutable manifests passed. Canonical cumulative CI completed
successfully and reported all hardware-free M0-V through M3 checks passed. The
baseline-to-tip diff check passed; commit and tree remained exactly
`9c008e59243d148bcf4f85efcf8fd20f8d6ea4af`/
`18d2c7d4246775e69573c2ed98c6824038d7b7cd`; ordinary status remained clean.
Ignored status was limited to `.zig-cache/`, `zig-out/`, and the M1/M2/M3
Python bytecode caches.

The accepted retained artifact remained byte-for-byte SHA-256
`6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`,
with seven independent runs, 35 samples per variant, and direct4/direct0 ratios
`0.994024` at batch 32 and `0.998583` at batch 64. The known environment-only
Nix fetcher-lock friction required narrowly scoped execution outside the
read-only sandbox cache; it changed no tracked state and was not a project or
gate failure.

The first verifier attempt and its exact extra `--retain` mutation remain
preserved as M3-GATE-001. After authorized byte-for-byte recovery and an
evidence-only incident commit, the discovering verifier closed M3-GATE-001 on
the clean retry above. The main session accepted this exact independent gate
and marked M3 complete. The acceptance-only record changes no product, tool,
build, schema, artifact, specification, or authority input and therefore does
not require another full gate.

## Post-integration gate failure and squash-bridge checkpoint

The authorized local squash produced `main` commit
`e140ed246a3ba71a6a606442589a3e654b659aed`, tree
`481e1e226989ab51268d7774d8395708918791f9`, exactly equal to retained
pre-squash branch tip/tree
`f07ab6ed5154e224785a8913f6c8a22bfa384111`/`481e1e226989ab51268d7774d8395708918791f9`.
Both immutable manifests passed. The post-integration canonical
`nix develop --command zig build ci` ran for approximately 413 seconds and
passed every cumulative M0-V through M3 check through the fresh M3 benchmark.
The fresh direct4/direct0 packet-rate ratios passed PERF-CORE-001 at `0.996402`
for batch 32 and `1.001114` for batch 64. The gate then failed retained M3
evidence because historical artifact source `332aa4483d859e28976016da8c6c7990581add48`
was no longer an ancestor of squash-history `HEAD`. The accepted retained
artifact did not change and remains SHA-256
`6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`.
This failed post-integration attempt remains failed; it is not evidence of a
completed local integration and does not revoke the earlier accepted M3 gate.

At main-session direction, the sole writer resumed retained `milestone/m3` to
address M3-INTEGRATION-001 without regenerating the artifact. Fresh generation
now uses a strict exact-current-HEAD mode. Retained validation uses a separate
fixed squash bridge that proves exact artifact-source, final-gate, pre-squash,
and squash anchors; source-to-gate-to-pre-squash ancestry; pre-squash/squash
tree identity; exactly one accepted branch or integrated-main topology; and
historical/pre-squash/squash blob equality for every recorded source. Current
worktree equality remains mandatory for the environment and every source
except the sole evolved validator path `tools/m3/benchmark-evidence.py`;
`build.zig` is not exempt. The self-test covers both positive topology modes
and rejects forged topology, source, validator-self-path, and statistical
evidence.

The focused addressing checkpoint passed:

```sh
nix develop --command zig build m3-bench-evidence \
  m3-bench-evidence-self-test schemas m3-coverage \
  m3-version-consistency docs-check
nix develop --command python3 -m py_compile tools/m3/benchmark-evidence.py
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
git diff --check
```

Retained validation passed on the branch topology. The self-test passed
fresh-current-HEAD and retained branch/integrated positive controls and 15
negative controls. Schemas, 51-claim cumulative coverage, version consistency,
authored documentation and 33 local links, Python compilation, both immutable
manifests, and diff checks passed. The initial sandboxed Nix attempt hit the
known user-cache fetcher-lock read-only error; the same focused command passed
with narrowly scoped execution outside that cache restriction. This checkpoint
does not run cumulative CI, retry integration, close the finding, or authorize
branch deletion.

## Findings and limitations

- All original API, resource, performance, M3-FRESH-001/002, M3-FRESH2-001,
  M3-FINAL-001, and M3-GATE-001 findings are closed by their discovering
  reviewers/verifier. Post-acceptance M3-INTEGRATION-001 is addressed pending
  independent closure.
  `m3_api_review` acknowledged the exact-context authority-return inventory at
  exact corrected source commit/tree `1dd6614`/`11d25fb`.
- Evidence is synthetic/virtual and host-local. It makes no physical-NIC,
  production-throughput, or production-capacity claim.
- The benchmark host is uncontrolled; cycle/rate dispersion is retained, and
  only the accepted ratio regression is claimed.
- AArch64 is ReleaseSafe build-tested only. M0-H remains deferred and mandatory
  before M4 acceptance.
- M3 records update-state, metric, and event schemas but implements no live
  publication, QSBR, metrics/event runtime, dynamic plugins, reusable state
  runtime, sources, production adapters, or policy executor.
- The current-source retained artifact, mandatory fresh full-diff review,
  independent final clean committed exact-tree verification, and main-session
  acceptance pass. The first local squash is tree-identical but its
  post-integration gate failed at the pre-bridge retained ancestry check;
  integration remains incomplete pending M3-INTEGRATION-001 closure,
  re-integration, and a full post-integration gate. M0-H remains mandatory
  before M4 can begin.
