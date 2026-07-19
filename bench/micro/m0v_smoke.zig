const std = @import("std");
const saint_shield = @import("saint_shield");

pub fn main() !void {
    const start = std.time.nanoTimestamp();
    var accumulator: usize = 0;
    for (0..100_000) |index| accumulator +%= index;
    const elapsed = std.time.nanoTimestamp() - start;
    const out = std.fs.File.stdout();
    try out.writeAll("M0-V synthetic regression smoke (not a capacity claim)\n");
    try out.deprecatedWriter().print("framework={s} iterations=100000 elapsed_ns={d} checksum={d}\n", .{
        saint_shield.version,
        elapsed,
        accumulator,
    });
}

