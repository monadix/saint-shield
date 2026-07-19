# Module: testing

## Responsibility

`testing` will expose deterministic fixtures and a public processor harness.
M0-V provides only a compile sentinel; facilities arrive with M1 and M3.

It does not place fuzzers, Scapy, generators, or other tooling in the runtime.

## Requirements and invariants

The future module supports FR-TEST-001..003 and conformance evidence for packet
and processor invariants. The sentinel claims no fixture semantics.

## Public contract

`scaffold_ready` reserves the namespace only.

## Dependencies

Public test helpers may depend on stable core contracts. External tools remain
test-only dependencies and are never imported by the public runtime library.

## Object lifecycle and ownership

No fixture object exists. Future helpers must make allocator ownership, seeded
randomness, token completion, and teardown deterministic.

## Concurrency

No concurrent state exists. Future schedulers/interleaving fixtures expose
explicit seeds and minimized traces.

## Allocation and work bounds

The sentinel allocates nothing. Future fixtures accept caller allocators and
bounded scenario sizes.

## Failure behavior

No test operation exists. Future failures retain exact seed/input and cleanup
accounting.

## Security boundary

Captured fixtures must be sanitized and record provenance/license; parsers
treat bytes as untrusted.

## Performance budget

This module is off-path; it must still avoid changing semantics of the code it
observes.

## Tests and evidence

M0-V checks importability and keeps fuzz/tool dependencies outside the runtime.
Later milestones test the harness against known reference outcomes.

## Alternatives and evolution

Private test helpers may coexist, but public extension contracts require a
stable supported harness.

## Open questions

None at M0-V.
