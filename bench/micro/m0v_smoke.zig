// SPDX-License-Identifier: Apache-2.0
//! Synthetic build/run regression smoke, never a production capacity result.

const std = @import("std");
const saint_shield = @import("saint_shield");

/// Executes a bounded integer loop to prove the benchmark command is runnable.
pub fn main() !void {
    var accumulator: usize = 0;
    for (0..100_000) |index| accumulator +%= index;
    std.debug.print("M0-V synthetic regression smoke (not a capacity claim)\n", .{});
    std.debug.print("framework={s} iterations=100000 checksum={d}\n", .{
        saint_shield.version,
        accumulator,
    });
}
