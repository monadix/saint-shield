# CI and Quality Gates

## Pull request lane

- Exact toolchain/dependency integrity check.
- `zig fmt --check` equivalent and documentation/link/schema validation.
- Debug and ReleaseSafe builds/tests on Linux x86-64.
- AArch64 cross-compile and compile-time contract suite.
- Unit, conformance, deterministic integration, short property tests.
- Bounded TLC model when update/ring models or mapped code change.
- Virtual DPDK adapter smoke when adapter code changes.
- Public API/requirement mapping diff.
- Short microbench informational result; fail only on large stable regressions after baseline matures.

Target: ordinary PR lane stays short enough for development; expensive evidence moves to merge/nightly, never disappears.

## Main lane

- Full Debug/ReleaseSafe/ReleaseFast semantics.
- Longer generated/property corpus.
- Coverage-guided fuzz smoke for all targets.
- ABI and dependency matrix for supported DPDK patch level(s).
- Documentation site and every published example from clean checkout.
- Microbenchmark comparison against rolling baseline with hardware/noise metadata.
- Artifact/SBOM generation smoke.

## Nightly lane

- Expanded TLC state bounds and random simulation.
- Long fuzz jobs with corpus merge/minimization.
- Allocation-failure sweep.
- Concurrency/update stress, event/exporter blockage, state churn.
- Virtual adapter repeated start/stop.
- Current supported kernel/toolchain patch trial; failures do not silently change pins.

## Hardware lane

Dedicated, isolated hosts only. Record and check CPU governor, turbo, SMT, isolation, IRQ placement, NUMA, huge pages, NIC driver/firmware, link state, kernel, DPDK/libxdp versions, offloads, temperature, and generator headroom. A preflight must pass before DUT results are accepted.

Run correctness conformance before performance. Performance jobs use repeated randomized A/B order, warm-up, raw sample retention, median and dispersion, and a noise threshold. Do not compare across changed hardware/firmware as one time series.

## Release lane

- All normative requirements linked to evidence.
- Supported target/adapter matrix passes.
- 24-hour minimum update/traffic/observability soak; longer 72-hour candidate before 1.0.
- Clean security and unsafe-boundary review status.
- Benchmark report/raw data and known limitations.
- Reproducible build attempt and signed source/binary/SBOM/version manifests.
- Upgrade from previous supported release and rollback rehearsal.
- Public docs versioned, examples tested, migration guide present.

## Review ownership

Changes to packet ownership/mutation require a core reviewer. Atomics/QSBR require a concurrency reviewer and model/test update. C/adapter boundaries require an adapter reviewer. Policy grammar/semantics require language and security reviewers. Benchmark gates/methodology require a performance reviewer. These may be roles held by the same person initially, but the review perspective must be explicit.

