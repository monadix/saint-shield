# Module: packet

## Responsibility

`packet` will define backend-neutral storage ownership, segments, borrow-scoped
views, input origins, receive order, and dispositions. M0-V exposes only a
compile sentinel; all packet semantics are gated to M1.

It does not receive/transmit packets or choose an I/O backend.

## Requirements and invariants

The M1 implementation owns FR-PKT-001..013 and INV-PKT-001..005. None of those
invariants is claimed by the current sentinel.

## Public contract

`scaffold_ready` proves package shape only. It is not a packet API.

## Dependencies

The module may depend on `foundation`, never on `io` or a backend-specific type.

## Object lifecycle and ownership

No packet token or view exists in M0-V. M1 must document receive, borrow,
retention, and exactly-once completion transitions alongside implementation.

## Concurrency

No concurrent state exists. M1 packet batches will be worker-owned and their
views scoped to one processing call.

## Allocation and work bounds

The sentinel allocates nothing. M1 hot paths must satisfy INV-RES-001 and the
accepted maximum batch bound of 64.

## Failure behavior

No behavior is implemented. M1 defines bounded error effects without weakening
packet completion invariants.

## Security boundary

Backend metadata and packet bytes become untrusted inputs in M1; M0-V parses
neither.

## Performance budget

M1 must preserve the zero-copy adapter boundary and compare views against the
simple synthetic reference.

## Tests and evidence

M0-V verifies importability only. Range, segment, ownership, and differential
tests are mandatory at the M1 gate.

## Alternatives and evolution

Internal slot layout may evolve behind the backend-neutral public contract.

## Open questions

None at M0-V.
