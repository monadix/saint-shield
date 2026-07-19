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
