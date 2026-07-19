# Executive Summary

## Architecture in one paragraph

An application composes a statically known tuple of native Zig processors into a typed pipeline. A worker owns one receive queue, packet-descriptor scratch space, processor-local state, metrics cells, an event ring, and normally one transmit queue per output. It receives a partial burst, creates backend-neutral packet slots that preserve backend ownership tokens, acquires one immutable generation at the batch boundary, runs active packets through processors in order, finalizes mutations, submits terminal packets to outputs, and reports a quiescent state. A management context prepares complete replacement generations off-path, validates budgets and capabilities, atomically publishes one pointer, and reclaims old generations only after every online worker has crossed the publication epoch.

## Why this baseline

The requirements emphasize stable semantics, bounded packet work, batching, native Zig extensions, and application-controlled deployment. They do not justify a general graph scheduler, dynamic native ABI, separate control-plane process, or mandatory bytecode VM. The recommended design therefore keeps the fast path small and typed, while moving flexibility into build-time composition and immutable prepared data.

DPDK is the first production I/O adapter because its poll-mode, per-queue ownership, burst operations, NUMA placement, and run-to-completion model closely match the required runtime. It is not exposed through public processor APIs. AF_XDP remains a first-class planned adapter because it permits a NIC to remain under the normal Linux driver and can share RX/TX UMEM, but its performance and zero-copy availability are more dependent on driver, queue, and flow-steering support. The synthetic adapter is implemented first because correctness, updates, and policy semantics must be testable without privileged hardware.

## Most consequential decisions

| Area | Decision | Cost accepted | Why the cost is justified |
| --- | --- | --- | --- |
| Dispatch | Compile-time processor tuple; direct batch calls | Rebuild to change processor types/order | Avoids universal ABI and per-packet dynamic dispatch; configured data still hot-updates |
| I/O | Neutral ownership contract; DPDK first production adapter | Adapter translation layer | Prevents DPDK types and lifetime rules from becoming framework API |
| Updates | Immutable generation + QSBR at batch boundary | Old generations consume memory until grace period | No reader refcount per batch and coherent generation for all processors |
| Packets | Opaque storage token plus bounded segment access | Slightly richer API than a raw mutable slice | Supports DPDK chains and AF_XDP multi-buffer later without breaking processors |
| Mutation | Structured editor by default; raw editor capability only for trusted processors | Finalization bookkeeping | Centralizes bounds, length, and checksum correctness |
| Metrics | Pre-registered fixed cells, relaxed atomics, weak snapshots | Snapshot is not transactional | Eliminates exporter calls and dynamic labels from the packet path |
| Events | Per-worker bounded SPSC rings | One drain stage and explicit loss | Makes consumer stalls harmless to packet workers |
| Policy | Typed IR and bounded interpreter first | Lower initial peak performance than specialized codegen | Establishes semantics, explanation, and differential oracle before optimization |
| State | Worker-local fixed-capacity shards | Flow affinity is required for strictly per-flow behavior | Avoids contended global state and makes exhaustion explicit |
| Formal work | TLA+ only for update/reclamation and ring protocols | Additional model maintenance | These protocols fail in interleavings that ordinary unit tests sample poorly |

## What is intentionally not selected

- No separate `control-plane` binary in the framework. Applications can put update sources in-process, local-process, or remote-controller topologies.
- No mandatory eBPF/XDP policy execution. XDP is used only to redirect traffic for the AF_XDP adapter; optional executors remain processors.
- No universal flow object. Stateful modules accept application-defined keys.
- No runtime-loaded native plugin ABI before a concrete deployment requires it.
- No OpenTelemetry SDK in the dataplane. An OTLP exporter can translate snapshots outside workers later.
- No JIT in the first policy engine. It expands attack surface and makes determinism and W^X deployment harder before there is evidence it is needed.

## Delivery shape

The roadmap contains thirteen evidence-gated increments, M0 through M12. The first six produce a useful static native framework with a production DPDK adapter. M6 through M8 add atomic updates, sources, and bounded observability. Policy and state arrive only after the lifecycle is trustworthy. AF_XDP and optional executors come after the core benchmark and compatibility boundaries are stable.
