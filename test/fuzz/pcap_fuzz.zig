// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const pcap = @import("pcap");

const fuzz_limits = pcap.Limits{
    .max_capture_bytes = 1024 * 1024,
    .max_records = 4096,
    .max_snaplen = 256 * 1024,
    .zero_length_records = .allow,
};

/// Parses one bounded raw input and returns a stable outcome code to the C
/// launcher. Parse failures are expected input outcomes, never process faults.
export fn saint_pcap_fuzz(data: [*]const u8, length: usize) c_int {
    const bytes = data[0..length];
    var parser = pcap.Parser.init(bytes, fuzz_limits) catch |err|
        return outcomeCode(pcap.classifyError(err));

    var digest: u64 = parser.header.snaplen;
    while (parser.next() catch |err|
        return outcomeCode(pcap.classifyError(err))) |record|
    {
        digest +%= record.original_len;
        if (record.timestamp) |timestamp| {
            digest +%= timestamp.seconds;
            digest +%= timestamp.fraction;
        }
        for (record.data) |byte| digest +%= byte;
    }
    std.mem.doNotOptimizeAway(digest);
    return 0;
}

fn outcomeCode(class: pcap.ErrorClass) c_int {
    return @as(c_int, @intCast(@intFromEnum(class))) + 1;
}
