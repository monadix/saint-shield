# ADR-012: AFL++ for coverage-guided fuzzing

- Status: accepted
- Date: 2026-07-19
- Owners/reviewers: Saint Shield core and security review
- Requirements/invariants: D-012, M0-V sanitizing and fuzzing gate
- Supersedes/superseded by: none

## Context

M0-V must select an exact coverage-guided engine compatible with Zig 0.16.0,
C adapter code, deterministic saved inputs, timeouts, and sanitizers. The
selection concerns local project parsers and fixtures only; it grants no scope
to test third-party binaries or network services.

Full DPDK headers contain compiler-specific TLS and inline constructs, so C
adapter fuzz targets remain ordinary C translation units. Pure Zig 0.16.0
targets are compiled normally and observed with AFL++ QEMU binary
instrumentation through a content-neutral C file launcher.

## Decision drivers

Correct reproducibility and sanitizer diagnostics rank first, followed by C/Zig
interoperability, corpus management, timeout control, CI availability, and
operational simplicity.

## Considered options

- AFL++ 5.00c: pinned by the flake, supports Clang and QEMU binary
  instrumentation, dictionaries, persistent corpora, saved crashes/hangs,
  per-execution timeouts, and ASan/UBSan.
- LLVM libFuzzer: strong in-process sanitizer integration, but Zig 0.16 does not
  provide a single stable project-wide driver for both pure Zig and C adapters.
- Zig test-only random generation: useful for seeded properties, but it is not
  coverage-guided and does not replace a fuzzer.

## Decision

Use AFL++ 5.00c from the locked Nix environment. C sanitizer targets use the
AFL Clang wrapper; pure Zig targets use ReleaseSafe Zig code observed by
AFL++'s `-Q` mode. Every target owns a bounded seed corpus, optional dictionary,
maximum input size, execution timeout, and a documented command that reruns a
saved input outside the fuzz loop.

The M0-V sanitizer fixture in `test/fuzz/d012_fixture.c` contains an intentional
local heap-boundary defect behind `M0V!`. The function in
`test/fuzz/d012_zig_branch.zig` contains the byte-dependent safe, crash, and
`HANG` branches used to prove observation inside Zig-compiled code. These are
evidence plumbing, never production code. `zig build fuzz-smoke` verifies the
checked-in reproducer twice, distinct QEMU maps for equal-length safe inputs,
exact timeout classification, coverage-guided discovery from a non-crashing
seed plus dictionary, saved-crash replay, and ASan classification of the saved
input.

## Consequences

AFL++ and LLVM/Clang are test dependencies only. Corpus and crash inputs are
reviewable files. Fuzz jobs need Linux process execution and may be slower under
CPU-constrained CI. Production code gains no AFL runtime dependency.

## Validation

Run inside the locked shell:

```sh
nix develop
zig build fuzz-smoke
```

The fuzz loop must finish within its 30-second outer bound. The command prints
two deterministic ASan reproductions, distinct AFL++ maps originating in Zig
branches, timeout status 1 for the 100 ms `HANG` case, SIGABRT status 134 for
the saved Zig-branch crash, and an ASan heap-buffer-overflow for that same saved
input.

## Reversal triggers

Revisit if QEMU observation cannot expose useful control flow in a required
pure-Zig target, becomes incompatible with the pinned LLVM/Zig toolchain, or a
Zig-native coverage engine provides equal corpus, timeout, and sanitizer
evidence with lower CI cost. Migrate corpora as raw byte inputs and preserve
this reproducer as a regression test.

## Rollout

M1 adds capture parsing, followed by packet parsing/finalization and later
artifact/event targets. Each target lands with bounds, seed provenance, and a
short CI smoke before longer jobs are enabled.
