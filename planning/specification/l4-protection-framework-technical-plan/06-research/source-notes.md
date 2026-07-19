# Research Sources and Design Implications

Research date: 2026-07-18. Primary/official sources are preferred. Links are direct so future ADRs can revalidate versions and claims.

## Zig

- [Official Zig downloads](https://ziglang.org/download/) lists 0.16.0 (2026-04-13) as the current stable release and master as 0.17 development. Implication: pin 0.16.0; do not build a long-lived low-level framework on master.
- [Zig 0.16 language reference](https://ziglang.org/documentation/0.16.0/) documents Debug/ReleaseSafe/ReleaseFast modes, the dependency-free Zig build system, C import/translation, tests, and `///`/`//!` docs. It also labels generated documentation experimental. Implication: use Zig's build/test/C interop, but keep authored Markdown as the durable user documentation.

## DPDK

- [Official DPDK downloads](https://core.dpdk.org/download/) lists 25.11.2 as the latest LTS on the research date; [the roadmap](https://core.dpdk.org/roadmap/) lists support to December 2028. Implication: pin 25.11.2 rather than a release candidate/current four-month feature line.
- [DPDK Poll Mode Driver guide](https://doc.dpdk.org/guides-25.11/prog_guide/ethdev/ethdev.html) describes run-to-completion and pipeline models, burst RX/TX, one RX queue per lcore, per-core TX resources, NUMA-local pools, and the cost of shared queues. Implication: the recommended worker/queue/NUMA model follows an established backend model rather than inventing a scheduler.
- [DPDK mbuf guide](https://doc.dpdk.org/guides-25.11/prog_guide/mbuf_lib.html) documents mempools, compact metadata, headroom, and chained buffers. Implication: public packet APIs must not assume a core-owned contiguous buffer.
- [DPDK RCU/QSBR guide](https://doc.dpdk.org/guides/prog_guide/rcu_lib.html) separates removal from reclamation, defines quiescence as holding no shared reference, and identifies the packet loop boundary as a suitable quiescent state. Implication: batch-boundary QSBR matches generation retirement, while retained memory/stalled readers remain explicit costs.
- [DPDK ACL guide](https://doc.dpdk.org/guides-25.11/prog_guide/packet_classif_access_ctrl.html) provides prepared N-tuple classification with scalar and SIMD implementations and build-time memory limits. Implication: it is a credible optional lowering/baseline for eligible policy subgraphs, not a complete implementation of Boolean/availability/action semantics.
- [DPDK Linux driver guide](https://doc.dpdk.org/guides/linux_gsg/linux_drivers.html) documents VFIO/DMA/locked-memory setup constraints. Implication: operational footprint is a real DPDK cost and an AF_XDP reversal trigger.

## AF_XDP and Linux

- [Linux AF_XDP documentation](https://docs.kernel.org/networking/af_xdp.html) documents RX/TX/FILL/COMPLETION rings, UMEM ownership, XSKMAP redirection, queue binding, copy/zero-copy modes, need-wakeup, SPSC constraints, and multi-buffer behavior. Implications: one XSK/queue/worker, explicit mode diagnostics, need-wakeup, ownership tests, and segment-aware API.
- [Linux kernel releases](https://www.kernel.org/) lists 6.12 and 6.18 as maintained longterm kernels on the research date. Implication: use them as the initial AF_XDP compatibility matrix rather than claiming every Linux kernel.
- [xdp-tools/libxdp project](https://github.com/xdp-project/xdp-tools) provides libxdp and AF_XDP tooling. Implication: use the maintained helper surface for initial setup instead of immediately owning every BPF loader/ring compatibility detail.
- [Performance Implications at the Intersection of AF_XDP and Hardware Flow Steering (2025)](https://cs.nyu.edu/~apanda/assets/papers/ebpf25.pdf) reports that AF_XDP performance depends materially on NIC flow steering and deployment mode. This supports treating DPDK versus AF_XDP as a hardware/deployment benchmark decision, not a universal hierarchy.
- [Understanding Delays in AF_XDP-based Applications (2024)](https://arxiv.org/html/2402.10513v1) analyzes latency behavior and configuration effects. Implication: adapter evaluation must include tail latency and wakeup/polling modes, not only Mpps.

## Benchmark methodology

- [RFC 2544](https://www.rfc-editor.org/rfc/rfc2544) defines network interconnect benchmarking methods and reporting.
- [RFC 9004](https://www.rfc-editor.org/rfc/rfc9004) updates back-to-back frame methodology.
- [RFC 3511](https://www.rfc-editor.org/rfc/rfc3511) covers firewall forwarding, connection, latency, and filtering benchmarks.
- [RFC 9411](https://www.rfc-editor.org/rfc/rfc9411) emphasizes validated security functionality, realistic/reproducible profiles, and avoiding testbed bottlenecks for modern security devices.

Implication: publish correctness configuration first, fixed and mixed frame profiles, zero-loss throughput, latency/loss under load, connection/state tests when relevant, and complete environment data. The framework is not an NGFW, so reports state exactly which methods are adapted.

## Observability

- [Prometheus metric and label naming](https://prometheus.io/docs/practices/naming/) warns that every label combination creates a time series and high-cardinality labels should be avoided. Implication: finite label domains and activation-time cell budgets are part of correctness/resource validation.
- [OpenTelemetry Prometheus exporter specification](https://opentelemetry.io/docs/specs/otel/metrics/sdk_exporters/prometheus/) defines off-path pull/export expectations and required Prometheus text compatibility. Implication: a Prometheus exporter can be optional and protocol-facing while the core snapshot API stays smaller and Zig-native.

## Formal concurrency documentation

- Leslie Lamport's [High-Level View of TLA+](https://lamport.azurewebsites.net/tla/high-level-view.html) describes TLA+ as a language for models above code and TLC as the common model checker.
- The [PlusCal tutorial introduction](https://lamport.azurewebsites.net/tla/tutorial/intro.html) specifically positions PlusCal for multithreaded algorithms checked through TLA+/TLC.

Implication: model the small publication/QSBR and bounded ring protocols whose failures arise from interleavings; do not attempt to formally specify every packet function.

## Inferences and limitations

The choice of DPDK first is an architectural inference from requirement fit, maturity, and operational trade-offs; the sources do not prove it will outperform AF_XDP on the project's unknown hardware. The archive therefore makes the choice provisional at the physical benchmark gate. Quantitative gates are engineering hypotheses and contain no fabricated measurements.

