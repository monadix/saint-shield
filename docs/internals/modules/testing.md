# Module: testing

## Responsibility

`testing` standardizes deterministic seeds and bounded minimized operation
traces for generated tests. Synthetic packets and capture records are supplied
through public `io.synthetic` and `io.pcap` modules. The full processor harness
remains predecessor-gated to M3.

## Requirements and invariants

The M1 helper supports FR-TEST-001/002 diagnostics and the archived requirement
that randomized failures print a seed, exact Zig toolchain, and minimized trace.
Synthetic tests use it alongside INV-PKT-001/002 evidence.

## Public contract

`SeededTrace(N)` owns one deterministic Zig PRNG and at most `N` trace bytes.
`append` never allocates; insufficient capacity sets `truncated`. A failure
report always labels `seed`, `toolchain`, and `minimized_trace`.

## Dependencies

Only the Zig standard library is imported. External fuzzers and packet oracles
remain tooling dependencies, not runtime-library imports.

## Object lifecycle and ownership

A trace is a caller-owned value. Returned random interfaces borrow its PRNG;
trace slices borrow its fixed storage.

## Concurrency

One test thread owns a trace. Parallel property runs use independent instances
and independently recorded seeds.

## Allocation and work bounds

Trace construction, random generation, append, and inspection allocate nothing.
Append is O(operation length) and bounded by the comptime storage size.

## Failure behavior

Trace overflow is observable through `truncated`; it never writes beyond the
fixed buffer. Diagnostic printing occurs only after a failed test.

## Security boundary

Trace text is diagnostic input supplied by the test. Capture parsing remains in
the bounded PCAP module.

## Performance budget

This module is test-only and does not execute in packet workers. Instrumenting
a test must not alter the production code under observation.

## Tests and evidence

Tests prove equal seeds reproduce equal PRNG values and trace overflow is
bounded and explicit. M1 packet properties use an independent exhaustive token
model and deterministic synthetic queue scenarios, so they do not need a
random seed to cover their finite state spaces. The canonical
`docs/requirements/coverage.yaml` map is checked for known/unique M1 IDs,
existing design/code paths, named tests, and passing-claim evidence.

## Alternatives and evolution

M3 builds the public processor harness over the real synthetic queues and
pipeline contracts. The seed/trace output format remains usable by it.

## Open questions

None for M1.
