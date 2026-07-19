# Requirements Traceability

The canonical individual requirements and source locations are in `source-requirements/requirements.yaml`. Code tests use exact IDs in test names or fixture metadata. This table assigns design and milestone ownership; it does not weaken any individual MUST.

| Requirements | Design owner | First complete milestone | Primary evidence |
| --- | --- | --- | --- |
| P-01..P-06 | root architecture | M5, maintained thereafter | package/dependency/API review |
| FR-COMP-001..003 | pipeline | M3 | build consumption, static composition, no ABI dependency |
| FR-COMP-004 | deferred dynamic ABI | Not before M11/use case | separate ADR/conformance if implemented |
| FR-COMP-005..006 | extension model | M9/M11 | optional processor uses public contract; core import audit |
| FR-PKT-001..015 | packet + pipeline + adapters | M5 | synthetic/DPDK conformance AC-001..003/010 |
| FR-PROC-001..009 | pipeline + update | M3 then M6 hot updates | lifecycle/fault/resource tests |
| FR-SRC-001..006 | update/source | M7 | direct/source equivalence and source conformance |
| FR-UPD-001..010 | update/QSBR | M6/M7 | TLA+, forced interleavings, AC-004..006/011/012 |
| FR-EXT-001..006 | extension model | Native M3, reference optional M9/M11 | contract reuse and module isolation |
| FR-STATE-001,004 | native worker state | M3/M5 | worker ownership and contention review |
| FR-STATE-002..003,005..006 | state module/update | M10 | capacity/exhaustion/transition differential tests |
| FR-OBS-001..003,007,009 | metrics | M5/M8 | blocked exporter, cardinality and snapshot tests |
| FR-OBS-004..006,008 | events | M8 | ring saturation, schema registration, AC-009 |
| FR-TEST-001..006 | test harness/tools | M3, explanation M9 | public harness and deterministic fixtures |
| PL-EXP-001..009 | policy | M9 | truth tables and reference/compiler differential |
| PL-SET-001..005 | policy sets | M9 | representation-independent membership properties |
| PL-PRED-001..004 | policy resolver | M9 | cycle, expansion, type/availability tests |
| PL-ACT-001..006 | policy action registry | M9 | capability/type/terminal-effect tests |
| Section 4 type/availability/ACL/rules/compiler prose | policy | M9 | AC-PL-001..008 and fixtures |
| Section 5 runtime/update/failure/time/resources | cross-cutting | M5/M6/M10 | invariant and overload suites |
| Section 6 observability | observability | M8 | descriptor/snapshot/export/event diagnostics tests |
| Phase-6 quality gates | release | M12 | release evidence bundle |

## Enforcement mechanism

Maintain `docs/requirements/coverage.yaml` in the implementation repository with one record per ID:

```yaml
- id: FR-PKT-012
  design: docs/internals/packet-ownership.md
  code: src/packet/handle.zig
  tests:
    - test/conformance/AC-010-packet-lifetime.zig
  status: passing
  since: 0.1.0
```

CI rejects unknown IDs, duplicate records, mandatory IDs without tests/manual evidence, and references to missing paths. `MAY` features can be `not-implemented`; `MUST` and `MUST_NOT` cannot be waived without changing the normative specification.

