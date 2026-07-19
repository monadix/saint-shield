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
