# Performance and Benchmark Methodology

The project cannot promise line rate independent of NIC, CPU, rule set, state, and packet size. It can measure framework tax, publish capacity envelopes, and detect regressions. Correctness is checked before performance; a faster run with different drops/actions is invalid.

## Questions answered

1. What does the hardware/backend deliver with minimal forwarding?
2. What overhead does the framework's adaptation, batch, disposition, and generation boundary add?
3. What does each processor/policy/state feature cost at stated scale?
4. Where does throughput saturate, and how do loss and latency behave near/above saturation?
5. How do updates, exporter failure, event overflow, state churn, and NUMA affect service?
6. When should DPDK, AF_XDP, or another internal choice be replaced?

## Test topology

Preferred: dedicated generator → two-port DUT → sink/generator return, with no switch. The generator must demonstrate at least 120% of the DUT's measured forwarding capacity for the packet profile, or line rate plus margin where possible. A two-host direct topology is acceptable when generator RX validates loss and latency. Host-local loopback results are micro/integration data, not production dataplane claims.

Synchronize clocks only when one-way latency is used; otherwise use round-trip or hardware-generator timestamps. Report timestamp method and resolution.

## Environment control

Record raw:

- CPU model/microcode, sockets, cores, SMT, frequency governor/turbo/C-states;
- isolated CPUs, task affinity, IRQ affinity, kernel command line;
- memory channels/speed, NUMA placement, huge pages, locked memory;
- NIC PCI ID, ports, queues, driver/PMD, firmware, link speed, flow steering;
- kernel, Zig, DPDK, libbpf/libxdp, application commit/build mode;
- RX/TX descriptors, mempool/UMEM, batch size, MTU, offloads, RSS key/fields;
- pipeline/processors, artifact semantic hash, resource limits;
- generator/version/profile/rate, cable/topology;
- ambient/background load and thermal readings if available.

Fix CPU settings for comparative runs. Do not hide busy-poll CPU cost: report cores and watts/CPU utilization where measurable.

## Traffic matrix

### Frames and protocols

- Ethernet frame sizes 64, 128, 256, 512, 1024, 1518 bytes; jumbo only where explicitly supported.
- A published IMIX profile in addition to fixed sizes.
- IPv4 and IPv6; TCP and UDP; fragments/malformed packets in correctness/security profiles, not mixed into ordinary throughput silently.
- Single flow, 1k, 64k, and high-cardinality flows; uniform and skewed distributions.
- Bidirectional/asymmetric profiles for state/affinity.

### Policy dimensions

- 0, 1, 10, 100, 1k, 10k rules where the syntax/engine supports them.
- first hit, middle hit, last hit, miss; 0/50/100% drop; mixed actions.
- small and large exact sets, prefix sets, and port ranges.
- all-fields-present versus frequent unavailable fields.
- native hand-coded semantic equivalent and policy engine.

### Stateful dimensions

- table occupancy 50, 80, 95, 100%; lookup-only and create/expire churn.
- flows/second and concurrent entries, hot-key skew, adversarial collision corpus.
- under-capacity, at-capacity, and explicit overload behavior.

## Measurements

- offered, received, forwarded, dropped, and lost packets/bytes;
- throughput in Mpps and Gbit/s, and zero-loss forwarding rate;
- latency p50/p90/p99/p99.9/max and full histogram where generator supports it;
- cycles/instructions/branches/branch misses/cache misses per packet/batch via `perf`;
- CPU cores/utilization and energy where available;
- batch distribution, output partial-submit, queue/mempool/UMEM drops;
- prepared/worker/retained/state/event memory;
- update prepare, publish, worker adoption, grace, and destruction times;
- event/metric/export rates and loss.

## Procedure

1. Preflight links/generator and validate packet correctness.
2. Warm up caches/JIT-less code/NIC for a fixed period.
3. Find zero-loss rate with a documented search and validation duration.
4. Run fixed offered-load points (e.g. 10/50/90/100/110% of zero-loss) for latency/loss curves.
5. Randomize A/B implementation order to reduce thermal/time bias.
6. Collect at least 7 independent runs after warmup; report all samples, median, dispersion, and confidence interval where meaningful.
7. Reject runs with preflight failure, thermal throttling, generator shortage, link error, or background task violation; retain rejection reason.
8. Store raw generator, DUT metrics, perf counters, environment, and commit/config artifacts.

RFC 2544 informs forwarding/latency/reporting, RFC 3511 informs firewall forwarding/filtering/connection tests, and RFC 9411 informs realistic security-device validation and transparent test setup. The project profiles are narrower than an NGFW and must say which RFC procedures are adapted rather than claiming blanket RFC compliance.

## Comparisons

Use in this order:

1. DPDK `testpmd` or AF_XDP minimal forwarder as backend/hardware ceiling.
2. Minimal handwritten Zig adapter loop using identical queue/pool settings.
3. Framework with zero processors.
4. Framework with equivalent hand-coded native processor.
5. Standard policy processor.
6. DPDK `l3fwd_acl` for eligible N-tuple policy only.
7. nftables/XDP-filter/VPP only as clearly different operational products, not framework-tax baselines.

Do not compare different correctness, checksum, MTU, offload, flow steering, or drop behavior as equal.

