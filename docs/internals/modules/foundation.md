# Module: foundation

## Responsibility

`foundation` defines allocation-free stable numeric identifier types, bounded
error identities, hard resource accounting, monotonic instants, and a
deterministically controlled clock. It does not own packets, adapters,
processors, generations, policy, or wall-clock conversion.

## Requirements and invariants

The deterministic clock implements Section 5.8 test-time monotonic time. The
hard budget is the M1 basis for Section 5.9 and INV-RES-002; later milestone
allocators must debit it rather than replacing its limit semantics.

## Public contract

`StableId(Tag)` creates non-interchangeable `u64` value types without reserving
sentinels. `BoundedError` carries a stable enum and numeric detail, never an
owned string. `Budget.reserve` and `Budget.release` are checked and
failure-atomic. `MonotonicInstant` uses nanoseconds from an unspecified local
epoch. `DeterministicClock` rejects reversal and overflow.

## Dependencies

Only the Zig standard library is imported. Higher-level core modules may depend
on `foundation`; dependency direction never reverses.

## Object lifecycle and ownership

All types are values. A `Budget` or `DeterministicClock` is mutated only by its
owner and owns no external resource.

## Concurrency

No internal synchronization is provided. A mutable budget or clock is
single-owner; immutable snapshots and identifier values may be copied.

## Allocation and work bounds

Every operation is O(1), allocation-free, and non-blocking. Resource addition
uses checked integer arithmetic before changing state.

## Failure behavior

Budget overflow/underflow and time reversal/overflow return bounded errors and
leave the prior value unchanged.

## Security boundary

No untrusted bytes are parsed. Numeric overflow is an explicit error rather
than wrapping into a weaker limit.

## Performance budget

Identifier, error, budget, and time operations remain suitable for packet-path
contexts without allocation or I/O. No throughput claim is attached to M1.

## Tests and evidence

Unit tests cover distinct identifier types, budget limit/underflow/maximum-
integer arithmetic, and deterministic time reversal/overflow in all build
modes. Commands and evidence are recorded under `evidence/m1/`.

## Alternatives and evolution

Atomic accounting may be added as a separate explicitly concurrent type. It
must not silently change the single-owner budget contract.

## Open questions

None for M1.
