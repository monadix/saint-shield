# Saint Shield Local Execution and Resource Plan

Status: accepted local implementation baseline, 2026-07-19.

This document records the decisions needed to implement Saint Shield without
re-deriving project intent in every session. It supplements, but does not
replace, the unpacked normative specification and technical plan.

## Source authority

When sources disagree, use this order:

1. `specification/l4-protection-framework-technical-plan/source-requirements/`
   is normative product behavior.
2. `specification/l4-protection-framework-technical-plan/DECISIONS.md` and the
   architecture/implementation documents are the accepted technical baseline.
3. This file records local execution, platform, and resource decisions.
4. `IMPLEMENTATION_PROGRESS.md` records execution state and evidence; it does
   not redefine requirements.

Read the technical archive in the order prescribed by its `README.md`. For
M0-V through M3, always read these files before implementation:

- `00-overview/selected-stack.md`
- `01-architecture/invariants.md`
- `01-architecture/memory-and-ownership.md`
- `01-architecture/modules/core-packet.md`
- `01-architecture/modules/io-backends.md`
- `01-architecture/modules/pipeline-runtime.md`
- `01-architecture/modules/testing.md`
- `02-implementation/roadmap.md`
- `02-implementation/testing-strategy.md`
- `02-implementation/ci-and-quality-gates.md`
- `03-performance/quantitative-gates.md`

All paths above are relative to
`planning/specification/l4-protection-framework-technical-plan/`.

## Accepted local decisions

### L-001: Split M0 into virtual and hardware gates

The archive's M0 combines locally implementable setup with physical testbed
acceptance. Locally, execute it as two explicit gates:

- **M0-V** covers the reproducible toolchain, project scaffold, all build modes,
  AArch64 cross-compilation, DPDK virtual-PMD ABI/lifecycle spike, fuzz-engine
  selection, benchmark schema, environment manifest, and local/CI commands.
- **M0-H** covers the physical NIC inventory, generator calibration, firmware,
  cabling, zero-copy AF_XDP spike, and production benchmark preflight.

Passing M0-V permits M1 through M3. M0-H must pass before M4 can be accepted or
any production performance claim is made. M4-related research spikes may occur
earlier, but their code and measurements do not satisfy M0-H.

### L-002: x86-64 is the first production platform

- Linux x86-64 is the production and performance target for the first 1.0 line.
- AArch64 remains a required compile and semantic-CI target.
- AArch64 must be labelled `build-tested`, not `performance-supported`, until a
  representative physical NIC testbed passes the relevant gates.
- A native/cloud AArch64 runner is an external CI resource; local Zig
  cross-compilation is required even before that runner exists.

### L-003: Workspace-local Nix environment

- Add `flake.nix` and `flake.lock` during M0-V.
- `nix develop` supplies workspace dependencies; `zig build` remains the
  canonical build, test, documentation, and benchmark entry point.
- Do not require changes to `/etc/nixos`, system profiles, or global packages
  for M0-V through M3.
- Pin and hash every fetched source. Preserve license metadata and make builds
  usable through configured Nix caches.

The inspected local host provides Nix 2.35.1 with flakes and sandboxing, Linux
6.18 x86-64, working user namespaces, Java 21, and Python. It has no configured
huge pages, VFIO/IOMMU test devices, KVM device, or passwordless sudo. Those do
not block M0-V through M3.

### L-004: Exact baseline dependencies

- Zig: exactly 0.16.0.
- DPDK: exactly 25.11.2 LTS, built by a custom pinned Nix derivation because the
  current Nixpkgs package is 26.03.
- Scapy: pinned Python environment, initially 2.7.0, integration-test oracle
  only.
- TLA+/TLC: pinned tool, initially Nixpkgs 1.7.4; first required for M6 but made
  available by the development environment.
- M0-V evaluates the exact coverage-guided fuzz engine and records D-012 in an
  ADR. AFL++ and LLVM/libFuzzer-compatible integration are candidates, not an
  assumed final decision.
- Supporting tools include Clang/LLVM, a C compiler, Meson, Ninja, pkg-config,
  perf, MkDocs, schema/link checkers, and Python.

### L-005: No silent scope expansion

M0-V through M3 do not add a controller, remote update protocol, database,
authentication service, dashboard, dynamic native ABI, JIT, Wasm/eBPF policy
executor, OpenTelemetry SDK, or production AF_XDP adapter. Public boundaries
must remain compatible with the plan, but deferred features are not implemented
without a concrete use case and ADR.

### L-006: Evidence-gated progression

Implement milestones in order. A milestone is complete only when its code,
tests, requirement links, documentation, benchmark delta, and cleanup/failure
evidence satisfy the archived roadmap. Update `IMPLEMENTATION_PROGRESS.md` only
from verified implementation and test evidence.

## M0-V through M3 implementation contract

### M0-V: reproducible virtual foundation

Build:

- Create the repository layout, `build.zig`, `build.zig.zon`, Nix flake, and
  canonical formatting, test, documentation, benchmark, fuzz, and CI commands.
- Pin Zig 0.16.0 and DPDK 25.11.2 with integrity metadata.
- Build Debug, ReleaseSafe, and ReleaseFast on Linux x86-64.
- Cross-compile the public library for Linux AArch64.
- Prove required `rte_mbuf` fields/layout through a narrow C compatibility
  boundary with compile-time/runtime ABI assertions.
- Receive and return a virtual DPDK burst using ring/virtual PMDs and
  no-hugepage mode. No physical NIC, VFIO, or root-owned setup is part of M0-V.
- Evaluate coverage-guided fuzz candidates by demonstrating a deterministic
  crash, saved reproducer, seed/corpus flow, timeout, and sanitizer behavior.
- Define benchmark-result JSON and environment-manifest schemas.

Exit evidence:

- Clean x86-64 builds/tests in all three modes.
- Successful AArch64 cross-compile.
- Verified DPDK source hash, C ABI assertions, and virtual token round trip.
- D-012 fuzz-engine ADR with exact commands and reproducer workflow.
- Validated benchmark/environment example documents.
- No permanent system configuration change.

### M1: foundation, ownership, and views

Implement stable IDs, bounded errors, budgets, deterministic/monotonic time,
adapter token state, packet segments, `PacketView`, `InputOrigin`, receive-order
slots, debug lifetime cookies, the bounded pure-Zig PCAP subset, and synthetic
input/output queues.

Required evidence includes complete range/segment boundary tests, checked
arithmetic, malformed descriptors, exact token transitions, double/missing
completion detection, allocation failure for every constructor, fuzz corpus for
capture parsing, and a zero-payload-copy counter. INV-PKT-001/002 and the
archived M1 exit gate must pass.

### M2: parsing, dispositions, and mutation

Implement the active bitset, disposition writer, output grouping, lazy
L2/L3/L4 parsing, fragment semantics, structured editor, trusted raw-editor
capability, mutation journal, checksum/length finalizer, and bounded retention
lease API.

Required evidence includes selection-versus-oracle property tests, truncation at
every header byte, IPv4 options/fragments, IPv6 extensions/fragments, all
disposition mixtures, Scapy checksum/decoded-field differential tests,
head/tailroom failure atomicity, lease exhaustion/leak tests, and parser/no-op
cycles per packet for batches 1/4/8/16/32/64. AC-001/002/010 and packet
invariants must pass; mutation failure must never transmit corruption.

### M3: native processor contract and static pipeline

Implement descriptor/capability schemas, comptime validation, prepared/worker
lifecycle, tuple pipeline and direct batch calls, stage metadata, resource
estimates, reverse cleanup, error/default policy, and the public processor test
harness.

Required evidence includes compile-fail cases for every invalid declaration,
three-stage ordering, mixed dispositions, allocation-fault cleanup, capability
denial, tiny random pipelines versus a reference runner, and cleanup accounting.
Benchmark 0/1/2/4/8 no-op processors against a hand-written monolith and
batch-vtable spike. PERF-CORE-001, AC-003/012, and the example native processor
application gate must pass.

## External resources

### Immediately required for M0-V through M3

| Resource | Used by | Provisioning rule |
| --- | --- | --- |
| Nix network/cache access | M0-V and clean rebuilds | Fetch only pinned flake inputs and sources; request scoped network approval when sandboxed. |
| Zig 0.16.0 | M0-V-M3 | Exact signed/hash-verified input, never master. |
| DPDK 25.11.2 source | M0-V ABI and virtual-PMD spike | Custom pinned derivation; do not substitute Nixpkgs 26.03. |
| Clang/C toolchain, Meson, Ninja, pkg-config | M0-V | Development-shell dependencies, not system packages. |
| Scapy/Python | M2 | External packet/checksum oracle only; never a runtime dependency. |
| Fuzz engine and sanitizers | M0-V-M2 | Exact engine decided by D-012; corpus/reproducer artifacts retained. |
| perf and stable local runner | M2-M3 | Synthetic relative measurements only; no production claims. |
| AArch64 runner | M0-V CI follow-up | Cross-compile locally; add native semantic execution when CI is available. |

### Required later for complete 1.0 evidence

| Resource | First blocking milestone | Purpose |
| --- | --- | --- |
| Physical x86-64 DUT with controllable BIOS/CPU/NUMA and multi-queue NIC | M0-H/M4 | DPDK ownership, offload, scaling, latency, and physical conformance. |
| Independent TRex STL or commercial generator/sink with at least 120% DUT headroom | M0-H/M4 | Zero-loss rate, latency, loss, burst, IMIX, and flow profiles. |
| Direct cabling/optics, management access, firmware/driver inventory | M0-H/M4 | Reproducible testbed contract and support matrix. |
| Huge pages, raised memlock, IOMMU/VFIO, NIC binding privileges | M4 | Physical DPDK operation; not needed for virtual no-huge PMDs. |
| Dedicated cores/queues and environment telemetry | M5 | NUMA/scaling and stable regression measurements. |
| TLA+/TLC capacity and concurrency reviewer | M6 | QSBR/publication and ring protocol evidence. |
| Prometheus interoperability fixture | M8 | Scrape exporter conformance outside workers. |
| Representative policies and policy-domain decisions | M9 | Grammar, semantics, diagnostics, performance profiles. |
| RSS/flow-steering state workload and long-soak capacity | M10 | Flow affinity, bounded state, high-churn behavior. |
| Linux 6.12/6.18 plus libxdp/libbpf and zero-copy-capable NIC/driver | M11 | AF_XDP copy/driver/zero-copy support matrix on the same DUT. |
| Artifact/docs hosting, protected signing identity, SBOM tooling, independent security review | M12 | Reproducible and signed 1.0 candidate with public evidence. |

Before M0-H/M4, the user must choose target link rate/NIC family, MTU and
encapsulation, port/output topology, required offloads, CPU/power budget, and
production traffic profiles. Before M7-M10, the user must supply the application
failure/update/event/state policies listed in
`06-research/assumptions-and-open-questions.md`. Agents must not invent them.

## Recommended single-run invocation

For a continuous M0-V-through-M3 implementation, the request should be
equivalent to:

> Implement and test M0-V through M3 in one continuous run. Read AGENTS.md and
> the planning sources first. Verify every milestone exit gate before beginning
> the next. Stop and report evidence if a gate cannot be satisfied; do not
> weaken or invent requirements.

The run is continuous, but milestone gates remain real checkpoints.
