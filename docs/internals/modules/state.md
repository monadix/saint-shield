# Module: state

## Responsibility

`state` will provide optional, bounded reusable state containers. M0-V exposes
only a compile sentinel; the module is predecessor-gated to M10.

It does not silently enable state, persistence, or distributed coordination.

## Requirements and invariants

The future implementation owns INV-STATE-001..002 and the reusable-state
requirements. No capacity or compatibility claim exists in M0-V.

## Public contract

`scaffold_ready` reserves the namespace only.

## Dependencies

State may use foundation identifiers and generation compatibility IDs. Packet
and policy modules consume state through declared capabilities, not reverse
imports.

## Object lifecycle and ownership

No container exists. M10 must document allocation, worker ownership, expiry,
generation compatibility, retirement, and deterministic destruction.

## Concurrency

No shared state exists now. Each future container must state sharding and owner
rules; cross-worker atomics require explicit review and evidence.

## Allocation and work bounds

The sentinel allocates nothing. Future capacity, probes, expiry work, and
exhaustion outcomes are accepted before activation.

## Failure behavior

No behavior exists. Future exhaustion and incompatible schemas fail according
to declared policy, never silent reinterpretation.

## Security boundary

Keys, values, and configuration are bounded untrusted inputs.

## Performance budget

Lookup/probe bounds and memory per entry require benchmark evidence against a
simple fixed-table reference.

## Tests and evidence

M0-V checks importability. M10 requires saturation, collision, expiry,
compatibility, allocation-failure, and differential tests.

## Alternatives and evolution

Persistent/external databases remain application concerns.

## Open questions

None at M0-V.
