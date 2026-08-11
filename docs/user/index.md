# Saint Shield documentation

Saint Shield is a reusable backend-neutral Zig library, not a mandatory
firewall appliance or control plane. M0-V proves that its toolchain and virtual
adapter foundation are reproducible. M1 adds deterministic packet ownership,
read-only segmented views, synthetic queues, and bounded capture fixtures. M2
adds parsing, selection/dispositions, mutation/finalization, and retention.

The current virtual/synthetic results are regression evidence only. They are
not production capacity claims, and AArch64 is labelled build-tested until a
representative physical testbed passes later gates.

Start with [M0-V development](m0-v-development.md), then read the
[M1 packet foundation](m1-packet-foundation.md).

Then read [M2 packet processing](m2-packet-processing.md) and the
[0.2 migration notes](migration-0.2.md).

For M1 capture fixtures, see [bounded PCAP fixtures](pcap-fixtures.md).
