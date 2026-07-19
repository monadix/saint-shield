# Bounded PCAP fixtures

`saint_shield.io.pcap` reads and writes a deliberately small classic-PCAP
subset for replay fixtures and tests. It has no libpcap dependency and is not a
live capture or injection backend.

## Supported format

The reader accepts the classic version-2.4 global header and record format in
little- or big-endian byte order. Both microsecond and nanosecond magic values
are supported. Record timestamps are exposed as optional fixture metadata.
PCAPNG, modified-PCAP variants, and unsupported versions return an explicit
unsupported error.

Every caller supplies limits before any record is exposed:

```zig
const limits = saint_shield.io.pcap.Limits{
    .max_capture_bytes = 16 * 1024 * 1024,
    .max_records = 100_000,
    .max_snaplen = 65_535,
    .zero_length_records = .reject,
};
```

`max_capture_bytes` counts the sum of captured record payloads. `max_records`
counts record headers, and `max_snaplen` bounds the value declared in the
global header. The zero-length policy is mandatory rather than adapter-defined.

## Borrowed and owned parsing

`Parser.init(bytes, limits)` validates the global header without allocation.
Repeated `next()` calls return record payload slices borrowed from `bytes`.
Truncated, malformed, unsupported, limit, and arithmetic failures have distinct
tags and can be grouped with `classifyError`.

Use `Capture.parseAlloc(allocator, bytes, limits)` when records must outlive the
source buffer. The returned capture owns its record table and payload storage:

```zig
var capture = try saint_shield.io.pcap.Capture.parseAlloc(
    allocator,
    bytes,
    limits,
);
defer capture.deinit(allocator);
```

## Deterministic output

`writeAlloc` emits one caller-owned classic-PCAP byte slice. It always writes
version 2.4, zero timezone correction, and zero timestamp-accuracy fields.
Byte order, timestamp resolution, snaplen, and link type come from
`WriterConfig`; a missing record timestamp is serialized as zero.

## Robustness and reproduction

The reviewed seed descriptions under `test/fuzz/pcap-corpus` are handcrafted
and contain no captured traffic. Run the bounded replay and AFL++ smoke inside
the locked development shell:

```sh
zig build pcap-fuzz-smoke
```

Replay any saved raw input through the same ReleaseSafe target with:

```sh
sh tools/m1/pcap-fuzz-smoke.sh --reproduce path/to/input
```

The reproducer prints one stable outcome category and applies the same one-MiB
input bound as the fuzz target.
