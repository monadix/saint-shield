# 8. Conformance and Acceptance

## 8.1 Conformance classes

### Core runtime conformant

An implementation is core-runtime conformant when it satisfies all mandatory requirements in:

- product definition;
- concepts and boundaries;
- framework composition;
- packet processing;
- processor lifecycle;
- update semantics for features it claims to support;
- observability core;
- testing requirements.

### Processor conformant

A processor is conformant when it:

- implements the published processor lifecycle;
- declares required capabilities;
- obeys packet and batch lifetimes;
- obeys packet-path constraints;
- reports resource and execution failures;
- provides deterministic cleanup;
- documents state behavior across updates.

### Source conformant

A configuration source is conformant when it:

- emits versioned artifacts;
- does not directly mutate active processors;
- reports source errors;
- stops deterministically;
- documents ordering and retry semantics.

### Exporter or consumer conformant

An exporter or event consumer is conformant when it:

- executes outside packet workers;
- cannot block packet processing;
- reports its own failure;
- respects descriptor and payload schemas.

### Standard policy module conformant

A policy module is conformant when it satisfies all mandatory `PL-*` requirements.

## 8.2 Minimum acceptance scenarios

### AC-001: Partial batch

Given an input queue with fewer packets than the configured maximum batch size, the framework processes the available packets without waiting for a full batch.

### AC-002: Mixed batch

Given packets from unrelated flows and protocols in one batch, a processor receives them without any false same-flow guarantee and produces independent dispositions.

### AC-003: Processor sequence

Given three processors, active packets are presented in configured order, and terminally completed packets are not passed onward unless explicitly configured.

### AC-004: Failed preparation

Given invalid processor configuration, preparation returns diagnostics and the currently active generation remains unchanged.

### AC-005: Atomic generation

Under continuous packet load during activation, every processed batch uses one coherent generation.

### AC-006: Safe retirement

A retired generation is not destroyed while any worker may still reference it.

### AC-007: Source independence

The same processor accepts equivalent artifacts supplied directly by the application and through a source module.

### AC-008: Exporter isolation

A blocked or failing exporter does not block packet workers and produces an observable exporter failure.

### AC-009: Event overflow

When the event queue reaches capacity, packet workers continue according to configured overflow policy and an overflow metric is updated.

### AC-010: Packet lifetime

A processor retaining a packet reference without explicit ownership transfer is rejected by static API constraints, runtime checks, tests, or documented unsafe-contract enforcement.

### AC-011: Update rollback

When rollback is supported and a retained compatible generation exists, rollback activates it coherently and reports the new active generation identity.

### AC-012: Resource rejection

A candidate generation whose declared mandatory resources exceed application limits fails before publication.

## 8.3 Policy-module acceptance scenarios

### AC-PL-001: Boolean composition

A policy can match nested combinations of conjunction, disjunction, negation, and grouping.

### AC-PL-002: Named set membership

A policy can match an address or port against a named typed set.

### AC-PL-003: Named predicate

A policy can define and reuse a named predicate without changing semantics.

### AC-PL-004: Missing field semantics

For a non-TCP packet, `tcp.destination_port != 80` does not evaluate as a successful top-level match solely because the field is unavailable.

### AC-PL-005: Ordered ACL

An ACL evaluates entries in order, honors explicit allow/deny, and applies an explicit default.

### AC-PL-006: Action validation

A policy referencing an unregistered action or invalid action arguments fails during preparation.

### AC-PL-007: Pure match expression

Match evaluation produces no packet mutation, metric update, event emission, state mutation, or external I/O.

### AC-PL-008: Explanation

For a supplied test packet, the module can report enough information to identify relevant parsed fields, matched rule or default, actions, and final disposition.

## 8.4 Quality gates

Before production-ready status is claimed, the project MUST demonstrate:

- no packet or generation resource leaks under repeated update cycles;
- bounded behavior under event-consumer failure;
- bounded behavior under state exhaustion;
- correct cleanup after preparation failure;
- correct packet mutation and finalization;
- update coherence under sustained load;
- reproducible performance tests with documented conditions;
- documented unsafe boundaries;
- compatibility policy for public APIs and optional module artifacts;
- security analysis for untrusted configuration artifacts.
