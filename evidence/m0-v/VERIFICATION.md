# M0-V verification evidence

Date: 2026-07-19  
Scope: reproducible virtual foundation only  
Environment label: virtual-regression-only; no production capacity claim

## Dependency build and integrity

Command:

```sh
nix build .#dpdk --print-build-logs
```

Result: pass. The custom derivation built DPDK 25.11.2 from
`https://fast.dpdk.org/rel/dpdk-25.11.2.tar.xz` with SRI
`sha256-QYv+MhJkDulaHLEK9u02DK0jh2hv4nIfijqc0C1e9PI=`. Output was
`/nix/store/zgcab7czp2m0axm6b86rz6rhbalf0n9p-dpdk-25.11.2`; the installed
package contains `libdpdk.pc`, the ring PMD, and
`share/saint-shield/integrity/dpdk-source.txt`.

The first build correctly failed because DPDK's build tool required the
undeclared Python `elftools` module. The derivation was corrected to use a
pinned Python environment containing `pyelftools`; the succeeding build is the
accepted evidence. No Nixpkgs DPDK 26.03 package was used.

Command:

```sh
nix develop --command zig build integrity
```

Result: pass. Verified Zig 0.16.0, DPDK 25.11.2, Scapy 2.7.0, AFL++ 5.00c,
TLA+ 1.7.4, the exact nixpkgs revision and DPDK hash, project/dependency license
records, and both immutable archive manifests. Exact dependency metadata is in
`evidence/m0-v/dependencies.json`. The integrity command evaluates
`lib.dependencyMetadata.x86_64-linux` from the locked flake and compares its
Zig, DPDK, AFL++, Scapy, TLA+, and check-jsonschema versions/SPDX lists to the
recorded JSON. Project-authored source is Apache-2.0 under the project owner's
2026-07-19 authorization recorded in `docs/adr/0001-project-license.md`.

Standalone command:

```sh
nix flake check --no-build --all-systems
```

Result: pass. Nix evaluated `packages`, `checks`, and `devShells` for both
`x86_64-linux` and `aarch64-linux`, plus the locked metadata `lib` output. The
locked AFL++ package is unavailable on AArch64. `perf` is omitted there by the
local x86 quality-tools policy; this evidence does not claim that the locked
package itself is unavailable.

## Complete clean-cache gate

Command:

```sh
nix develop --command zig build ci
```

Result: pass. `tools/m0/ci.sh` creates isolated temporary Zig local/global
caches, then ran:

- formatting plus x86-64 install builds and tests in Debug, ReleaseSafe, and
  ReleaseFast;
- ReleaseSafe Linux AArch64 public-library cross-compile;
- Zig API docs, authored docs, the static example, and the synthetic benchmark
  smoke;
- both JSON Schema metaschema/example checks;
- backend-version negative schema checks and a DPDK-free AF_XDP manifest;
- version/hash/live locked-license/archive integrity checks;
- the DPDK ABI/no-huge virtual-PMD check;
- the bounded D-012 AFL++ workflow.

The final line was `complete M0-V hardware-free CI gate passed`.

## DPDK compatibility and virtual lifecycle

Command (also included in CI):

```sh
nix develop --command zig build dpdk-smoke
```

Result: pass. Compile-time C assertions covered every mirrored field's offset,
size, and alignment and the complete structure. The reference-count location
is represented by reserved bytes, and Zig compilation rejects any translated
`refcnt` field. Zig and C independently reported:

```text
M0V_ABI size=128 align=64 data_off=16 pkt_len=36 data_len=40 next=64
```

Reports matched. EAL selected VA IOVA and started with `--no-huge --no-pci
--in-memory --no-telemetry`. A batch-level RX call transferred one real mbuf
view to Zig; Zig directly read `nb_segs`, `next`, lengths, and payload bytes,
then the batch-level TX boundary accepted or rejected the token.

All deterministic lifecycle cases balanced allocation/completion and restored
the mempool from 127 available objects back to 127:

| Injection | Allocated/completed | Destroy-time drain |
| --- | --- | --- |
| normal | 1/1 | RX 0, TX 0 |
| after pool, rings, or port setup | 0/0 | RX 0, TX 0 |
| after RX enqueue | 1/1 | RX 1, TX 0 |
| TX rejection | 1/1 | RX 0, TX 0 |
| after TX acceptance before completion | 1/1 | RX 0, TX 1 |

The final line was `Zig-driven DPDK batch and deterministic cleanup cases
passed`. No VFIO, NIC binding, root operation, hugepage setup, or permanent
configuration change occurred.

## D-012 and sanitizer evidence

Command (also included in CI):

```sh
nix develop --command zig build fuzz-smoke
```

Result: pass. The checked-in `M0V!` reproducer triggered an ASan
heap-buffer-overflow twice. AFL++ QEMU maps differed for equal-length safe
inputs whose only content-dependent path was compiled from
`test/fuzz/d012_zig_branch.zig`. `afl-showmap -Q -t 100` classified the Zig
`HANG` branch with exact timeout status 1. AFL++ 5.00c loaded one non-crashing
seed and two dictionary tokens, saved one Zig-branch crash in one second in the
final full-gate run, and replayed it with exact SIGABRT status 134. The same
saved input produced the expected ASan
heap-buffer-overflow in the sanitizer fixture. The fuzz loop has a 30-second
outer bound and the script deletes only its own `mktemp` directory. The
decision and reversal triggers are in
`docs/adr/0012-coverage-guided-fuzz-engine.md`.

## Schemas and documentation

`zig build schemas` passed both metaschema checks, both M0-V examples, and a
generated DPDK-free AF_XDP environment. Negative checks rejected a non-pinned
DPDK version, the wrong synthetic version, absent AF_XDP libxdp metadata, and a
benchmark without methodology evidence. The environment records the archived
methodology fields and conditionally requires DPDK 25.11.2 only for DPDK while
requiring libbpf/libxdp for AF_XDP.

`zig build docs-check` verified `///` documentation on every project Zig public
or exported declaration, all ten top-level module design records, a strict
MkDocs build, and 25 local URLs with zero warnings and zero errors. `zig build
docs`, `zig build example`, and `zig build bench` passed; the benchmark
identifies itself as a synthetic regression smoke and not a capacity claim.

## Known limitations and next gate

- AArch64 is cross-build-tested only, not performance-supported.
- Virtual/synthetic measurements are regression evidence only.
- M0-V establishes boundaries and tooling; M1 packet ownership/segments and M3
  processor behavior are not implemented here.
- M0-H hardware inventory, generator calibration, firmware/cabling, AF_XDP
  zero-copy evidence, hugepages, VFIO, and production performance remain
  deferred. M0-H is mandatory before M4 acceptance.

The next predecessor-gated action is M1.
