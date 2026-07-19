# Module: pipeline

## Responsibility

`pipeline` will validate and execute an ordered compile-time tuple of native
processors. M0-V reserves the namespace with a compile sentinel; execution is
gated to M3.

It does not acquire artifacts, select an I/O backend, or publish generations.

## Requirements and invariants

M3 owns FR-COMP-001..003/005..006, FR-PKT-014..015, INV-PKT-003..004, and the
pipeline side of AC-003/012.

## Public contract

`scaffold_ready` has no runtime or ordering semantics.

## Dependencies

The future module may depend on `foundation`, `packet`, and `processor`. It must
remain independent of concrete adapters and optional policy implementations.

## Object lifecycle and ownership

No pipeline object exists. M3 must construct prepared and worker tuples in
order, destroy them in reverse order, and reconcile partial construction.

## Concurrency

No concurrent state exists. Future worker pipelines are single-worker-owned;
prepared state is generation-immutable.

## Allocation and work bounds

The sentinel performs no work. M3 derives finite scratch and metadata layouts
at preparation and performs no undeclared hot-path allocation.

## Failure behavior

No processing occurs. M3 must preserve terminal dispositions and identify the
processor responsible for a declared failure.

## Security boundary

Processor declarations are validated before activation; M0-V accepts none.

## Performance budget

M3 compares static calls with a simple reference runner and a deliberately
type-erased baseline.

## Tests and evidence

M0-V proves importability. M3 adds invalid-declaration, ordering, cleanup,
random differential, and microbenchmark evidence.

## Alternatives and evolution

Runtime reorder remains rebuild/restart unless later evidence justifies a
finite validated variant set.

## Open questions

None at M0-V.
