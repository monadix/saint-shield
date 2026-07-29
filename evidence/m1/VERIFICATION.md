# M1 verification evidence

Date: 2026-07-29  
Scope: hardware-free foundation, ownership, views, synthetic I/O, and PCAP only  
Status: accepted and complete  
Environment label: synthetic/virtual regression only; no production capacity claim

## Complete cumulative gate

Command:

```sh
nix develop --command zig build ci
```

Result: pass. `tools/m1/ci.sh` first ran the independently invocable M0-V
predecessor gate and then the M1 additions. The cumulative result included:

- isolated-cache Debug, ReleaseSafe, and ReleaseFast x86-64 builds and tests;
- ReleaseSafe Linux AArch64 public-library cross-build;
- exact flake/dependency/archive/license integrity and DPDK 25.11.2 virtual
  no-huge lifecycle checks;
- M0-V and bounded classic-PCAP AFL++ workflows;
- canonical M1 requirement-map validation, validator negative self-tests, and
  exact package/API/coverage version consistency;
- the ReleaseFast M1 synthetic traversal regression;
- benchmark/environment schema checks;
- Zig formatting, generated docs, public-declaration docs, strict MkDocs, the
  example, and local link validation.

The final line was `complete cumulative M1 hardware-free CI gate passed`.
The immutable technical-plan and source-requirement manifests also passed
direct `sha256sum -c MANIFEST.sha256` checks before implementation.

## Independent acceptance

The final independent core ownership review examined the fully remediated
owner-bound handle, iterator, ownership, and PERF evidence and reported no
blocking findings. The independent gate verifier then reproduced:

```sh
cd planning/specification/l4-protection-framework-technical-plan
sha256sum -c MANIFEST.sha256
cd source-requirements
sha256sum -c MANIFEST.sha256
cd ../../../..
nix develop --command zig build ci
git diff --check
```

Both immutable manifests passed. The exact cumulative CI command ended with
`complete cumulative M1 hardware-free CI gate passed`, and `git diff --check`
passed. On that independent review and reproduced gate evidence, the main
session accepted M1 on 2026-07-29.

## INV-PKT-001 ownership and failure atomicity

Commands:

```sh
nix develop --command zig build -Doptimize=Debug test
nix develop --command zig build -Doptimize=ReleaseSafe test
nix develop --command zig build -Doptimize=ReleaseFast test
```

Result: pass in all modes.

- An independent token oracle exhausts all `6^5 = 7,776` length-five
  operation sequences through the real `TokenTracker`. After every operation
  it compares the exact state, error, receive count, completion count, and
  shutdown result. Invalid-token, invalid-transition, already-completed,
  missing-completion, output, return, and retention paths are covered.
- A separate queue oracle exhausts all `6^4 = 1,296` four-operation sequences
  over backpressure, output failure, delayed/immediate acceptance, completion,
  and return. It compares real synthetic token state, accepted records, pending
  completion, counters, and shutdown after every operation.
- Synthetic receive preflights the whole requested burst in temporary slots.
  Injected failure at the second slot and receive-sequence overflow both leave
  token states, receive/completion counts, sequence, cursor, and caller slots
  unchanged. Only after all fallible checks pass are tokens transitioned and
  slots published.
- `std.testing.checkAllAllocationFailures` passes for `TokenTracker`,
  `PacketBatchOwner`, synthetic input construction/enqueue, synthetic output
  construction, owned PCAP parsing, and PCAP writing. Each constructor uses
  `errdefer`/`defer` cleanup and returns to the testing allocator baseline.

## INV-PKT-002 lifetime and boundary evidence

`PacketBatchOwner` is an allocator-owned, address-stable owner held across
processing-call frames. `begin` copies bounded slot metadata, never payload,
and advances an internal monotonic generation. Public `PacketBatch` and
`PacketView` values are fieldless pointer-free tags: a batch carries a
process-unique non-pointer owner identity plus its generation, and a view adds
an index. `@intFromEnum` therefore cannot reveal an owner address. Owner
construction assigns identities through a setup-only atomic compare/exchange
loop. Every operation receives the valid opaque owner separately and validates
identity first, then generation/index, before indexing private storage. Ending
either batch alias invalidates the owner-controlled generation once; both
aliases reject length, origin, view, and repeated invalidation access, while
every existing `PacketView` length, metadata, contiguous, read, segments, and
`SegmentIterator.next(owner)` operation reports stale.

The lifetime test returns a view through a separate function after the
processing frame has exited while its owner remains live. It then checks copied
alias invalidation, creates a later generation, and proves the escaped/old
handles remain stale. Generation exhaustion rejects instead of wrapping. A
public type/field audit verifies batch/view enum handles, an opaque owner, and
an iterator with no pointer field. Zero, random, and modified handle tags
constructed with safe `@enumFromInt` calls all return bounded
`BatchReleased`/`StaleView` errors when paired with the valid owner; none can
cause an arbitrary dereference or write. Forging the opaque owner pointer
itself remains unsafe. Destroying the owner while a handle remains reachable
is an explicit caller contract violation.

`SegmentIterator.next(owner)` revalidates its view tag, range, and progress
against private owner state on every call. It recomputes segment offsets from
validated descriptors using checked addition. Tests mutate the view tag, set
range endpoints and progress to `maxInt`, invert the range, and verify bounded
`StaleView`, `Bounds`, or `Overflow` results in Debug, ReleaseSafe, and
ReleaseFast.

Two simultaneously live owners use distinct origins, batch counts, and packet
lengths. The provenance test crosses both owners in both directions through
batch length/origin/view/invalidate, every view accessor, and iterator
advancement. Every operation returns `BatchReleased` or `StaleView`; both
owners retain their original live state and values afterward. Modified
owner-identity bits are rejected identically. The production identity allocator
never reuses a value; a private test invokes the same allocator algorithm with
a local atomic counter, allocates `maxInt(u64)` once, then observes repeated
`OwnerIdentityExhausted` without wrap or production-state mutation.

Boundary tests pass for:

- batch sizes 0 through 64 and explicit size-65 rejection;
- synthetic receive requests 0 through 64 and request-65 rejection;
- segment counts 1 through 16;
- leading, interior, and trailing empty segments;
- every byte range of the fixture through `read`, `contiguous`, and iteration,
  including expected contiguous/non-contiguous outcomes and borrowed pointer
  identity;
- destination-too-small, out-of-bounds, range arithmetic overflow, descriptor
  total mismatch, backing-length mismatch, segment-count excess, and descriptor
  sum overflow;
- strict receive order, caller-frame escape, copied-alias stale behavior,
  later-generation reuse resistance, generation no-wrap behavior, forged
  pointer-free tags, cross-owner provenance, owner-identity no-wrap, and
  adversarial iterator state.

## PCAP fuzz and capture construction

Command:

```sh
nix develop --command zig build pcap-fuzz-smoke
```

Result: pass. The script decoded and deterministically replayed the six reviewed
seeds under `test/fuzz/pcap-corpus/`, observed different Zig branch maps for
the endian/resolution seeds, and ran the bounded two-second AFL++ job with no
saved crash or hang. The script uses a private `mktemp` directory and removes
findings at exit. Unit tests separately cover every representable truncation,
four endian/resolution combinations, malformed lengths/timestamps, configured
limits, explicit zero-record policy, deterministic writing, error classes, and
allocation cleanup.

## Requirement map

Command:

```sh
nix develop --command zig build coverage
nix develop --command zig build coverage-self-test
nix develop --command zig build version-consistency
```

Result: pass. `docs/requirements/coverage.yaml` contains 11 M1-selected
requirement/invariant/performance IDs. The canonical validator accepts only
`passing` and `passing-synthetic-regression-only`, requires nonempty code
evidence, validates every path, and resolves mapped test names only from the
import graph executed through `src/root.zig`. Seven negative self-tests prove
rejection of unknown and duplicate IDs, missing paths, missing and unreachable
tests, invalid status, and empty code. Version validation confirms
`0.1.0-m1` in `build.zig.zon`, `src/root.zig`, and all 11 coverage claims.
Full source-catalogue coverage remains dependency-gated to later milestones;
the M1 map does not claim those features.

## PERF-CORE-004 synthetic regression

Command:

```sh
nix develop --command zig build -Doptimize=ReleaseFast m1-bench
nix develop --command zig build schemas
```

Result: pass. The runnable regression traversed linear and six-segment
partitions for every size 0 through the configured 256-byte maximum:

```text
packets=514
payload_bytes=65792
receive_calls=9
submit_calls=514
segment_borrows=1799
identity_matches=1799
abstraction_copy_bytes=0
general_allocations=0
artifact=matched
```

Every output segment retained the exact queue-owned address and length captured
before receive, not merely a pointer observed after slot publication. A
`CountingAllocator` wraps the real allocator passed to both queues; setup
activity is snapshotted before traversal and actual allocation/growth calls
remain unchanged through receive and submit. Instrumentation is connected to
receive, submit, segment borrow, explicit `PacketView.read`, and the centralized
abstraction-copy operation; ordinary traversal performs neither copy path.
Intentional allocation and abstraction-copy negative controls each make the
guard reject the run. The benchmark records each negative-control boolean only
inside the branch that observes its exact expected guard error, fails if a
guard unexpectedly succeeds, and compares those derived booleans to the
embedded artifact.

The ReleaseFast executable embeds, parses, and compares all computed proof
metrics against the schema-validated
`bench/examples/benchmark.m1.json`; it reports `artifact=matched` and fails on
drift. This is the first M1 baseline, so there is no prior M1 delta; the M0-V
integer-loop smoke is not a comparable packet baseline.

## Limitations and next gate

- These measurements prove deterministic synthetic semantics and regression
  counters only. They are not production throughput, latency, or capacity
  evidence.
- The 256-byte configured maximum is the explicit M1 regression configuration,
  not a production MTU promise.
- `PacketView.read` is an explicit caller-requested payload copy and increments
  a separate counter; it is not used by ordinary forwarding traversal.
- AArch64 is cross-build-tested, not performance-supported.
- Physical DPDK and AF_XDP behavior remain later-gated; M0-H remains mandatory
  before M4 acceptance.
- M1 is complete within its hardware-free synthetic/virtual scope. M2 remains
  not started and is the next predecessor-gated milestone.
