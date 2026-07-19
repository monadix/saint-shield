# Module: Processor Contract and Pipeline Runtime

## Responsibility

Validate native processor types, build the ordered pipeline, calculate required scratch/capabilities, create worker instances, execute one coherent batch, resolve errors/defaults, and clean up deterministically. It does not acquire artifacts or publish generations.

## Compile-time validation

For each processor, validate:

- stable ID and API version;
- required functions and exact error/return categories;
- declared packet access, dispositions, outputs, time, state, metrics, events, and metadata;
- prepared and worker type ownership/deinit;
- resource estimate functions for configurable state;
- update-state modes;
- no duplicate producer for exclusive metadata slots;
- consumed metadata is produced earlier or supplied by input.

Errors identify the processor and missing/incompatible declaration.

## Prepared and worker layout

The generated `PreparedPipeline` is a tuple of processor prepared objects. `WorkerPipeline` is a tuple of worker objects. Both are destroyed in reverse construction order; partial construction uses `errdefer`. Shared immutable prepared parts are pointer-stable for the generation lifetime.

The generated batch/context type contains only the union of capabilities. A metadata layout pass assigns fixed offsets/types to stage-produced values, avoiding string maps and per-packet allocation.

## Execution

```text
for processors in declared order:
    if active is empty: break
    call processor.processBatch once
    validate returned status/disposition constraints
finalize active/default dispositions
```

The processor may visit packets scalar, by selection word, or in SIMD groups. The pipeline does not force a callback per packet. A processor that declares only `Drop` cannot redirect; safe builds assert this and preparation makes such an error unreachable.

## Fault boundary

Zig native panics/illegal behavior are not ordinary processor errors and cannot be reliably recovered in-process. ReleaseSafe invariant panic stops the affected application according to root panic policy. Expected parse, state, capacity, or action failures are explicit return values and must not panic.

## Runtime reorder

Changing processor configuration is supported. Changing processor types or order is rebuild/restart in the baseline. If real applications require runtime order changes, compile a finite set of validated pipeline variants and select one at startup or generation preparation; do not introduce an unbounded plugin graph.

## Tests

- Comptime negative tests for each descriptor/signature/capability mismatch.
- Ordered three-processor scenarios with mixed terminal/non-terminal packets.
- Empty active-set short circuit and empty receive behavior.
- Every failure policy and error-to-disposition mapping.
- Partial instantiate failure destroys exactly constructed parts in reverse.
- Random generated processor models compared to a simple reference runner.
- Microbench: 0, 1, 2, 4, 8 no-op processors; static versus deliberately type-erased batch calls.

## Requirement ownership

FR-COMP-001..003, FR-COMP-005..006, FR-PROC-001..009, FR-PKT-014..015, FR-EXT-001..003, AC-003, AC-012.

