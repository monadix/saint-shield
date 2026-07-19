# Error and Security Architecture

## Threat model

Native application processors are trusted code. Configuration/policy artifacts, capture files, remote source bytes, metric scrape requests, and event destinations may be untrusted. NIC descriptors and offload metadata are also validated at the adapter boundary because driver/hardware faults must not become memory corruption.

The core is not a sandbox and does not defend an application from a malicious native processor. Wasm/eBPF executor modules must publish their own isolation claims.

## Artifact preparation defenses

- Content type and schema version checked before parsing.
- Artifact byte limit before allocation.
- Bounded token count, nesting, predicate expansion, set entries, rules, actions, and diagnostics.
- Checked arithmetic for sizes and offsets.
- No recursive predicate expansion; build a dependency graph and reject cycles.
- Deterministic preparation time budget with cancellation outside critical sections.
- Canonical hash covers semantic content, compiler version, registered extension identities, and relevant options.
- Diagnostics cap count, source excerpt, and rendered length.
- Candidate arena is destroyed on every failure path; fault-inject every allocation site.

## Runtime failure taxonomy

Use stable bounded codes grouped by domain: input, output, packet parse, mutation, processor, state, event, generation, resource, and invariant. Error sets exposed publicly are narrow. Detailed internal causes chain outside the packet path using owned diagnostics.

Defaults are explicit at assembly:

- input failure: retry/backoff, stop worker, or stop runtime;
- output congestion/failure: drop, bounded retry, alternate output, or stop;
- processor error: per-packet default, fail-open, fail-closed, or stop;
- state exhaustion: deny, bypass, evict under declared policy, or degrade feature;
- event overflow: drop-newest, sample, aggregate, or disable type;
- update failure: preserve active generation;
- exporter/source failure: isolate and report.

## Privilege and process concerns

The DPDK adapter may require VFIO/device/huge-page setup; the AF_XDP adapter requires XDP/BPF/socket privileges during setup. Adapters should support a privileged setup helper passing already configured descriptors only as an application option, not a framework process split. Drop unnecessary capabilities after initialization. Bind AF_XDP sockets to the selected interface and verify queue/map correspondence.

## Supply chain

- Pin every dependency by exact version and integrity hash.
- Record license and security contact.
- Prefer no runtime dependency when a small, audited implementation is cheaper than an unstable wrapper.
- Automate CVE/advisory monitoring for Zig, DPDK, libbpf/libxdp, documentation tooling, traffic generators, and test-only parsers.
- Produce SBOM and source/version manifest for releases.
- Reproducible build attempts compare binary and generated artifact hashes in a clean environment.

## Security review gates

M1 reviews buffer boundaries and lifetime. M4 reviews C/DPDK ABI. M6 reviews atomics and reclamation. M9 reviews policy parser/compiler resource abuse. M10 reviews state-exhaustion attacks. Production-ready status requires an independent review of these four surfaces and fuzz corpus stability under sanitizing builds.

