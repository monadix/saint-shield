// SPDX-License-Identifier: Apache-2.0
//! Public deterministic testing helpers shared by property and adapter tests.
//! Packet fixtures use `io.synthetic`; this module standardizes bounded seeded
//! traces so every randomized failure reports a reproducer seed and minimized
//! operation trace.

const std = @import("std");

/// Default deterministic seed for short M1 property runs.
pub const default_seed: u64 = 0x5341_494e_545f_4d31;

/// Seeded pseudo-random source with a bounded human-readable operation trace.
///
/// Context: tests only. Allocation: none. Blocking: never except diagnostic
/// stderr output after a failed assertion. The trace truncates explicitly when
/// its configured byte bound is reached.
pub fn SeededTrace(comptime max_trace_bytes: usize) type {
    return struct {
        seed: u64,
        prng: std.Random.DefaultPrng,
        storage: [max_trace_bytes]u8 = undefined,
        used: usize = 0,
        truncated: bool = false,

        const Self = @This();

        /// Initializes a reproducible pseudo-random sequence and empty trace.
        pub fn init(seed: u64) Self {
            return .{ .seed = seed, .prng = .init(seed) };
        }

        /// Returns the deterministic random interface owned by this run.
        pub fn random(self: *Self) std.Random {
            return self.prng.random();
        }

        /// Appends one already-minimized operation description when space
        /// remains; excess bytes set `truncated` and are never allocated.
        pub fn append(self: *Self, operation: []const u8) void {
            if (self.truncated) return;
            const separator_len: usize = if (self.used == 0) 0 else 1;
            const required = std.math.add(usize, separator_len, operation.len) catch {
                self.truncated = true;
                return;
            };
            if (required > self.storage.len - self.used) {
                self.truncated = true;
                return;
            }
            if (separator_len != 0) {
                self.storage[self.used] = ';';
                self.used += 1;
            }
            @memcpy(self.storage[self.used .. self.used + operation.len], operation);
            self.used += operation.len;
        }

        /// Returns the bounded minimized operation trace accumulated so far.
        pub fn minimizedTrace(self: *const Self) []const u8 {
            return self.storage[0..self.used];
        }

        /// Prints the required deterministic failure reproducer fields.
        pub fn reportFailure(self: *const Self) void {
            std.debug.print(
                "seed={d} toolchain=zig-0.16.0 minimized_trace={s}{s}\n",
                .{ self.seed, self.minimizedTrace(), if (self.truncated) ";<truncated>" else "" },
            );
        }
    };
}

test "seeded traces reproduce values and retain bounded minimized operations" {
    const Trace = SeededTrace(16);
    var first = Trace.init(default_seed);
    var second = Trace.init(default_seed);
    try std.testing.expectEqual(first.random().int(u64), second.random().int(u64));
    first.append("receive(2)");
    first.append("drop(1)");
    try std.testing.expectEqualStrings("receive(2)", first.minimizedTrace());
    try std.testing.expect(first.truncated);
}
