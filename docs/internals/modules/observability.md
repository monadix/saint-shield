# Module: observability

## Responsibility

`observability` will provide bounded metrics, events, registries, per-worker
rings, and off-path consumers. M0-V exposes only a compile sentinel.

It does not allow exporters to block workers or define a remote control plane.

## Requirements and invariants

The future module owns FR-OBS-001..008 and INV-OBS-001..003. M0-V claims no
metric/event behavior.

## Public contract

`scaffold_ready` is namespace evidence only.

## Dependencies

The module may consume stable foundation and packet identifiers. Exporters stay
downstream and no core module depends on a particular consumer.

## Object lifecycle and ownership

There are no registries or rings. Future records transfer from worker-owned
bounded rings to off-path consumers with explicit overflow accounting.

## Concurrency

No concurrent state exists. Future cross-thread behavior must document atomic
orders and prove that consumer delay cannot block packet workers.

## Allocation and work bounds

The sentinel allocates nothing. Future cardinality, payload, and ring capacity
are fixed before activation.

## Failure behavior

No events are emitted. Future overflow follows a declared policy and increments
a bounded counter rather than blocking.

## Security boundary

Future application-defined schemas are bounded and validated before use.

## Performance budget

Worker emission is bounded and allocation-free; exporter work remains off-path.

## Tests and evidence

M0-V checks importability. Later gates require blocked-consumer, saturation,
schema, cardinality, and exporter-failure tests.

## Alternatives and evolution

Binary and JSONL consumers may evolve behind the registry contract; dashboards
and service discovery remain out of scope.

## Open questions

None at M0-V.
