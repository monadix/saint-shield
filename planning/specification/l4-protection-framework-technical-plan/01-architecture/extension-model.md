# Extension Model

## Native processor shape

The concrete Zig API should follow this type pattern rather than a runtime universal interface:

```zig
pub fn Pipeline(comptime ProcessorTypes: tuple) type { ... }

const MyProcessor = struct {
    pub const descriptor: ProcessorDescriptor = ...;
    pub const Prepared = ...;
    pub const Worker = ...;

    pub fn prepare(artifact: ?Artifact, ctx: PreparationContext) !Prepared;
    pub fn instantiate(prepared: *const Prepared, worker: WorkerDescriptor) !Worker;
    pub fn processBatch(worker: *Worker, batch: anytype, ctx: anytype) ProcessResult;
    pub fn deinitWorker(worker: *Worker) void;
    pub fn deinitPrepared(prepared: *Prepared) void;
};
```

`anytype` in the illustrative hot call is concretized to a capability-restricted batch/context type by the pipeline builder. Compile-time validation reports a readable error if declarations or signatures are missing.

## Optional executors

A standard policy engine, table classifier, eBPF executor, or Wasm runtime is a normal processor with a potentially untrusted artifact. It owns validation, instruction/memory budgets, prepared code/data, worker instances, failure policy, and explanation tooling. The core processor enum does not list executor technologies.

An executor may use batch-level indirect calls internally. It may not weaken packet ownership, call remote services, allocate without a bounded pool, or bypass generation publication.

## Registration without global registries

Fields, functions, actions, metrics, and events are registered through comptime tuples supplied to the specific processor/application assembly. Preparation builds compact numeric handles. This avoids process-global mutable registries, string lookups in the hot path, and initialization-order bugs.

If an application needs startup-selected modules, it builds a finite tagged union of compiled variants. Dynamic native loading is added only after a use case proves that rebuild/redeploy is unacceptable; it then gets a separate C-compatible ABI, process isolation recommendation, compatibility policy, and conformance suite.

## Sources, exporters, and consumers

These use batch/control-path vtables if runtime selection is useful because they execute off-path. Their contracts are object-safe, allocator-aware, and explicitly cancellable. A source submits artifacts to the application; it cannot mutate the active generation. Exporters receive immutable snapshots; consumers receive copied/owned event records.

## API evolution

- Public structs that applications initialize use options structs with defaults and reserved extension space only where C ABI is required.
- Zig-native APIs prefer constructors and opaque state over exposing layout.
- Capabilities have stable string/numeric identities and versioned semantic definitions.
- Optional modules version artifacts independently from the framework API.
- Deprecation lasts at least one minor line after a replacement is usable, except security fixes.

