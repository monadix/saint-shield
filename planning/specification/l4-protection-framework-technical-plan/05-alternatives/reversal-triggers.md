# Reversal Triggers and Fallback Paths

These triggers turn architecture flexibility into a practical route. Crossing a trigger starts an ADR/experiment; it does not authorize an untested rewrite.

## DPDK → prioritize AF_XDP

Trigger if any target deployment cannot detach/share the NIC acceptably, privileges/huge pages/VFIO are prohibited, required NIC support is absent, or DPDK's measured advantage is <10% while AF_XDP materially improves operations. Implement M11 early, run identical hardware tests, and change the recommended adapter per support matrix. Core/processors do not migrate.

## AF_XDP → DPDK recommendation

For an AF_XDP deployment, recommend DPDK when zero-copy is unavailable, flow steering cannot preserve required queue affinity, small-packet throughput misses capacity by >15%, or copy/generic mode CPU cost exceeds budget. Preserve AF_XDP as supported only for its documented envelope.

## Static pipeline → hybrid batch vtable

Trigger when a real application must select processor ordering/types without rebuild, generated binary text grows beyond an agreed budget (initial signal: >25% attributable to variants), compilation becomes a material delivery bottleneck, or instruction-cache counters show >5% throughput recovery in the batch-vtable experiment. Keep capability-validated compiled variants; dispatch once per batch-stage.

## QSBR → refcount/reference implementation

Trigger if model/code review cannot establish online/offline safety, stalled-worker retention cannot meet memory budgets under required policy, or implementation repeatedly produces unreproducible retirement bugs. First switch to a per-batch atomic reference-count implementation to restore correctness and quantify cost. Consider hazard/epoch refinements only from evidence. Never free by timeout.

## Relaxed atomic metrics → batch accumulation/double buffer

Trigger when required metrics cause >3% zero-loss throughput regression in two stable profiles or a cache-line contention hotspot. First accumulate processor counters in registers/batch-local fields and flush once per batch where semantics permit. If still high, prototype worker-owned page flip at batch boundary with missing-worker metadata.

## Scalar policy → classifier lowering

Trigger when PERF-POL-001 fails after field caching, constant folding, set specialization, and compact blocks, and profiles attribute >30% cycles to match evaluation. Lower only eligible pure N-tuple subgraphs to DPDK ACL or a Zig batch classifier; use reference shadow checks. Preserve generic evaluator for ineligible expressions.

## Classifier lowering → JIT

Trigger only when a deployment has a written performance requirement still missed by ≥20%, policies update infrequently enough to amortize compilation, executable-memory policy permits it, and security review accepts compiler attack surface. Start as optional module. The typed IR/reference evaluator and resource bounds remain authoritative.

## Worker-local state → shared/owner stage

Trigger if hardware steering cannot keep the chosen key on one worker, policy needs exact cross-queue/global counts, or stateful processing dominates enough work to amortize a stage hop. Choose explicitly between sharded synchronized table (stronger direct semantics, cache cost), dedicated owner stage (queue/hop cost), or hierarchical approximate meters. Document consistency.

## Single process → privileged setup/helper or management process

Trigger from least privilege, crash isolation, or operations—not from the logical responsibility names. First split privileged adapter setup and pass configured descriptors. Split management only when an application needs independent lifecycle. The framework still exposes local artifact/update APIs; the IPC/network protocol stays application-specific.

## Zig version pin change

Trigger for security/critical compiler fix, required supported target, or supported stable line policy. Compile/test/benchmark downstream corpus, C ABI, all build modes, and generated artifacts. A compiler update that changes public API syntax gets a framework migration release, not an invisible CI change.

## Dynamic native ABI

Trigger only with at least two concrete independently shipped extensions that cannot be statically linked/redeployed and have explicit compatibility/lifecycle/security requirements. Before implementation, compare process-isolated IPC or Wasm module deployment. Dynamic loading is not justified merely as generic extensibility.

