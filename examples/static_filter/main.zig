// SPDX-License-Identifier: Apache-2.0
//! Hardware-free package-import smoke; the static filter arrives after M3.

const std = @import("std");
const saint_shield = @import("saint_shield");

/// Prints the imported scaffold version without allocating framework state.
pub fn main() !void {
    std.debug.print("saint-shield {s} scaffold ready\n", .{saint_shield.version});
}
