# Processor module

## Responsibility

`processor` defines the native M3 descriptor, lifecycle errors/results,
resource estimates and limits, counted allocator, typed metadata store, and
opaque call-scoped contexts. It does not order stages or publish generations.

## Requirements and invariants

Primary mappings are FR-PROC-001..009, FR-EXT-001..003, FR-STATE-001/004,
INV-RES-001/002, and AC-012. FR-COMP-005/006 are claimed only for the open
native contract: M3 contains no closed executor enumeration and does not claim
that an optional executor implementation exists.

## Public contract

`ProcessorDescriptor` declares stable identity/API, packet access,
dispositions/outputs, artifacts, authority-free typed metadata, concrete bounded
metric/event schemas, services, bounded work, errors, update-state
schema/default, and resource categories. M3 rejects retention declarations.
`ProcessContext(descriptor)` generates the exact call-scoped surface.

## Dependencies

The module depends only on `foundation` and `packet`. Adapters, update runtime,
sources, and policy are not imported.

## Object lifecycle and ownership

A processor provides `Prepared` and `Worker` values. Pipeline construction owns
both tuples. `ProcessContext` stores only an opaque cookie; no owner, token,
pointer, slice, writer, or borrow is returned to the processor. A
package-internal invocation bridge binds that cookie to the installed descriptor
and a pointer-free effective-capability record and revokes it before return.
Neither invocation nor capability-installation machinery is exported through
the public `processor` or root namespace.

## Concurrency

One worker owns its `Worker` value. Prepared values are static-generation owned
and treated as immutable during execution. One thread-local invocation is
active for the duration of a direct stage call.

## Allocation and work bounds

Preparation and worker construction use separately counted per-stage allocators
with hard declared limits. Each allocator is sealed at constructor return and
opens free-only authority during owner-mediated cleanup. Descriptors report
finite resource categories and an authoritative maximum batch-work formula.
Fixed metadata slots and packet-path access allocate nothing.

## Failure behavior

Lifecycle failures use bounded categories. Expected processing errors are the
exact `ProcessError` set and follow the descriptor policy. Invariant faults are
not converted to recoverable packet errors.

## Security boundary

Generated contexts recheck both declared and installed capabilities on every
operation. Trusted raw writes are explicit and additionally require application
opt-in. Metadata/metric/event inline types recursively reject pointer, slice,
function, frame, allocator-bearing, and other lifetime authority. Processor
results cannot carry packet authority or arbitrary callback state.

## Performance budget

The processor boundary is one direct call per non-empty stage and batch. It has
no per-packet virtual dispatch or hot-path allocation.

## Tests and evidence

`m3-compile-fail` covers declaration categories. `m3-test` covers limits,
underestimates, capabilities, allocation failures, cleanup, error policies,
metadata, ordering, and seeded reference pipelines.

## Alternatives and evolution

Dynamic native plugins and optional executors remain future modules using this
same open contract. M3 records update modes but has no generation switching or
QSBR.

## Open questions

None for M3.
