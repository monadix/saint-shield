# M3 native processors and static pipelines

Saint Shield 0.3.0-m3 adds application-defined native Zig processors and a
compile-time ordered pipeline. It remains hardware-free: the public harness and
example use synthetic packets, and the benchmark is host-local regression
evidence rather than a production-capacity result.

## Processor contract

Each processor type declares a `ProcessorDescriptor`, `Prepared`, `Worker`,
`estimateResources`, `prepare`, `instantiate`, `processBatch`, `deinitWorker`,
and `deinitPrepared`. The descriptor records stable processor/API identity,
packet and disposition capabilities, artifact requirements, typed metadata,
bounded work, state-update schema/default, error policy, and resource
categories. `m3-compile-fail` rejects incomplete or inconsistent declarations
with processor-specific diagnostics.

`prepare` runs outside packet processing with a counted hard-limit allocator.
Worker state is constructed before the pipeline is runnable. Both tuples are
constructed in application order and destroyed in exact reverse order,
including partial failures.

## Restricted packet contexts

The generated context type exposes only declared abilities:

- metadata-only processing;
- checked copies and length/origin observations for read access;
- selected structured edits and explicit finalization;
- trusted raw writes only when both descriptor and application opt in;
- only declared dispositions and outputs;
- fixed typed metadata values and validity selections.

No processor result returns a batch owner, adapter token, slot pointer, packet
slice, unrestricted disposition state, or retained borrow. Context cookies are
valid only during the direct `processBatch` call.

## Assembly and execution

Use `Pipeline(.{ ProcessorA, ProcessorB })` without typed application input
metadata. Zig 0.16 has no default function parameters, so pipelines with
inputs use the explicit equivalent
`PipelineWithInputMetadata(.{...}, MetadataKeys(.{...}))`.

Assembly validates every capability and estimate before calling the first
processor `prepare`. `ResourceLimits` includes prepared bytes, per-worker and
worker-count totals, metadata scratch, bounded pools, and maximum batch work.
Checked overflow, exact limit, one-byte excess, worker multiplication,
underestimation, and unavailable capability all reject before a runnable
pipeline is returned. Application output IDs are validated and copied into the
prepared owner; the caller-owned capability slice is not retained.

Execution calls each non-empty stage exactly once. Terminal packets never
reach later stages. A stage error follows only its explicit policy: continue
active packets, apply a non-retaining terminal disposition, or apply that
disposition and request stop. Existing terminal packets are never overwritten.
Remaining `Continue` packets are resolved only through the supplied pipeline
policy. Before the first callback, the pipeline validates the complete
`DispositionConfig`: its bounded unique output table, application membership,
every output declared by the generated processors, explicit `Continue`
routing, and any default required by nullable processor acceptance. Invalid
routing returns `DispositionFailure` without invoking a processor or changing
packet bytes.

If any pipeline-detected error is returned after a callback has run—including
a processor work-contract breach or disposition-resolution failure—the
pipeline invalidates that exact batch generation first. Existing batch, view,
editor, iterator, and output handles then reject as stale/released; no partial
`ExecutionResult` is returned. Adapter-token reconciliation remains the
caller's responsibility and the public harness performs it exactly once.
Because an escaped raw slice or adapter token cannot be revoked, its prior
issuance rejects pipeline entry before any callback instead.

## Public synthetic harness

`ProcessorTestHarness(PipelineType)` prepares one static generation and runs
real synthetic input, pipeline, and output contracts. Fixtures accept bytes or
segmented bytes, explicit origin, deterministic monotonic time, and typed input
metadata. Results own copied final bytes and expose final dispositions,
stage/error status, token completion, and resource accounting. The harness
reconciles received synthetic tokens on both success and failure.

Hot updates, metrics collection, and event collection are intentionally absent
until their predecessor-gated milestones.

M3 also rejects every retention declaration. It does not mint a lease or token,
and a native processor cannot extend packet authority beyond its direct call.
Metric and event declarations are concrete compile-time tuples with stable IDs,
inline value/payload types, and explicit finite bounds; only their schemas are
negotiated in M3, not runtime handles.

Prepared state owns a configured number of workers. Its copyable `WorkerHandle`
contains only scalar owner identity, slot, and generation values; processing,
resource observation, and teardown also require the separately live prepared
owner. Destroying prepared state while any worker is live fails, and wrong-owner,
forged, stale, or recycled handles fail without dereferencing released worker
storage. Construction allocators are separate per stage and sealed before
return. A retained allocator copy cannot allocate, resize, remap, or free on the
packet path; the owner opens free-only cleanup authority while invoking the
matching destructor.

The benchmark constructor is part of the M3 allocation-failure suite. Every
ownership-transfer error returns received tokens, workers and prepared
pipelines unwind in exact reverse order, and successful teardown uses the same
order. These checks compile and run without executing performance samples.

Resource limits include exact generated `PreparedPipeline` and `WorkerPipeline`
storage, per-stage tuples/budget state, processor estimates, and the full fixed
`MetadataStore`. `worker_count` is both the checked multiplication input and the
maximum number of simultaneously live workers. The declared worst-case formula
and accepted estimate bound every runtime work result.

## Commands and limits

```sh
nix develop --command zig build m3-test
nix develop --command zig build m3-compile-fail
nix develop --command zig build m3-example
nix develop --command zig build m3-cross-aarch64
nix develop --command zig build m3-bench-compile -Doptimize=ReleaseFast
nix develop --command zig build m3-bench-gate
nix develop --command zig build m3-bench-evidence
nix develop --command zig build m3-bench-evidence-self-test
```

The benchmark gate requires a clean committed tree and launches seven warmed
ReleaseFast processes. It retains per-run raw samples and aggregates, binds the
raw stream, full benchmark inputs, generation configuration, commit and tree,
then recomputes every statistic and the `>= 0.95` ratio threshold. Use
`python3 tools/m3/benchmark-gate.py --retain bench/examples/benchmark.m3.json`
only when intentionally refreshing the checked-in artifact.

The monolith and batch-vtable variants omit portions of the production pipeline
context/authentication/accounting path. Their samples are retained only as
non-comparable diagnostics and are excluded from acceptance and architecture
decisions. The validator checks a complete variant-order permutation for every
run/batch/sample and recomputes packet rate, nanoseconds per packet, and cycles
per packet from raw counters within the recorded decimal-print tolerances.

The example composes metadata production/read, mixed filtering, and final
acceptance. AArch64 is ReleaseSafe build-tested only. M3 records update-state,
metric, and event schemas but performs no live generation update and provides
no metrics/event runtime. Dynamic plugins, reusable state runtime, sources,
production adapters, and policy execution remain out of scope.
