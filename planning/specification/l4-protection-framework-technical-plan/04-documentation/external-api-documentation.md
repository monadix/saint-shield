# External Documentation for Framework Users

## Canonical format and site

Author version-controlled Markdown under `docs/user` and `docs/api`; build a static MkDocs-compatible site. Keep links and navigation generator-neutral so another renderer can replace MkDocs. Publish docs for latest stable and the maintained prior minor line.

Zig autodoc generated from `///`/`//!` is linked as a symbol index, not the primary guide. Examples are real build targets executed in CI.

## Information architecture

```text
docs/user/
├── index.md
├── quickstart.md
├── concepts/
│   ├── packets-batches-ownership.md
│   ├── processors-and-capabilities.md
│   ├── generations-and-updates.md
│   └── metrics-and-events.md
├── guides/
│   ├── write-native-processor.md
│   ├── choose-io-backend.md
│   ├── configure-workers-numa.md
│   ├── hot-update-and-rollback.md
│   ├── write-source-exporter-consumer.md
│   ├── policy-language.md
│   ├── stateful-rate-limiter.md
│   └── test-and-benchmark.md
├── reference/
│   ├── build-options.md
│   ├── capabilities.md
│   ├── errors-failure-policies.md
│   ├── metrics.md
│   ├── events.md
│   ├── artifact-content-types.md
│   ├── limits.md
│   └── support-matrix.md
├── operations/
│   ├── dpdk-setup.md
│   ├── af-xdp-setup.md
│   ├── troubleshooting.md
│   └── upgrade-rollback.md
└── compatibility/
    ├── policy.md
    └── migrations/<version>.md
```

## Processor documentation contract

Every standard processor page includes:

- use case and non-goals;
- required packet/input/output capabilities;
- artifact content type/version and complete example;
- preparation/runtime resource formulas and defaults;
- state/update modes;
- packet mutation/dispositions/actions;
- metrics/events with bounded labels/payloads;
- failure and exhaustion behavior;
- deterministic test harness example;
- performance envelope and benchmark conditions;
- security considerations.

Third-party processor authors get the same template and conformance checklist.

## Reference formats

- Policy language: versioned EBNF, type/availability truth tables, examples, error-code catalogue, formatter behavior, compatibility rules.
- Structured artifacts: JSON Schema only if the artifact is JSON; otherwise a binary schema/grammar and test vectors. Do not describe a byte protocol only with pseudocode.
- Metrics: name, type, unit, meaning, reset/lifecycle, bounded label domain, cardinality formula.
- Events: stable type/version, typed bounded fields, privacy/cardinality notes, overflow policy.
- Build/source API: exact supported Zig version and import/build examples.

## Examples as tests

Every guide's code is compiled and run where feasible. Quickstart uses synthetic I/O so no privilege/hardware is required. DPDK/AF_XDP guides have a separately tested preflight command and show actual adapter-mode diagnostics. Snippets that cannot be compiled are marked illustrative.

## API change documentation

Every release has `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`, and `performance` sections as applicable. Migration guides show before/after code, semantic changes, artifact compatibility, operational impact, and rollback.

## Avoided documentation mistake

Do not turn internal layout or current algorithms into public guarantees. User docs explain observable semantics and performance conditions; internals docs explain current implementation. Cross-link them without conflating stability.

