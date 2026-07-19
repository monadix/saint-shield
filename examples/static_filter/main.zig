const std = @import("std");
const saint_shield = @import("saint_shield");

pub fn main() !void {
    try std.fs.File.stdout().writeAll("saint-shield " ++ saint_shield.version ++ " scaffold ready\n");
}

