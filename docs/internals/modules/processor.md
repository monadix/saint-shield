# Module: processor

## Responsibility

`processor` will define native processor declarations, capabilities, prepared
state, worker state, and bounded batch-call semantics. M0-V contains only a
compile sentinel; the contract is predecessor-gated to M3.

It does not order processors, publish generations, or implement policy syntax.

## Requirements and invariants

M3 owns FR-PROC-001..009, FR-EXT-001..003, INV-RES-001..002, and the processor
side of AC-003/012. M0-V claims none of those behaviors.

## Public contract

`scaffold_ready` indicates a reserved namespace only.

## Dependencies

The future contract may depend on `foundation` and `packet`; it must not import
adapters, update machinery, or the optional standard policy module.

## Object lifecycle and ownership

No runtime object exists. M3 will specify prepare, per-worker construction,
reverse cleanup, and borrow-only batch access.

## Concurrency

No state exists in M0-V. Prepared data will be immutable and worker state
single-owner unless a declaration explicitly proves otherwise.

## Allocation and work bounds

The sentinel allocates nothing. M3 declarations must expose preparation and
worker resource bounds and forbid undeclared packet-path allocation.

## Failure behavior

No processor can run. M3 will map declared errors to explicit packet/default
effects and treat invariant violations as non-recoverable faults.

## Security boundary

Processor declarations and artifacts become validated inputs in M3.

## Performance budget

The future batch call is static and bounded, without a callback per packet.

## Tests and evidence

M0-V imports the namespace. M3 requires compile-fail contracts, allocation
faults, ordering scenarios, and reference-runner differential tests.

## Alternatives and evolution

Runtime plugin discovery remains out of scope; finite compile-time composition
keeps the public boundary replaceable.

## Open questions

None at M0-V.
