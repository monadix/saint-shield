# Module: Metrics, Events, and Diagnostics

## Responsibility

Provide bounded registration, hot-path metric/event handles, weakly consistent snapshots, health/progress data, and off-path exporter/consumer contracts. It is not a monitoring database, dashboard, logger, or controller.

## Metrics registry

Processors declare descriptors at comptime or during preparation before publication. A descriptor contains stable ID/name, kind, unit, help, bounded label domains, aggregation semantics, and lifecycle. Label combinations are expanded/validated into a finite number of cells at activation. Packet-derived strings/addresses never become labels by default.

Handles are compact integer indices into worker storage. Counters use relaxed atomic addition because off-thread snapshots otherwise create a language-level data race. Gauges use relaxed stores; fixed-bucket histograms update one bucket plus count/sum according to documented semantics. If profiling proves atomic RMW cost material, the alternative is double-buffered worker-owned pages with a handshake at batch boundaries, not unsynchronized reads.

## Snapshot semantics

A snapshot aggregates per-worker cells outside packet workers and includes start/end monotonic timestamps, active/published generation IDs, worker contribution bitmap, and `weak` consistency marker. Values are not a transactional view across workers. Monotonic counters remain monotonic modulo explicit reset/restart metadata.

Core descriptors include every metric listed in the source requirements plus:

- worker-published versus worker-observed generation;
- QSBR grace age and retire-queue bytes;
- adapter mode/offload capability info;
- outstanding retention leases;
- output partial-submit/drop counts;
- preparation budget peak/limit;
- snapshot/exporter/consumer own health.

## Events

Each worker produces to its own SPSC ring. An event slot has fixed header fields and up to the configured bounded payload. Schemas are registered before execution. Large/high-cardinality content uses bounded typed fields or references to off-path data owned by the consumer; the worker never formats JSON or strings.

Policies per event type: always-until-full, deterministic sample, token-bucket rate limit, aggregate-to-metric, or disabled. Overflow is drop-newest initially; overwrite-oldest is unsafe for a concurrent consumer unless separately implemented and modeled. Every non-accepted outcome increments a metric.

One drain context consumes all worker rings and may fan out owned copies to multiple consumers. A slow consumer gets its own bounded queue/drop policy or is detached; it never stalls ring draining globally without application opt-in.

## Exporters/consumers

First metrics exporter is a Prometheus scrape module. It obtains/caches a snapshot outside workers and serves the standard text format. It binds localhost by default. A future OTLP exporter translates the same snapshot contract.

First event consumers are a compact versioned binary stream for production and JSON Lines for debugging. The binary format carries schema/version records and checksums; it is not a public stable network protocol until explicitly versioned.

## Tests

- Registry rejects duplicate IDs, unbounded labels, excessive cell count, invalid histogram boundaries.
- Concurrent snapshot while workers update; exact bounds and monotonicity appropriate to weak semantics.
- Ring wraparound, full/empty races, overflow, sampling/rate limit, worker shutdown.
- Block exporter/consumer indefinitely while packet throughput continues.
- Cardinality attack artifacts fail preparation.
- Prometheus golden output and parser compatibility.
- Microbench every metric/event mode enabled/disabled/full.

## Requirement ownership

FR-OBS-001..009, all Section 6 requirements, AC-008..009.

