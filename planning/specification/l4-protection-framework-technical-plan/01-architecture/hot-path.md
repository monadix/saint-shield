# Packet Hot Path and Scheduling

## Baseline scheduling model

Use one long-lived OS thread per RX queue. Pin it to one physical CPU or SMT sibling chosen by deployment policy; allocate queue buffers, scratch space, processor worker state, metrics, and event ring on the NIC-local NUMA node. The worker runs receive → process → transmit to completion. Management and exporter work never runs on that thread.

This matches the required run-to-completion semantics and DPDK's own per-queue/private-resource guidance. A stage-per-core graph would add rings, ownership transfers, cache movement, and queue overload policies before any processor demonstrates enough cost to require it.

## Batch representation

`max_batch` is a build/runtime assembly parameter constrained to a supported range, initially 1..64. Public APIs do not expose 64 as a semantic maximum. Internal Phase-1 selection uses one `u64`; a word-slice implementation is introduced before supporting larger batches.

The batch stores structure-of-arrays only where every processor benefits:

- packet slots in receive order;
- active bitset;
- terminal disposition tag per slot;
- output/reason identifiers per slot;
- lazy parsed-field cache per slot;
- compile-time laid-out stage metadata.

Do not globally convert all packet metadata to SoA at first. Profile field access and introduce a specialized layout only for demonstrably batch-classified fields. This avoids optimizing one policy engine at the expense of ordinary native processors.

## Dispatch

Application code constructs `Pipeline(.{ ProcessorA, ProcessorB, ... })`. The compiler verifies each processor's declaration and produces a direct ordered `processBatch` call per processor. There is no vtable lookup per packet. A processor may internally use a prepared jump table for actions or rules.

A batch-level type-erased pipeline adapter is permitted later for applications that must choose among precompiled pipeline variants at startup. It may dispatch once per processor per batch, never once per packet. Runtime loading of arbitrary native code is separate and deferred.

## Work bounds

Every processor declaration includes a cost category and any configurable loop bound. Preparation rejects artifacts that violate:

- maximum rules/instructions/actions evaluated per packet;
- maximum packet extension-header walk;
- maximum event bytes and emissions per batch;
- state operations and retry/probe bound;
- maximum outputs/retentions;
- total prepared and worker-local bytes.

The runtime does not pretend every processor has constant cost; it requires an enforceable bound or a configured budget-exhausted outcome.

## Idle behavior

Busy polling is the throughput baseline. An optional adaptive-idle policy may spin, pause, then use a backend wait/interrupt facility after a documented idle threshold. It must be disabled in reference throughput benchmarks. AF_XDP should use `XDP_USE_NEED_WAKEUP`; DPDK power/monitor features are adapter options.

## Error handling in a batch

Hot-path errors are small enums, never allocated diagnostic strings. The processor descriptor declares one of:

- errors are impossible after successful preparation;
- per-packet error maps to a configured disposition;
- processor-wide batch error maps remaining active packets;
- fatal invariant breach stops the worker/runtime.

Human-readable diagnostics are reconstructed outside the worker from generation, processor, bounded error, and optional rule identifiers.

## Performance-sensitive rules

- No logging or exporter call in `processBatch`.
- No shared RX/TX queue between workers.
- No allocation through the general allocator.
- No wall clock, DNS, file, socket, mutex, or condition-variable call.
- Prefetching is introduced only with perf-counter evidence; prefetch distance is adapter/CPU tunable.
- Hardware checksum/RSS/offload metadata must be capability-probed, never assumed.
- Benchmarks report both SMT disabled and actual deployment topology when relevant.

