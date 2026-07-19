# 1. Concepts and Boundaries

## 1.1 Runtime responsibilities

The framework has three local responsibility areas. These are not required to be separate binaries, services, or machines.

### Packet runtime

The packet runtime is responsible for:

- receiving packets from configured inputs;
- grouping available packets into batches;
- invoking packet processors in configured order;
- preserving packet and batch lifetime rules;
- applying packet dispositions;
- transmitting, redirecting, dropping, or otherwise completing packets;
- maintaining worker-local processing state;
- exposing low-overhead instrumentation points.

### Update runtime

The update runtime is responsible for:

- accepting versioned configuration artifacts from the application;
- asking processors to prepare new configurations outside packet workers;
- validating local resource requirements;
- constructing processor instances required by packet workers;
- publishing complete generations atomically;
- retiring old generations only after they are no longer in use;
- reporting preparation and activation failures;
- supporting application-directed rollback where configured.

### Observability runtime

The observability runtime is responsible for:

- collecting low-overhead counters and bounded events;
- aggregating worker-local observations into local snapshots;
- exposing snapshots and event streams through public interfaces;
- ensuring exporter or consumer delays do not block packet workers.

## 1.2 Application responsibilities

An application using the framework is responsible for:

- selecting and composing processors;
- selecting packet inputs and outputs;
- choosing configuration sources;
- passing configuration artifacts to processor update APIs;
- choosing metrics exporters and event consumers;
- defining deployment topology;
- defining operational failure policies;
- integrating with optional external controllers;
- defining tool-specific protection behavior.

## 1.3 External-system responsibilities

External systems MAY provide:

- centralized policy distribution;
- multi-node rollout coordination;
- persistence and audit storage;
- fleet-wide metrics aggregation;
- dashboards and alerting;
- operator-facing APIs;
- configuration authorization;
- artifact signing and provenance.

These capabilities are outside the core framework.

## 1.4 Deployment topology

The framework MUST support the following without changing packet-processor semantics:

1. one binary containing configuration, packet processing, and observability;
2. one packet-processing binary controlled by another local process;
3. one packet-processing binary receiving updates from a remote controller;
4. multiple packet-processing applications managed by an external system.

The framework MUST NOT require any one topology.

## 1.5 Core domain terms

### Packet

A packet is one input packet buffer and associated framework metadata during one processing lifecycle.

### Batch

A batch is an ordered collection of zero or more packets obtained together from one packet input queue during one receive operation or equivalent polling step.

Packets in a batch are not required to share a flow, protocol, address, rule, or semantic relationship.

### Processor

A processor is an application-selected extension that can inspect, classify, modify, redirect, drop, or otherwise act on packets in a batch.

### Prepared processor

A prepared processor is immutable or logically immutable configuration produced outside packet workers and suitable for creating worker-visible processor instances.

### Worker processor

A worker processor is the processor state used by one packet worker. It MAY refer to shared read-only prepared data and MAY contain worker-local mutable state.

### Generation

A generation is a complete set of compatible processor configurations and runtime references published as one activation unit.

### Configuration artifact

A configuration artifact is a versioned byte sequence or structured value supplied by the application to a processor or update API.

### Disposition

A disposition is the framework-level outcome that determines whether a packet remains active, is accepted for normal forwarding, dropped, redirected, or completed through another configured output.

### Metric

A metric is a bounded aggregate measurement.

### Event

An event is a detailed, potentially high-cardinality observation delivered through a bounded asynchronous mechanism.
