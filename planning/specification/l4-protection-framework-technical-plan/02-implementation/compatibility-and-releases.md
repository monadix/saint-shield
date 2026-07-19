# Compatibility, Versions, and Releases

## Version domains

Version these independently:

1. Zig source API of the framework.
2. Optional native dynamic ABI, only if it ever exists.
3. Processor artifact formats (standard policy, table, Wasm/eBPF modules).
4. Event binary stream/schema.
5. Benchmark result schema.
6. External application/controller protocols, outside core.

A framework version bump does not imply a policy artifact syntax bump.

## Pre-1.0 policy

Minor releases may change Zig source APIs, but every change has migration notes and tests. Stable semantic IDs (requirements, errors, metrics, events) are not casually reused. Public experimental modules are namespaced/documented as experimental.

## 1.0 source compatibility

Follow semantic versioning at the package level with the caveat that a Zig compiler upgrade may require a new minor/major framework line. Pin the supported Zig release in each branch. Public API diff tooling is imperfect, so CI also compiles a corpus of downstream example applications.

Patch releases cannot change packet/update semantics or artifact interpretation except to correct behavior that contradicts the specification/security. Such corrections are called out.

## Artifact evolution

Artifacts carry content type and schema/language version. Parsers reject unsupported major versions and unknown semantics. Minor additions require explicit feature negotiation or syntax that old parsers reject safely. Canonical semantic hashes include the language/compiler semantic version.

## Adapter support

Publish a table by framework release: DPDK exact LTS patch range, kernel/libxdp range, tested NIC/driver/firmware, architecture, mode (copy/zero-copy), and limitations. `works in CI` and `performance supported` are separate labels.

## Deprecation

Every deprecation supplies replacement, migration example, first deprecated version, and planned removal version. Keep for at least one minor line where security does not prohibit it. Silent aliasing of old metric/error semantics is forbidden.

## Release artifacts

- Source archive and integrity/signature.
- `build.zig.zon` dependency hashes and SBOM.
- Generated public docs and source Markdown.
- Compatibility/support matrix.
- Migration/upgrade/rollback guide.
- Benchmark report with raw machine-readable results.
- Known limits and unsafe boundaries.

