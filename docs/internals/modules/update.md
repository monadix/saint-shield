# Module: update

## Responsibility

`update` will prepare, validate, publish, adopt, retire, and reclaim immutable
generations. M0-V exposes only a compile sentinel; implementation is deferred
to M6.

It does not define policy syntax or processor-local state semantics.

## Requirements and invariants

The future implementation owns INV-GEN-001..005 and the generation portions of
FR-COMP-004 and runtime/update requirements. No publication claim exists now.

## Public contract

`scaffold_ready` reserves the namespace and exposes no update operation.

## Dependencies

The future module may assemble core prepared objects; the public core must not
depend on controllers, remote protocols, or persistent stores.

## Object lifecycle and ownership

No generation exists. M6 must document preparation, atomic publication,
worker adoption, grace periods, reverse destruction, and failure cleanup.

## Concurrency

No atomics exist in M0-V. A TLA+/PlusCal model is a mandatory predecessor for
the future publication/reclamation protocol.

## Allocation and work bounds

The sentinel allocates nothing. Preparation is off-path and budgeted; worker
adoption must be bounded and allocation-free.

## Failure behavior

No behavior exists. Candidate failure must preserve active behavior under
INV-GEN-004.

## Security boundary

Future artifacts are untrusted until bounded validation completes.

## Performance budget

Publication work is per generation and adoption cost is measured per batch,
never hidden per packet.

## Tests and evidence

M0-V checks importability. M6 requires model checks, forced interleavings,
fault injection, update-under-load, and reclamation accounting.

## Alternatives and evolution

Remote update protocols and persistence remain application concerns unless a
later accepted requirement changes scope.

## Open questions

None at M0-V.
