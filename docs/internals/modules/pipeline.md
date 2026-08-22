# Pipeline module

## Responsibility

`pipeline` validates and executes an application-ordered tuple of native
processors. It owns pre-runnable validation, lifecycle tuples, typed metadata,
direct calls, error/default resolution, and exact reverse cleanup.

## Requirements and invariants

M3 owns FR-COMP-001..003/005..006, FR-PKT-014..015, INV-RES-001..002, and the
pipeline side of AC-003/012. Existing terminal packets are never overwritten or
reintroduced into later active selections.

## Public contract

`Pipeline(.{...})` constructs a pipeline without application input metadata.
`PipelineWithInputMetadata(.{...}, MetadataKeys(.{...}))` is the explicit typed
input form required because Zig 0.16 has no default function parameters.

## Dependencies

The module depends on `foundation`, `packet`, and `processor`; it is independent
of concrete adapters, update machinery, and optional policy implementations.

## Object lifecycle and ownership

Prepared and worker tuples are constructed in application order and destroyed
in exact reverse order. The prepared owner maintains a checked worker registry,
capacity, live count, and per-slot generation. A `WorkerHandle` contains only
scalar owner identity, slot, and generation values. Every operation supplies a
separately live prepared owner, which rejects wrong-owner, forged, stale, or
recycled values before resolving internal worker storage. Prepared destruction
rejects live workers. The prepared owner also copies the bounded validated
application output-ID set; it never retains the caller's capability slice.

## Concurrency

A worker pipeline is single-worker-owned. Prepared state is generation-static.
M3 performs no concurrent publication or runtime reorder.

## Allocation and work bounds

Assembly checks capability availability, artifacts, each stage estimate,
generated wrapper/tuple/registry bytes, worker multiplication, the full fixed
metadata store, bounded pools, and maximum work before the first `prepare`.
Separate stage budgets prevent slack laundering. Allocation denial after
underestimation aborts construction. Execution uses fixed metadata and no hot
allocation.

## Failure behavior

Each stage error follows only its declared policy: continue active packets,
apply a non-retaining terminal disposition, or apply it and stop later stages.
Pipeline-end `Continue` resolution is an explicit caller policy. Complete
disposition configuration is validated before the first callback against its
own bounds, the application output set, all generated processor outputs, and
default/`Continue` routing. Once a callback begins, every returned pipeline
error invalidates the exact batch generation before control returns; derived
batch, view, editor, iterator, and output handles cannot expose partial effects.
Adapter tokens are not completed by invalidation and remain a single caller
reconciliation obligation. A pre-existing non-revocable raw slice or adapter
token rejects before callbacks, because invalidation could not revoke it.

## Security boundary

Comptime validation rejects incomplete or inconsistent processor declarations,
undeclared metadata reads, and authority-bearing inline values. Runtime assembly
rejects unavailable capabilities before any processor runs. Invocation
authority remains pipeline-owned and bound to one descriptor/capability record.

## Performance budget

PERF-CORE-001 compares direct four-stage and zero-stage generated pipelines at
batches 32/64. The monolith and batch-vtable paths do not run the complete
pipeline context/authentication/accounting path, so their measurements are
classified as non-comparable diagnostic-only data and cannot affect acceptance
or an architecture decision. A deep terminal variant proves later stage
counters remain zero.

## Tests and evidence

Dedicated tests cover invalid declarations, exact and excess limits, overflow,
worker multiplication, partial cleanup, allocation-failure sweeps, ordering,
mixed outcomes, all error policies, metadata, and seeded reference pipelines.
They also cover pre-callback invalid-routing atomicity, post-callback
work-contract revocation, and the benchmark constructor's every-index
allocation failure, token reconciliation, and exact reverse teardown without
running performance samples.
Fresh evidence requires seven independently launched warmed runs and retains 35
samples per variant plus per-run aggregates. Validation recomputes every
raw `ns/packet`, cycles/packet, and packet rate from elapsed time, cycles, batch
size, and measurement iterations within recorded print tolerances. It also
checks each sample's complete order permutation, recomputes every aggregate,
and binds schema, commit/tree ancestry, raw output, generation inputs, all
benchmark sources, and environment. The retained artifact is refreshed only
after the authority-return review checkpoint.

## Alternatives and evolution

Runtime reorder, dynamic plugin graphs, and per-packet virtual dispatch remain
out of scope.

## Open questions

None for M3.
