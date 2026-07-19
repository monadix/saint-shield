# Module Family: Packet I/O Adapters

## Core contract

An adapter provides input/output descriptors, capability discovery, worker-owned queue handles, burst receive/submit, packet-segment access, mutation finalization hooks, completion/recycling, link/error statistics, and deterministic shutdown. Its methods are called by the generated runtime, not by ordinary processors.

Each queue is single-worker-owned. Adapter capability negotiation includes MTU, linear/multi-segment, head/tailroom, checksum offloads, RSS metadata, timestamps, zero-copy status, output sharing, and retention support.

## Synthetic adapter

Pure Zig queues own byte buffers and scripted outcomes. It supports deterministic time, arbitrary partial batches, segment splits, output backpressure, malformed metadata, allocation failure, and delayed completion. It is the semantic reference and CI default.

No production behavior may be implemented only in DPDK tests; every public ownership and disposition rule has a synthetic test.

## DPDK adapter

Baseline: DPDK 25.11.2 LTS.

- EAL/device configuration belongs to application assembly options.
- One RX queue per worker; normally one TX queue per worker/output.
- `rte_eth_rx_burst`/`rte_eth_tx_burst` at batch boundaries.
- `rte_mbuf` remains adapter token; payload is never copied solely for abstraction.
- NUMA-local mempools and port/queue placement are validated and diagnosed.
- Handle partial TX: retry only within a configured bounded budget, then apply the output failure policy and free/retain tokens correctly.
- Probe checksum/RSS/scatter/gather/offload flags; normalize them into framework metadata.
- A narrow C header/shim handles macros/static inline APIs. Hot field access must inline or be batched; no C function call per byte/field.
- Build-time/runtime ABI checks cover required struct layout and DPDK feature version.

CI uses virtual/ring/pcap/null PMDs where possible; release performance uses supported physical NICs and publishes driver/firmware/device IDs.

## AF_XDP adapter

Baseline test matrix: Linux 6.12 and 6.18 longterm kernels; zero-copy only where the driver advertises it.

- libxdp/libbpf for setup unless a later ADR justifies direct ring setup.
- XDP program performs only validated queue-to-XSK redirection and explicit fallback/drop; framework policy stays in userspace.
- One XSK per queue/worker. FILL/COMPLETION and RX/TX rings respect their SPSC ownership.
- Enable `XDP_USE_NEED_WAKEUP`; issue wakeup syscall only when required.
- Expose actual copy/zero-copy/driver/generic mode in diagnostics and metrics; never benchmark an implicit fallback as zero-copy.
- Prevent the same UMEM frame from existing in two ownership rings.
- Multi-buffer packets are rejected explicitly until complete support lands; the core API already permits segments.

AF_XDP is not an automatic fallback inside a running DPDK adapter. The application selects it at assembly/startup because device ownership and operational setup differ.

## PCAP adapter

Implement bounded classic PCAP/PCAPNG reading only to the extent needed for fixtures and replay; fuzz it as untrusted input. Preserve capture timestamps as optional test metadata. Output writes reproducible captures. It is not a live libpcap injection backend initially.

## Adapter acceptance

- Same conformance corpus on synthetic, DPDK virtual, physical DPDK, and AF_XDP.
- RX/TX/drop accounting reconciles with hardware/kernel statistics within documented races.
- Every partial TX and shutdown path proves token balance.
- Link flap, queue starvation, descriptor exhaustion, and invalid descriptor injection.
- No payload copy in the ordinary linear forwarding path, verified by instrumentation/profile.

## Requirement ownership

FR-PKT-003..004, FR-PKT-011..014, application I/O portions of AC-001/002/010, core input/output health metrics.

