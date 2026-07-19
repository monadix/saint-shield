# L4 Protection Framework Requirements and Abstract API Specification

This consolidated file is generated from the numbered specification sections in this archive.

# 0. Product Definition

## 0.1 Product identity

The product is a **Zig framework for building low-level Layer 4 network protection tools**.

It is a reusable library and set of public contracts, not a mandatory ready-made firewall, distributed controller, appliance image, or fleet-management product.

An application using the framework composes packet-processing extensions, configuration sources, update behavior, state facilities, and observability outputs into a concrete protection tool.

## 0.2 Primary users

The primary users are developers building tools such as:

- stateless and stateful L4 firewalls;
- DDoS mitigation components;
- packet filters and normalizers;
- SYN protection mechanisms;
- traffic classifiers and redirectors;
- rate limiters;
- custom L4 gateways or enforcement points;
- specialized packet inspection and mutation tools.

## 0.3 Product goals

The framework MUST:

1. make high-throughput packet processing a first-class use case;
2. allow applications to compose native Zig packet processors;
3. allow processor configuration to be loaded and replaced without coupling packet workers to configuration I/O;
4. support local metrics and event collection without blocking packet processing;
5. define stable packet, batch, lifecycle, update, and extension semantics;
6. permit optional standard extensions such as expression rules, table-based execution, BPF execution, or WebAssembly execution without making any of them fundamental framework concepts;
7. keep deployment topology under application control;
8. preserve deterministic and explainable behavior where the chosen processor supports it;
9. make resource usage and failure behavior explicit;
10. support incremental construction of increasingly capable protection products.

## 0.4 Product non-goals

The framework MUST NOT require or attempt to provide:

- a fleet-wide control plane;
- distributed policy coordination;
- leader election or consensus;
- operator authentication and authorization;
- persistent policy storage;
- global metrics storage or dashboards;
- service discovery;
- a mandatory policy language;
- a mandatory virtual machine or bytecode executor;
- a mandatory process split;
- a mandatory network protocol between configuration and packet processing;
- arbitrary remote calls in the per-packet path;
- transparent portability across every packet I/O environment at the cost of weakening packet-path guarantees.

## 0.5 Product principles

### P-01: Library before appliance

The framework exposes reusable components and contracts. A complete executable is an application built with the framework.

### P-02: Native extension model first

The fundamental extension mechanism is a native Zig processor contract. Other execution technologies are modules built on top of that contract.

### P-03: Logical separation, not forced deployment separation

Packet processing, update preparation, and observability have different execution constraints, but MAY coexist in one process and one machine.

### P-04: Packet path remains local

Packets MUST be processed from locally available policy and state. External communication MUST NOT be required to decide every packet.

### P-05: Stable semantics over maximum genericity

The framework MUST define stable packet ownership, batch behavior, update publication, and disposition semantics. It SHOULD avoid universal abstractions that erase behavior critical to performance or correctness.

### P-06: Optional features remain optional

The core framework MUST remain usable without an expression engine, BPF runtime, WebAssembly runtime, stateful flow tracker, remote configuration source, or a particular exporter.

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

# 2. Functional Requirements

## 2.1 Framework composition

**FR-COMP-001** The framework MUST be consumable as a Zig library.

**FR-COMP-002** An application MUST be able to select the set and order of packet processors.

**FR-COMP-003** The framework MUST NOT require a universal dynamic plugin ABI for statically linked applications.

**FR-COMP-004** The framework MAY additionally support runtime-loaded native extensions through a separately versioned ABI.

**FR-COMP-005** Optional standard processors MUST use the same processor contract available to application-defined native processors.

**FR-COMP-006** The core framework MUST NOT contain closed enumerations of supported execution technologies such as table, BPF, or WebAssembly executors.

## 2.2 Packet processing

**FR-PKT-001** The framework MUST expose packets to processors in batches.

**FR-PKT-002** A batch MUST preserve packet order as received from its input queue unless a processor explicitly changes routing or ordering.

**FR-PKT-003** A batch MUST identify its input origin sufficiently for processors to distinguish configured inputs and queues.

**FR-PKT-004** The framework MUST process a partial batch without waiting for a configured maximum batch size.

**FR-PKT-005** The framework MUST NOT imply that packets in a batch belong to the same flow or rule class.

**FR-PKT-006** A processor MUST be able to inspect packet bytes and framework metadata.

**FR-PKT-007** A processor MAY be granted mutation capabilities by the application and framework configuration.

**FR-PKT-008** Packet mutation capability SHOULD be narrower than unrestricted writable access for ordinary processors.

**FR-PKT-009** Trusted processors MAY receive unrestricted packet access where required.

**FR-PKT-010** Processors MUST be able to mark subsets of a batch with dispositions without forcing immediate per-packet callbacks.

**FR-PKT-011** The framework MUST define ownership of packets that are dropped, transmitted, redirected, retained, or left active.

**FR-PKT-012** A processor MUST NOT retain a packet or batch reference beyond the lifetime granted by the framework unless it explicitly transfers ownership through a framework-supported mechanism.

**FR-PKT-013** The framework MUST support one or more configured packet outputs.

**FR-PKT-014** The framework MUST support run-to-completion processing as a baseline execution model.

**FR-PKT-015** Alternative execution models MAY be added if they preserve public processor semantics.

## 2.3 Processor lifecycle

**FR-PROC-001** Every configurable processor MUST separate configuration preparation from packet-time execution.

**FR-PROC-002** Configuration preparation MUST be callable outside packet workers.

**FR-PROC-003** Configuration preparation MAY allocate, parse, compile, perform local I/O, and return detailed errors.

**FR-PROC-004** Packet-time execution MUST obey packet-path constraints defined in this specification.

**FR-PROC-005** A processor MUST be able to create worker-local state from prepared configuration.

**FR-PROC-006** A processor MUST provide deterministic cleanup for prepared and worker-local state.

**FR-PROC-007** The framework MUST define ordering between processor preparation, worker instantiation, activation, retirement, and destruction.

**FR-PROC-008** A processor MUST be able to declare resource requirements before activation.

**FR-PROC-009** Activation MUST fail before publication when declared mandatory resources cannot be satisfied.

## 2.4 Configuration sources

**FR-SRC-001** Configuration acquisition MUST be independent from configuration interpretation.

**FR-SRC-002** A configuration source MUST be able to emit versioned artifacts.

**FR-SRC-003** Artifacts MUST carry enough identity to detect stale, duplicated, or out-of-order updates when the application requests such enforcement.

**FR-SRC-004** Sources MAY block, allocate, retry, and use external I/O because they operate outside packet workers.

**FR-SRC-005** The framework MUST allow an application to supply artifacts directly without using a source abstraction.

**FR-SRC-006** Standard source modules MAY include static, file, watched-file, stream, or remote sources, but none is mandatory.

## 2.5 Update and generation management

**FR-UPD-001** The framework MUST prepare an update fully before making it visible to packet workers.

**FR-UPD-002** Activation MUST publish a complete generation atomically from the perspective of each worker.

**FR-UPD-003** A worker MUST NOT observe a mixture of incompatible processor configurations from two generations.

**FR-UPD-004** Workers MAY begin using a generation at different safe boundaries, provided each individual batch is processed under a coherent generation.

**FR-UPD-005** Failed preparation MUST leave the active generation unchanged.

**FR-UPD-006** Failed activation MUST leave either the previous generation active or produce a clearly reported fatal runtime state; partial silent activation is forbidden.

**FR-UPD-007** The framework MUST delay destruction of a retired generation until no worker can reference it.

**FR-UPD-008** The framework SHOULD support activation rollback to a retained compatible generation.

**FR-UPD-009** The application MUST be able to select behavior for existing state when a new generation becomes active, within capabilities exposed by processors.

**FR-UPD-010** The framework MUST expose generation identity and update status to observability APIs.

## 2.6 Native and optional execution extensions

**FR-EXT-001** Native Zig processors are the primary extension mechanism.

**FR-EXT-002** An optional executor, including an expression engine, table engine, BPF runtime, or WebAssembly runtime, MUST be implementable as a processor module.

**FR-EXT-003** Optional executors MUST NOT require changes to packet-runtime semantics.

**FR-EXT-004** Optional executors MUST define their own artifact validation, preparation, resource limits, and worker instantiation.

**FR-EXT-005** Optional executors MUST expose bounded failure behavior and MUST NOT perform remote per-packet execution unless an application explicitly constructs such behavior outside normal conformance.

**FR-EXT-006** Standard optional executors SHOULD serve as reference implementations of the public processor contract.

## 2.7 State facilities

**FR-STATE-001** The framework MUST permit processors to maintain worker-local mutable state.

**FR-STATE-002** The framework MAY expose reusable bounded state facilities.

**FR-STATE-003** Reusable state facilities MUST define capacity, ownership, lifetime, and exhaustion behavior.

**FR-STATE-004** Shared mutable state in the packet path SHOULD be avoided unless the processor explicitly accepts the synchronization cost.

**FR-STATE-005** State migration or retention across generations MUST be explicit.

**FR-STATE-006** The framework MUST NOT silently reinterpret processor state under a new configuration generation.

## 2.8 Metrics and events

**FR-OBS-001** Packet workers MUST be able to update local metrics without calling exporters.

**FR-OBS-002** The framework MUST expose local metric snapshots.

**FR-OBS-003** Exporters MUST consume snapshots outside packet workers.

**FR-OBS-004** Detailed events MUST use bounded queues or an equivalent bounded asynchronous mechanism.

**FR-OBS-005** Packet workers MUST NOT block waiting for an event consumer.

**FR-OBS-006** Event overflow behavior MUST be explicit and observable.

**FR-OBS-007** The framework MUST distinguish bounded metrics from high-cardinality events.

**FR-OBS-008** Application-defined processors MUST be able to register bounded metrics and event schemas.

**FR-OBS-009** The framework MUST expose core runtime health measurements independent of processors.

## 2.9 Testing and diagnostics

**FR-TEST-001** The framework MUST make processors testable without live production traffic.

**FR-TEST-002** A test harness MUST be able to submit synthetic packets or captured packet sequences.

**FR-TEST-003** The test harness MUST expose resulting packet dispositions and mutations.

**FR-TEST-004** Update preparation and activation behavior MUST be testable deterministically.

**FR-TEST-005** The framework SHOULD support an explanation or trace facility for processors that can provide one.

**FR-TEST-006** Diagnostic facilities MAY allocate and execute outside packet-path constraints.

# 3. Abstract API Contracts

The signatures below are language-neutral contracts expressed in pseudocode. They define observable behavior, not internal representation.

## 3.1 Application assembly

```text
FrameworkApplication {
    inputs: PacketInput[]
    outputs: PacketOutput[]
    processors: ProcessorBinding[]
    runtime_policy: RuntimePolicy
    observability: ObservabilityConfiguration
}
```

Requirements:

- Processor order MUST be explicit.
- Input-to-worker and output routing policy MUST be explicit or have documented defaults.
- Application assembly MUST fail before packet processing begins if mandatory processor capabilities are unavailable.
- Application assembly MAY be static at build time, dynamic at startup, or a mixture of both.

## 3.2 Processor module

```text
interface ProcessorModule {
    describe() -> ProcessorDescriptor

    prepare(
        artifact: ConfigurationArtifact?,
        context: PreparationContext
    ) -> PreparedProcessor | PreparationError

    instantiate(
        prepared: PreparedProcessor,
        worker: WorkerDescriptor
    ) -> WorkerProcessor | InstantiationError

    process_batch(
        worker_processor: WorkerProcessor,
        batch: PacketBatch,
        context: ProcessingContext
    ) -> BatchResult

    retire_worker(worker_processor: WorkerProcessor)
    destroy_prepared(prepared: PreparedProcessor)
}
```

### ProcessorDescriptor

A descriptor MUST declare:

- stable processor identity;
- API compatibility version;
- required packet capabilities;
- possible packet dispositions;
- whether mutation is required;
- whether processor-local configuration is required;
- whether worker-local state is required;
- metrics and events that may be emitted;
- resource categories that can be estimated before activation.

### PreparationContext

The preparation context MAY provide:

- bounded allocators or resource budgets;
- application-provided services;
- capability discovery;
- logging and diagnostics;
- access to prior compatible prepared state when explicitly allowed;
- artifact metadata and provenance.

Preparation MUST NOT make new behavior visible to packet workers.

### ProcessingContext

The processing context MUST provide only packet-path-safe services.

It MAY include:

- worker identity;
- current generation identity;
- monotonic time access;
- worker-local metrics handles;
- bounded event emission;
- configured state facilities;
- configured output identifiers;
- processor metadata from previous stages.

It MUST NOT implicitly provide blocking I/O or unbounded allocation.

## 3.3 Packet batch

```text
PacketBatch {
    origin: InputOrigin
    packets: PacketHandle[]
    active: PacketSelection
    generation: GenerationId
}
```

Contract:

- `packets` is ordered.
- `active` identifies packets still available to the current processor.
- A processor MAY update the active selection through explicit disposition operations.
- Packet handles are valid only for the call unless ownership is transferred.
- A processor MUST NOT assume that the batch is full.
- A processor MUST NOT assume semantic similarity between packets.

## 3.4 Packet access

```text
interface PacketView {
    length() -> Integer
    read(range) -> BytesView | BoundsError
    metadata() -> PacketMetadataView
}

interface PacketEditor extends PacketView {
    set_supported_field(field, value) -> Result
    write(range, bytes) -> Result
    request_length_change(change) -> Result
}
```

Contract:

- Read operations MUST be bounds-checked by contract, whether enforced statically, dynamically, or through trusted caller requirements.
- Structured field mutation SHOULD preserve required packet consistency or mark it for framework finalization.
- Raw writes MAY be restricted to trusted processors.
- Mutation failures MUST be observable and MUST NOT silently corrupt packets.

## 3.5 Batch result and dispositions

```text
BatchResult {
    dispositions: PacketDispositionMap
    metadata_updates: ProcessorMetadataUpdate?
}

PacketDisposition =
    Continue
  | Accept(output?)
  | Drop(reason?)
  | Redirect(output, metadata?)
  | Retain(ownership_contract)
  | Complete(custom_completion_id)
```

Contract:

- `Continue` leaves a packet active for later processors.
- A terminal disposition removes a packet from ordinary later processing unless the application explicitly configures a compatible continuation.
- Every packet MUST have exactly one final completion outcome.
- Ownership consequences of every disposition MUST be documented.
- Drop reasons SHOULD use bounded identifiers rather than unbounded strings in the packet path.

## 3.6 Configuration artifact

```text
ConfigurationArtifact {
    source_id: StableIdentifier?
    revision: RevisionIdentifier
    content_type: ContentTypeIdentifier
    payload: Bytes | StructuredValue
    metadata: ArtifactMetadata
}
```

Contract:

- Artifact interpretation belongs to the receiving processor.
- The framework MUST preserve revision and provenance metadata through preparation diagnostics.
- The application MAY validate signatures or authorization before submission.
- A processor MAY reject unsupported content types.

## 3.7 Update session

```text
interface UpdateRuntime {
    begin_update(base_generation?) -> UpdateSession

    prepare_processor(
        session,
        processor_binding,
        artifact?
    ) -> PreparedUpdatePart

    validate(session) -> ValidationReport
    activate(session, activation_policy) -> GenerationId
    abort(session)
    rollback(target_generation) -> GenerationId
}
```

Contract:

- An update session represents one candidate generation.
- Activation MUST be all-or-nothing from the perspective defined in `FR-UPD-003`.
- `validate` MUST have no packet-visible side effects.
- `abort` MUST release candidate resources.
- Rollback MAY fail if a target generation was not retained or is incompatible.

## 3.8 Configuration source

```text
interface ConfigurationSource {
    start(sink: ArtifactSink) -> SourceHandle
    stop(handle)
}

interface ArtifactSink {
    submit(binding_id, artifact) -> SubmissionResult
    report_source_error(error)
}
```

Contract:

- Sources deliver artifacts; they do not directly mutate processor instances.
- Source retries, authentication, and transport behavior are source concerns.
- The application controls how submitted artifacts are grouped into update sessions.

## 3.9 Metrics interfaces

```text
interface MetricRegistry {
    register(descriptor) -> MetricHandle
}

interface WorkerMetrics {
    add(counter_handle, value)
    set(gauge_handle, value)
    observe(histogram_handle, value)
}

interface MetricsSnapshotProvider {
    snapshot(request) -> MetricsSnapshot
}

interface MetricsExporter {
    export(snapshot) -> ExportResult
}
```

Contract:

- Worker metric updates MUST be packet-path-safe.
- Exporters MUST NOT execute synchronously on packet workers.
- Metric descriptors MUST have bounded identity and label domains.
- Snapshot consistency guarantees MUST be documented.

## 3.10 Event interfaces

```text
interface EventRegistry {
    register(schema) -> EventTypeHandle
}

interface WorkerEvents {
    emit(event_type, bounded_payload) -> EmissionResult
}

interface EventConsumer {
    consume(events[]) -> ConsumptionResult
}
```

Contract:

- Emission MUST be bounded in time and storage.
- `EmissionResult` MUST indicate accepted, sampled-out, or dropped/overflowed outcomes where relevant.
- Consumers operate outside packet workers.

## 3.11 Test harness

```text
interface ProcessorTestHarness {
    install(processor_set, artifacts) -> TestGeneration
    submit(test_generation, packets, input_origin) -> TestResult
    activate_update(candidate_artifacts) -> TestGeneration
    collect_metrics() -> MetricsSnapshot
    collect_events() -> Event[]
}
```

The test harness MUST reproduce public processor semantics without requiring a production packet input.

# 4. Optional Standard Policy-Language Module

This section specifies an optional standard processor module. It is not part of the irreducible core framework.

## 4.1 Purpose

The module provides a declarative policy language for matching packets and local flow or metadata context, then applying actions.

The language SHOULD provide functionality comparable to rich Boolean packet filters and ordered address-control lists without copying the ambiguities of any particular existing syntax.

## 4.2 Expression model

**PL-EXP-001** A match expression MUST support Boolean composition using conjunction, disjunction, negation, and grouping.

**PL-EXP-002** A match expression MUST support typed comparisons.

**PL-EXP-003** A match expression MUST support membership in typed sets.

**PL-EXP-004** A match expression SHOULD support ranges where meaningful.

**PL-EXP-005** A match expression MUST support named predicates.

**PL-EXP-006** A match expression MAY call registered pure functions.

**PL-EXP-007** Match expressions MUST be side-effect free.

**PL-EXP-008** The module MUST define short-circuit behavior or explicitly permit equivalent optimized evaluation.

**PL-EXP-009** Optimization MUST NOT change observable match semantics.

Example capability:

```text
ip.source in trusted_networks
and (
    tcp.destination_port in web_ports
    or udp.destination_port == 443
)
and not ip.source in blocked_networks
```

## 4.3 Type system

The module SHOULD support at least:

- Boolean values;
- unsigned integers;
- IP addresses;
- IP prefixes;
- ports and port ranges;
- protocol identifiers;
- packet lengths;
- TCP flag sets;
- durations;
- bounded byte strings;
- named typed sets;
- registered application-defined types where supported.

Type errors MUST be reported during preparation, not packet execution.

## 4.4 Field availability

Protocol-specific and optional fields may be unavailable for a packet.

The module MUST define absent-aware semantics such that a comparison against an unavailable field does not accidentally match merely because the comparison is negated.

A conforming default is three-valued internal evaluation:

- true;
- false;
- unavailable.

A rule matches only when its top-level expression evaluates to true.

The exact internal representation is unspecified, but externally observable behavior MUST be equivalent.

## 4.5 Named sets

**PL-SET-001** The language MUST support named typed sets.

**PL-SET-002** Sets MAY be embedded in a policy artifact or resolved from separately supplied artifacts.

**PL-SET-003** Set update and policy update consistency MUST be explicit.

**PL-SET-004** The language MUST specify membership semantics independently of the internal data structure.

**PL-SET-005** Implementations MAY compile sets into any suitable representation.

## 4.6 Named predicates

**PL-PRED-001** The language MUST support reusable named predicates.

**PL-PRED-002** Predicates MUST be pure expressions.

**PL-PRED-003** Recursive predicate definitions MUST be rejected unless the language explicitly defines bounded recursion.

**PL-PRED-004** Predicate expansion or compilation MUST preserve type and field-availability semantics.

## 4.7 Ordered ACLs

The module SHOULD provide an ordered ACL construct with:

- named ACLs;
- ordered entries;
- explicit allow and deny entries;
- nested inclusion of named ACLs;
- first-match behavior;
- explicit default behavior.

ACL behavior MUST be distinct from general Boolean expression behavior.

An ACL MUST NOT rely on implicit defaults that change by call site.

Example capability:

```text
acl trusted_sources {
    deny 192.0.2.13
    allow 192.0.2.0/24
    include office_networks
    default deny
}
```

## 4.8 Rulesets

A ruleset MUST associate match expressions with actions.

A rule SHOULD have:

- stable identity;
- optional human-readable name;
- match expression;
- ordered actions;
- continuation behavior;
- optional bounded observability identifiers.

A ruleset MUST define a default outcome when no rule terminates processing.

Example capability:

```text
ruleset ingress {
    rule drop_blocked {
        when ip.source in blocked
        then drop(reason = blocked_source)
    }

    rule normalize_web {
        when tcp.destination_port in web_ports
        then set(ip.dscp, 10)
        continue
    }

    default accept
}
```

The concrete syntax is deliberately unspecified.

## 4.9 Actions

**PL-ACT-001** The module MUST support action registration by native processors or application modules.

**PL-ACT-002** Action argument types MUST be validated during preparation.

**PL-ACT-003** Actions MUST declare whether they are terminal, non-terminal, or selectable by policy syntax.

**PL-ACT-004** Terminal behavior SHOULD be explicit in the policy.

**PL-ACT-005** Effects such as packet mutation, metrics, events, state changes, rate limiting, or redirection MUST occur through actions, not match expressions.

**PL-ACT-006** An unknown action MUST cause preparation failure.

## 4.10 Field providers and pure functions

The module MUST permit native registration of additional fields and pure functions.

A field provider MUST declare:

- stable field name;
- value type;
- availability conditions;
- extraction requirements;
- whether extraction is packet-local or depends on configured state.

A pure function MUST declare:

- stable function name;
- argument types;
- result type;
- availability behavior;
- resource cost category where relevant.

## 4.11 Compilation and explanation

The module MAY compile expressions into tables, decision trees, native code, bytecode, vectorized evaluation, or other forms.

The module SHOULD provide:

- validation diagnostics tied to source locations;
- rule and predicate reference resolution;
- resource estimates;
- an explanation facility for a supplied packet and generation;
- deterministic policy hashing;
- optional shadow comparison of two prepared policies.

Internal compilation technology is not part of the public specification.

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

# 9. Deliberately Unspecified Decisions

The following choices are intentionally not fixed by this specification because they are implementation details, deployment choices, or future product decisions.

## 9.1 Packet I/O technology

The specification does not mandate a particular packet I/O library, driver model, operating system, kernel-bypass mechanism, or virtualization environment.

An implementation may provide one or more backends, provided public packet and batch semantics remain valid.

## 9.2 Internal threading and scheduling

The specification does not mandate:

- one thread per queue;
- number of queues per worker;
- polling strategy;
- cooperative scheduling;
- interrupt use;
- processor fusion;
- stage-per-core execution.

Implementations must merely satisfy the public lifecycle and packet-path constraints they claim.

## 9.3 Memory representation

The specification does not mandate:

- packet-buffer type;
- allocator;
- memory pool;
- zero-copy strategy;
- metadata layout;
- batch-mask representation;
- generation reclamation algorithm.

## 9.4 Processor dispatch

The specification does not mandate compile-time composition, runtime vtables, generated pipelines, inlining, code generation, or dynamic loading.

Static Zig composition is expected to be a natural baseline, but it is not an externally observable requirement beyond the Zig library product requirement.

## 9.5 Policy syntax

The policy module requirements define semantics, not concrete grammar.

The implementation may choose a syntax inspired by existing filter languages or define a new syntax, provided it satisfies the required capabilities and avoids ambiguous behavior.

## 9.6 Policy compilation

The specification does not mandate interpretation, bytecode, native code generation, decision trees, tables, vectorization, or JIT compilation.

## 9.7 State data structures

The specification does not mandate particular hash tables, prefix structures, eviction algorithms, or timer mechanisms.

## 9.8 Separate processes

The specification neither requires nor forbids separating local management/update functionality from packet processing.

A separate process is an application deployment option, not a core framework requirement.

## 9.9 Remote controller protocol

The framework exposes local artifact and update APIs. Any network protocol used by an external controller is outside scope.

## 9.10 Metrics protocol

The framework exposes snapshots and event streams. It does not mandate Prometheus, OpenTelemetry, a telemetry socket, JSON, or another protocol.

## 9.11 Dynamic native plugins

A runtime-loaded ABI is optional and should only be standardized after concrete use cases justify its compatibility and lifecycle cost.

## 9.12 Universal flow model

The framework does not impose a single flow key or state machine on all processors.

Reusable stateful modules may expose default L4 flow models, but applications and processors must remain able to define other identities where required.

