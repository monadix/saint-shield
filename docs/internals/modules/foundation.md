# Module: foundation

## Responsibility

`foundation` is the dependency-free home for stable identifiers, bounded
errors, budgets, and time contracts. M0-V exposes only a documented compile
sentinel; its concrete behavior is predecessor-gated to M1.

It does not own packets, adapters, processors, generations, or policy.

## Requirements and invariants

M1 will map the module to the foundational portions of FR-PKT-001..004 and
INV-RES-001..002. M0-V makes no behavioral claim beyond importability.

## Public contract

`scaffold_ready` is a compile sentinel, not a capability or readiness probe.

## Dependencies

No framework module may be imported here. Higher-level core modules may depend
on `foundation`; adapters remain downstream of the core.

## Object lifecycle and ownership

There are no runtime objects or ownership transfers in M0-V.

## Concurrency

There is no mutable or concurrent state in M0-V.

## Allocation and work bounds

Importing the module allocates nothing and performs no runtime work.

## Failure behavior

The sentinel has no failure mode. Concrete error and budget behavior must land
with M1 tests and documentation.

## Security boundary

There is no input parser or unsafe boundary in this module.

## Performance budget

Foundational value types must remain allocation-free on the packet path. The
M0-V sentinel is not benchmark evidence for the M1 implementation.

## Tests and evidence

All build modes and the AArch64 cross-build import this module through
`src/root.zig`.

## Alternatives and evolution

M1 replaces the sentinel with bounded types without changing the dependency
direction. Public semantics require normal compatibility review.

## Open questions

None at M0-V.
