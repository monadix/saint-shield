# M0-V development

## Environment

From the repository root:

```sh
nix develop
zig version
zig build test
```

The reported Zig version must be exactly `0.16.0`. `zig build` is the canonical
interface inside the shell; no global package installation is needed.

## Canonical commands

| Command | Purpose |
| --- | --- |
| `zig build fmt-check` | Check Zig formatting. |
| `zig build test` | Run public-library tests in the selected mode. |
| `zig build docs` | Generate Zig symbol documentation. |
| `zig build docs-check` | Build authored docs and check local links. |
| `zig build example` | Run the hardware-free static application scaffold. |
| `zig build bench` | Run a synthetic regression smoke, not a capacity test. |
| `zig build cross-aarch64` | Cross-compile the public library for Linux AArch64. |
| `zig build dpdk-smoke` | Assert the DPDK ABI and run the no-huge ring-PMD token path. |
| `zig build fuzz-smoke` | Run the bounded D-012 local fixture workflow. |
| `zig build schemas` | Validate benchmark/environment examples. |
| `zig build integrity` | Verify versions, hashes, licenses, and source manifests. |
| `zig build ci` | Run the complete M0-V hardware-free gate. |

Select semantics with `-Doptimize=Debug`, `ReleaseSafe`, or `ReleaseFast`.

## DPDK compatibility boundary

DPDK 25.11.2 headers transitively expose compiler-specific TLS declarations
which Zig 0.16 translate-C does not flatten reliably. The adapter therefore
imports only `saint_dpdk_mbuf_view`, a private flat C layout containing the
required fields. C `_Static_assert`s compare every mirrored field's offset,
size, and alignment plus the full structure against the real pinned
`rte_mbuf`. Zig emits direct field access against that view; there is no
per-packet accessor call. At runtime Zig and C reports must match before the
virtual token test runs.

The virtual test selects the current allowed CPU, passes `--no-huge`,
`--no-pci`, `--in-memory`, and `--no-telemetry`, creates RX/TX rings and a
mempool, and drives batch RX/TX from Zig. Zig reads the asserted view and
payload directly; the reserved reference-count bytes are not accessible as a
field. Normal completion and deterministic failures after every ownership
boundary drain RX/TX rings and reconcile allocation/completion and mempool
counts.

## Coverage-guided fuzz smoke

The selected AFL++ 5.00c workflow uses QEMU binary instrumentation to observe
branches compiled by Zig 0.16.0 and an AFL Clang ASan/UBSan fixture to classify
the saved input. The bounded smoke proves distinct safe-input coverage, exact
100 ms timeout status, seed/dictionary discovery, deterministic replay, and
sanitizer output. All targets and findings are confined to the script's
temporary directory.

## Limits

- M0-V implements scaffolding and risk evidence only; it does not claim M1
  packet ownership or M3 processor behavior.
- AArch64 is cross-build-tested, not performance-supported.
- Virtual/synthetic timings are only local regression signals.
- M0-H physical NIC, firmware, generator, hugepage, and VFIO evidence is
  deferred and remains mandatory before M4 acceptance.
