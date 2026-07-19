# Module: Test Harness and Developer Tools

## Test harness API

The harness assembles the real pipeline/update/observability code over the synthetic adapter. It provides:

- packet construction from bytes, segmented bytes, capture records, or helper builders;
- explicit input origin and deterministic monotonic time;
- install/startup preparation and candidate activation;
- scripted output capacity/failure/completion;
- resulting bytes, dispositions, ownership trace, metrics, events, generation IDs, and diagnostics;
- hooks at publication, worker acquire, batch end, event push/pop, and output submit for deterministic interleavings.

The harness is a public supported module, not test-only private scaffolding, because processor authors need it.

## Fixture format

Use small human-readable YAML/JSON only as a test case envelope, not policy semantics. Packet bytes are hex or referenced PCAP. Expected values use stable IDs. Each fixture declares framework/version assumptions and has a unique conformance ID.

Fixtures generated from captures must remove secrets and include provenance/license. Golden binary outputs are regenerated only through a reviewed command and diff summary.

## Reference models

Keep deliberately simple implementations for:

- selection/disposition sets;
- packet checksum/length validation (plus Scapy integration oracle);
- update generation model in deterministic single thread;
- policy typed-IR evaluator;
- map/expiry/meter behavior;
- metric aggregation and event policy.

Optimized implementations never replace their own oracle.

## Developer executables

- `artifact-inspect`: parse/validate, resource report, semantic digest, diagnostics.
- `policy-check`: format, validate, explain packet/capture, compare two policies.
- `replay`: run capture through synthetic pipeline and emit dispositions/capture/events.
- `benchctl`: record environment, execute benchmark matrix, validate results schema, compare against a baseline.

Only `replay` shares runtime code; command parsing/output formatting is outside core libraries.

## Requirement ownership

FR-TEST-001..006, deterministic-time requirement, AC scenarios as executable fixtures, and production quality-gate evidence.

