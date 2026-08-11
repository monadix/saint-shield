# Saint Shield

Saint Shield is a Zig framework for building low-level Layer 4 protection
tools. The repository currently includes the M2 hardware-free packet surface:
exact adapter-token ownership, segment-safe views, bounded parsing,
selection/dispositions, structured/raw mutation and software finalization,
retention leases, deterministic synthetic queues, and bounded classic-PCAP
fixtures. Processor composition remains predecessor-gated to M3.

Enter the exact local environment and run the hardware-free gate:

```sh
nix develop
zig build ci
```

`zig build ci` is the cumulative M2 gate. Predecessor gates remain separately
runnable as `zig build ci-m0-v` and `zig build ci-m1`.

The shell pins Zig 0.16.0, a custom DPDK 25.11.2 derivation, Scapy 2.7.0,
and TLA+ 1.7.4; the x86-64 shell also pins AFL++ 5.00c. DPDK tests use
`--no-huge`, `--no-pci`, an in-memory EAL configuration, and the virtual ring
PMD. They do not bind a NIC, request VFIO, require root, or modify permanent
system configuration.

See the [M0-V developer guide](docs/user/m0-v-development.md) for individual
commands and limitations. See the [M1 packet foundation guide](docs/user/m1-packet-foundation.md)
for ownership, lifetime, zero-length, and capture-limit behavior.
See [M2 packet processing](docs/user/m2-packet-processing.md) for parsing,
disposition, mutation/finalization, output, and retention behavior.
