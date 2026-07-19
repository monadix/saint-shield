# Module: Name

## Responsibility

One paragraph. Then explicit non-responsibilities.

## Requirements and invariants

Exact FR/PL/AC and INV identifiers.

## Public contract

Types/functions and observable semantics. State stability level.

## Dependencies

Allowed dependency direction and why each nontrivial dependency exists.

## Object lifecycle and ownership

Construction, borrowing/transfers, activation, retirement, destruction, partial-failure cleanup.

## Concurrency

Callers/threads, single/multi-owner data, atomics and memory order, quiescent points, false-sharing precautions.

## Allocation and work bounds

Preparation/runtime memory formula, maximum loops/probes/records, overflow/exhaustion behavior.

## Failure behavior

Each failure category and the resulting packet/generation/module state.

## Security boundary

Trusted/untrusted inputs, validation limits, sensitive data, unsafe/FFI points.

## Performance budget

Relevant BENCH/PERF IDs and the simpler reference implementation.

## Tests and evidence

Unit, property/differential, model, integration, hardware, fuzz, soak. Map requirements.

## Alternatives and evolution

Rejected/deferred choices, reversal triggers, and how the public API avoids blocking them.

## Open questions

Only unresolved decisions with owner/gate; do not use this as an unbounded wish list.

