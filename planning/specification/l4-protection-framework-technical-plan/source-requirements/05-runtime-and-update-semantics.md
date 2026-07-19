# 5. Runtime and Update Semantics

## 5.1 Packet-path constraints

A conforming packet processor MUST NOT, during `process_batch`:

- perform blocking I/O;
- wait indefinitely for another thread or process;
- request remote policy decisions for every packet;
- allocate unbounded memory;
- emit unbounded strings or high-cardinality metric labels;
- retain packet references without explicit ownership transfer;
- silently ignore mutation, routing, or resource failures.

A packet processor SHOULD avoid:

- contended global locks;
- general-purpose heap allocation;
- shared mutable state across workers;
- per-packet dynamic dispatch when batch-level or statically composed processing is possible;
- work whose maximum cost cannot be bounded or controlled.

The framework MAY permit explicitly marked non-conforming processors for experimentation, but such processors MUST be identifiable and MUST NOT be presented as satisfying packet-path guarantees.

## 5.2 Batch formation

A batch is formed from packets made available by one input queue during one receive operation or equivalent polling action.

The framework MUST document:

- maximum requested batch size;
- actual batch size;
- input origin;
- whether empty batches are exposed to processors;
- packet-order guarantees;
- behavior when more packets remain queued.

The framework MUST process non-empty partial batches without artificial waiting by default.

Optional coalescing MAY be provided, but it MUST be explicit because it changes latency behavior.

## 5.3 Processor ordering

Processors execute in application-defined order.

The framework MUST define:

- which dispositions remove packets from later processors;
- whether metadata produced by one processor is visible to later processors;
- whether a processor can route packets to an alternate pipeline;
- how errors affect the remainder of a batch;
- whether processor ordering can change at runtime.

The baseline model SHOULD keep one coherent processor sequence for a batch.

## 5.4 Generation coherence

Each batch MUST be associated with one generation for all processors that are updated as part of that generation.

A worker MAY switch generations only at a documented safe boundary.

A safe boundary MUST prevent:

- one processor observing new configuration while a dependent processor observes incompatible old configuration;
- destruction of data still referenced by the worker;
- state interpretation under an incompatible schema.

## 5.5 Update lifecycle

A candidate update proceeds through these abstract states:

```text
Created -> Preparing -> Prepared -> Validated -> Activating -> Active
                                  \-> Aborted
                       \-> Failed
Active -> Retiring -> Retired -> Destroyed
```

Requirements:

- Preparation and validation MUST be packet-invisible.
- Activation MUST be explicit.
- A candidate MUST be abortable before activation.
- Activation failures MUST be observable.
- Retirement MUST wait for quiescence.
- Destruction MUST release all generation-owned resources.

## 5.6 Existing state during updates

Processors that maintain state MUST declare supported update modes.

Possible modes include:

- retain until state expiry;
- retain and interpret under a compatible schema;
- lazily reevaluate on next packet;
- eagerly reevaluate before activation;
- flush at activation;
- processor-defined migration.

The application MUST select or accept a documented default.

An unsupported requested mode MUST fail preparation or validation.

## 5.7 Failure behavior

The application MUST be able to configure or determine behavior for:

- packet input failure;
- packet output failure;
- processor execution error;
- resource exhaustion;
- event-queue overflow;
- metrics-export failure;
- source failure;
- update preparation failure;
- activation failure;
- state-capacity exhaustion.

Where packet continuation is possible, behavior SHOULD be expressible as one of:

- fail open;
- fail closed;
- preserve previous generation;
- use a configured default disposition;
- degrade a non-essential feature;
- stop the affected worker or runtime.

Defaults MUST be documented and MUST NOT be silently inferred from unrelated components.

## 5.8 Time and determinism

The framework MUST expose a monotonic time source suitable for local packet-processing decisions.

Processors SHOULD NOT depend on wall-clock time in the packet path unless explicitly required.

Testing APIs SHOULD allow deterministic time control.

## 5.9 Resource budgets

The application MUST be able to impose resource limits on processor preparation and runtime state.

Processors MUST report resource exhaustion through bounded, observable outcomes.

A processor MUST NOT silently exceed declared mandatory limits.

The framework SHOULD expose resource accounting for:

- prepared configuration memory;
- worker-local state;
- retained generations;
- event queues;
- reusable state facilities;
- packet retention where supported.
