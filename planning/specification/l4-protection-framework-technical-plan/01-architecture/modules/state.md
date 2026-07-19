# Module: Reusable Bounded State

## Responsibility

Provide optional worker-local fixed-capacity maps, application-defined keys, expiry scheduling, counters/meters, exhaustion policies, and explicit generation-transition hooks. It does not impose a universal flow tracker or make cross-worker consistency invisible.

## Flow affinity prerequisite

Strict per-key semantics in worker-local state require packets for a key to reach one worker during that state lifetime. The application chooses a key and configures NIC RSS/XDP steering or an explicit dispatcher. The framework validates available hash/queue metadata where possible and documents that asymmetric directions may hash differently.

If affinity cannot be provided, the processor must choose approximate replicated state, a dedicated owner/sharding stage, or shared synchronized state. It cannot claim strict worker-local semantics.

## Fixed table

Start with an open-addressed table using preallocated entry arrays, occupancy/generation markers, bounded probe count, and stable indices. Hash seed is application/randomly selected outside deterministic tests. Deletion uses tombstones or backward shift only after benchmarking and correctness tests. Resize is not allowed in the packet path.

Capacity exhaustion policies are explicit: reject-new, evict-expired, sampled/clock eviction, fail-open, fail-closed, or processor-defined. LRU is not the default because exact shared/linked LRU bookkeeping is costly; any eviction algorithm publishes its approximation.

## Expiry

A per-worker hierarchical timing wheel stores entry indices, not pointers. Each packet loop advances by a bounded number of ticks/entries using monotonic time. Long idle jumps process under a configured budget and carry debt; they do not scan the full table in one batch. Stale wheel records are detected by entry generation counters.

## Meters

Provide integer token-bucket and GCRA-like primitives using saturating checked arithmetic and monotonic ticks. Preparation validates rates, bursts, precision, and overflow horizon. Tests inject deterministic time. No floating point is required.

## Generation transitions

Containers attach a schema/semantic compatibility ID. Processor preparation chooses:

- retain unchanged;
- retain and lazily revalidate entry;
- build migrated candidate state off-path;
- flush at activation;
- keep old state until expiry while new entries use new state.

Unsupported or ambiguous transitions fail validation. Shared reuse across generations has explicit owner/ref lifetime; no generation silently treats bytes under a new key/value layout.

## Shared state alternative

The module may later provide sharded concurrent tables, but only with explicit consistency, synchronization, NUMA, and exhaustion semantics. It must be a separate type so choosing it makes the performance cost visible. Cross-worker global rate limiting can also use hierarchical local budgets periodically replenished off-path; that is approximate and must say so.

## Tests

- Reference map differential under random insert/find/delete/expire.
- Probe/tombstone wrap and full capacity.
- Expiry at boundaries, clock jumps, idle debt, stale wheel record.
- Meter arithmetic at zero/max/rate precision/overflow.
- Affinity violation diagnostics.
- Every exhaustion and generation-transition mode.
- State churn benchmarks at 50/80/95/100% occupancy with adversarial and normal keys.

## Requirement ownership

FR-STATE-001..006, Phase-4 state facilities, state portions of failure/resource/time requirements.

