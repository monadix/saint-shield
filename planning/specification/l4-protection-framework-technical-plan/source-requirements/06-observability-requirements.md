# 6. Observability Requirements

## 6.1 Scope

The framework collects and exposes local observability data. It does not provide fleet-wide storage, dashboards, alerting, or global aggregation.

## 6.2 Core metrics

The framework MUST expose bounded metrics for at least:

- packets and bytes received per configured input;
- packets and bytes completed per configured output;
- packets dropped by framework-level reason;
- receive and transmit failures;
- current active generation;
- successful and failed update counts;
- update preparation and activation duration;
- retained and retired generation counts;
- processor execution failures;
- event emission drops or overflow;
- worker liveness or progress;
- batch-size distribution or equivalent batching observations;
- resource exhaustion events.

The framework SHOULD expose processor execution cost measurements where they can be gathered without unacceptable overhead.

## 6.3 Processor metrics

Processors MUST be able to register bounded metric descriptors before packet execution.

Descriptors MUST define:

- stable name or identifier;
- metric kind;
- unit;
- bounded label dimensions;
- aggregation meaning;
- lifecycle relative to generations.

Per-rule metrics MAY be supported but MUST have explicit cardinality limits.

Dynamic packet-derived values such as arbitrary addresses or flow identifiers MUST NOT be used as metric labels by default.

## 6.4 Snapshot semantics

A metrics snapshot MUST include:

- snapshot time;
- relevant generation identity;
- metric descriptors or descriptor references;
- values;
- consistency metadata when values are not read atomically.

The framework MAY expose weakly consistent snapshots if this avoids packet-path synchronization, but the guarantee MUST be documented.

## 6.5 Exporters

Metrics exporters are optional application-selected components.

An exporter:

- consumes snapshots outside packet workers;
- MAY allocate, block, retry, or perform I/O;
- MUST report exporter failure separately from packet-runtime failure;
- MUST NOT mutate packet-runtime state except through explicit management APIs;
- MUST NOT require a packet worker to wait.

## 6.6 Events

Events are used for detailed observations unsuitable for bounded aggregate metrics.

Each event type MUST have:

- stable type identity;
- bounded payload schema;
- severity or category where useful;
- generation and processor attribution where applicable.

Event production MUST support explicit policies such as:

- always emit until queue capacity;
- sample;
- rate limit;
- aggregate before emission;
- discard with a counter.

## 6.7 Event consumers

Event consumers operate outside packet workers.

Consumers MAY:

- serialize events;
- write to files or sockets;
- forward to external systems;
- aggregate or enrich events;
- drop events according to application policy.

Consumer failure MUST NOT block packet processing.

## 6.8 Diagnostics

The framework SHOULD expose human-readable diagnostics for:

- update failures;
- processor preparation failures;
- resource-budget violations;
- incompatible generation transitions;
- rejected artifacts;
- unsupported capabilities;
- event overflow;
- processor execution faults.

Detailed diagnostics MAY be omitted from the packet path and generated from bounded identifiers outside it.
