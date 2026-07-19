// SPDX-License-Identifier: Apache-2.0
//! Dependency-free bounded value contracts shared by packet and adapter code.
//! Stable identifiers are opaque numeric values, budgets reject before their
//! hard limit, and packet-path time is monotonic nanoseconds. None allocates or
//! blocks.

const std = @import("std");

/// Creates a distinct stable numeric identifier type.
///
/// All bit patterns are values; interpretation and persistence belong to the
/// declaring subsystem. Construction, comparison, and formatting allocate
/// nothing and are thread-safe value operations.
pub fn StableId(comptime tag: type) type {
    return struct {
        value: u64,

        const Self = @This();

        /// Constructs an identifier without reserving sentinel values.
        pub fn init(value: u64) Self {
            return .{ .value = value };
        }

        /// Returns the stable numeric representation.
        pub fn raw(self: Self) u64 {
            return self.value;
        }

        comptime {
            _ = tag;
        }
    };
}

/// Bounded error identity suitable for packet-path propagation.
/// `detail` is subsystem-defined numeric context, never an owned string.
pub const BoundedError = struct {
    code: Code,
    detail: u32 = 0,

    /// Stable framework-wide error categories introduced by M1.
    pub const Code = enum(u16) {
        invalid_argument = 1,
        bounds = 2,
        overflow = 3,
        resource_exhausted = 4,
        invalid_state = 5,
        malformed_input = 6,
        truncated_input = 7,
        unsupported = 8,
        input_failure = 9,
        output_failure = 10,
    };
};

/// Hard accounting limit with current and peak byte counts.
///
/// Context: preparation/assembly accounting. Complexity: O(1). Allocation:
/// none. Blocking: never. The owner serializes mutation; snapshots are values.
pub const Budget = struct {
    limit: usize,
    current: usize = 0,
    peak: usize = 0,

    /// Budget accounting failures. `Overflow` leaves all counters unchanged;
    /// `Underflow` means release exceeded the live reservation.
    pub const Error = error{ Overflow, Underflow };

    /// Creates a budget with a fixed inclusive byte limit.
    pub fn init(limit: usize) Budget {
        return .{ .limit = limit };
    }

    /// Reserves bytes or rejects atomically without changing accounting.
    pub fn reserve(self: *Budget, amount: usize) Error!void {
        const next = std.math.add(usize, self.current, amount) catch
            return error.Overflow;
        if (next > self.limit) return error.Overflow;
        self.current = next;
        self.peak = @max(self.peak, next);
    }

    /// Releases a prior reservation or reports accounting underflow.
    pub fn release(self: *Budget, amount: usize) Error!void {
        if (amount > self.current) return error.Underflow;
        self.current -= amount;
    }

    /// Reports the remaining capacity without arithmetic wraparound.
    pub fn remaining(self: Budget) usize {
        return self.limit - self.current;
    }
};

/// Monotonic time measured in nanoseconds from an unspecified local epoch.
pub const MonotonicInstant = struct {
    nanoseconds: u64,

    /// Creates an instant from a monotonic nanosecond count.
    pub fn init(nanoseconds: u64) MonotonicInstant {
        return .{ .nanoseconds = nanoseconds };
    }

    /// Returns elapsed nanoseconds, rejecting reversed observations.
    pub fn elapsedSince(self: MonotonicInstant, earlier: MonotonicInstant) error{TimeReversed}!u64 {
        if (self.nanoseconds < earlier.nanoseconds) return error.TimeReversed;
        return self.nanoseconds - earlier.nanoseconds;
    }
};

/// Deterministic monotonic clock for tests and synthetic adapters.
/// The owning test thread mutates it; reads allocate nothing and never block.
pub const DeterministicClock = struct {
    now_ns: u64 = 0,

    /// Creates a clock at the supplied local epoch.
    pub fn init(start_ns: u64) DeterministicClock {
        return .{ .now_ns = start_ns };
    }

    /// Returns the current monotonic instant.
    pub fn now(self: *const DeterministicClock) MonotonicInstant {
        return .init(self.now_ns);
    }

    /// Advances by a bounded delta; overflow leaves time unchanged.
    pub fn advance(self: *DeterministicClock, delta_ns: u64) error{Overflow}!void {
        const next = std.math.add(u64, self.now_ns, delta_ns) catch
            return error.Overflow;
        self.now_ns = next;
    }

    /// Moves to `instant`; backwards movement is rejected unchanged.
    pub fn set(self: *DeterministicClock, instant: MonotonicInstant) error{TimeReversed}!void {
        if (instant.nanoseconds < self.now_ns) return error.TimeReversed;
        self.now_ns = instant.nanoseconds;
    }
};

test "stable identifier types do not mix" {
    const A = StableId(enum { a });
    const B = StableId(enum { b });
    const a = A.init(7);
    const b = B.init(7);
    try std.testing.expectEqual(@as(u64, 7), a.raw());
    try std.testing.expectEqual(@as(u64, 7), b.raw());
    try std.testing.expect(A != B);
}

test "budget reserve is checked and failure atomic" {
    var budget = Budget.init(9);
    try budget.reserve(4);
    try budget.reserve(5);
    try std.testing.expectEqual(@as(usize, 9), budget.peak);
    try std.testing.expectError(error.Overflow, budget.reserve(1));
    try std.testing.expectEqual(@as(usize, 9), budget.current);
    try std.testing.expectError(error.Underflow, budget.release(10));
    try std.testing.expectEqual(@as(usize, 9), budget.current);
    try budget.release(9);
}

test "budget arithmetic cannot wrap" {
    var budget = Budget.init(std.math.maxInt(usize));
    try budget.reserve(std.math.maxInt(usize));
    try std.testing.expectError(error.Overflow, budget.reserve(1));
    try std.testing.expectEqual(std.math.maxInt(usize), budget.current);
}

test "deterministic clock is monotonic and overflow checked" {
    var clock = DeterministicClock.init(11);
    const before = clock.now();
    try clock.advance(9);
    try std.testing.expectEqual(@as(u64, 9), try clock.now().elapsedSince(before));
    try std.testing.expectError(error.TimeReversed, clock.set(.init(19)));
    try std.testing.expectEqual(@as(u64, 20), clock.now().nanoseconds);

    var end = DeterministicClock.init(std.math.maxInt(u64));
    try std.testing.expectError(error.Overflow, end.advance(1));
    try std.testing.expectEqual(std.math.maxInt(u64), end.now().nanoseconds);
}
