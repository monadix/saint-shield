# Testing module

## Responsibility

`testing` provides bounded seeded traces and the public
`ProcessorTestHarness(PipelineType)`. It exercises the real synthetic queue,
packet, disposition, and generated pipeline contracts without production
traffic.

## Requirements and invariants

The module supports FR-TEST-001/002 diagnostics and the archived requirement
that randomized failures identify seed, exact Zig toolchain, and minimized
trace. The harness must reconcile every received synthetic token.

## Public contract

One harness prepares one static generation and generation-checked worker handle. Submission accepts bytes
or segments, origin, deterministic monotonic time, and fixed typed input
metadata. Results own copied final packet bytes and expose dispositions,
stage/error status, completion state, and resource accounting.

## Dependencies

The harness depends on public `foundation`, `packet`, `pipeline`, and
`io.synthetic` contracts. Seeded trace support imports only Zig standard
library facilities.

## Object lifecycle and ownership

The harness owns the prepared and worker pipeline. Worker cleanup precedes
prepared cleanup. A result owns its copied bytes. Received tokens are completed
on success and reconciled before any returned failure.

## Concurrency

One test thread owns a harness or seeded trace. Parallel property runs use
independent instances and independently recorded seeds.

## Allocation and work bounds

Harness setup and owned result copies may allocate through the supplied test
allocator. Pipeline packet processing uses fixed metadata and records zero
hot-path allocator calls. `SeededTrace` uses fixed storage.

## Failure behavior

Initialization and submission failures unwind pipeline state and token
ownership deterministically. Exhaustive allocation-index sweeps cover public
prepare, instantiate, synthetic submission, result copying, and cleanup paths.
Trace overflow is explicit through `truncated` and never writes past fixed
storage.

## Security boundary

Inputs are repository-owned synthetic fixtures. The harness opens no device,
socket, capture source, or external system.

## Performance budget

The harness is test-only and not used in production packet workers. Its
instrumentation records the production contract without changing the direct
pipeline call shape.

## Tests and evidence

M3 tests cover partial metadata validity, mixed terminal outcomes, empty
batches, cleanup sweeps, and all error policies. Seeded reference tests use
fixed seed `0x4d33524546455245` and print a bounded trace on mismatch.

## Alternatives and evolution

Hot updates, metrics collection, and event collection remain absent until
their predecessor-gated milestones. The harness remains reusable by those
future features.

## Open questions

None for M3.
