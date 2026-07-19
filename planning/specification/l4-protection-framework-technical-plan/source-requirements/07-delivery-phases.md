# 7. Delivery Phases

The phases define coherent product subsets. They are not a prescribed internal implementation plan.

## Phase 1: Core packet-processing framework

### Product outcome

A developer can build a static Zig application that receives packets, processes them through native Zig processors in batches, and produces final dispositions.

### Required subset

- Zig library packaging;
- application-defined processor sequence;
- packet and batch contracts;
- packet inspection;
- controlled packet mutation;
- pass, drop, redirect, and output completion;
- worker-local processor instances;
- startup-time processor preparation;
- deterministic cleanup;
- core runtime metrics snapshots;
- synthetic-packet test harness;
- documented packet ownership and failure behavior.

### Explicit exclusions

- hot updates;
- remote sources;
- standard policy language;
- BPF or WebAssembly execution;
- shared reusable flow state;
- dynamic native plugins.

## Phase 2: Local update and observability lifecycle

### Product outcome

A running application can prepare and atomically activate new processor generations while continuing packet processing under the prior generation.

### Required subset

- versioned configuration artifacts;
- update sessions;
- preparation, validation, activation, retirement, and destruction;
- generation coherence per batch;
- rollback to retained compatible generations;
- application-supplied artifact submission;
- configuration-source interface;
- bounded event production and consumption;
- metrics exporter interface;
- update and generation diagnostics;
- deterministic update testing.

## Phase 3: Standard declarative policy module

### Product outcome

A developer can include an optional standard processor that evaluates rich composable L4 policies without writing a custom processor.

### Required subset

- typed Boolean expressions;
- conjunction, disjunction, negation, and grouping;
- typed comparisons and set membership;
- named sets;
- named predicates;
- absent-aware field semantics;
- ordered ACLs;
- rulesets with actions and explicit defaults;
- native field, function, and action registration;
- preparation-time validation;
- packet explanation for test inputs;
- atomic policy replacement through Phase 2 APIs.

## Phase 4: Reusable stateful protection facilities

### Product outcome

Applications can build stateful L4 protection tools without every processor reimplementing basic bounded state and metering facilities.

### Required subset

- reusable bounded worker-local state containers;
- capacity and exhaustion contracts;
- flow-key facilities configurable by the application;
- rate and token-meter primitives;
- state expiry support;
- explicit state behavior across generations;
- state metrics and diagnostics;
- deterministic time in tests.

This phase MUST NOT impose a universal flow model on processors that do not need one.

## Phase 5: Optional executor and integration modules

### Product outcome

The ecosystem demonstrates that alternate execution and integration technologies fit the native processor and source/exporter contracts.

### Candidate modules

- table-oriented processor;
- BPF executor processor;
- WebAssembly executor processor;
- watched-file source;
- remote-stream source;
- common metrics exporters;
- common event consumers;
- dynamic native plugin ABI, only if justified by real use cases.

Each module remains optional and independently versioned where necessary.

## Phase 6: Operational hardening

### Product outcome

The framework is suitable for production protection tools under documented environments and limits.

### Required subset

- compatibility and stability policy;
- sustained-load and failure-injection test suite;
- update-under-load validation;
- resource leak and generation-retirement tests;
- packet mutation correctness tests;
- bounded-overload behavior;
- reproducible performance methodology;
- security review of untrusted artifact handling;
- long-running observability validation;
- upgrade and rollback procedures.
