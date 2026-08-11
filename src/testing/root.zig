// SPDX-License-Identifier: Apache-2.0
//! Public deterministic testing helpers shared by property and adapter tests.
//! Packet fixtures use `io.synthetic`; this module standardizes bounded seeded
//! traces so every randomized failure reports a reproducer seed and minimized
//! operation trace.

const std = @import("std");
const packet = @import("../packet/root.zig");

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

        /// Structured fields emitted for every randomized failure.
        pub const FailureReport = struct {
            seed: u64,
            toolchain: []const u8,
            minimized_trace: []const u8,
            truncated: bool,
        };

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

        /// Returns the exact fields used by the stderr failure reporter.
        pub fn failureReport(self: *const Self) FailureReport {
            return .{
                .seed = self.seed,
                .toolchain = "zig-0.16.0",
                .minimized_trace = self.minimizedTrace(),
                .truncated = self.truncated,
            };
        }

        /// Prints the required deterministic failure reproducer fields.
        pub fn reportFailure(self: *const Self) void {
            const report = self.failureReport();
            std.debug.print(
                "seed={d} toolchain={s} minimized_trace={s}{s}\n",
                .{
                    report.seed,
                    report.toolchain,
                    report.minimized_trace,
                    if (report.truncated) ";<truncated>" else "",
                },
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
    const report = first.failureReport();
    try std.testing.expectEqual(default_seed, report.seed);
    try std.testing.expectEqualStrings("zig-0.16.0", report.toolchain);
    try std.testing.expectEqualStrings("receive(2)", report.minimized_trace);
    try std.testing.expect(report.truncated);
}

test "FR-PKT-010 M2 selection matches a u64 oracle with bounded seeded failure traces" {
    const base_seed: u64 = 0x6d325f73656c6563;
    const Trace = SeededTrace(2048);
    for (0..2_000) |case_index| {
        const seed = base_seed +% case_index;
        var trace = Trace.init(seed);
        const random = trace.random();
        const batch_len = random.uintLessThan(usize, packet.max_batch + 1);
        var operation_buffer: [48]u8 = undefined;
        trace.append(std.fmt.bufPrint(
            &operation_buffer,
            "batch({d})",
            .{batch_len},
        ) catch unreachable);
        var selection = try packet.PacketSelection.all(batch_len);
        var oracle = @intFromEnum(selection);
        for (0..128) |_| {
            if (batch_len != 0) {
                const raw = random.uintLessThan(usize, batch_len);
                const index = try packet.PacketIndex.init(raw, batch_len);
                if (random.boolean()) {
                    trace.append(std.fmt.bufPrint(
                        &operation_buffer,
                        "without({d})",
                        .{raw},
                    ) catch unreachable);
                    selection = try selection.without(index, batch_len);
                    oracle &= ~(@as(u64, 1) << @intCast(raw));
                } else {
                    trace.append(std.fmt.bufPrint(
                        &operation_buffer,
                        "intersect({d})",
                        .{raw},
                    ) catch unreachable);
                    const singleton = try packet.PacketSelection.one(raw, batch_len);
                    selection = selection.intersect(singleton);
                    oracle &= @as(u64, 1) << @intCast(raw);
                }
            } else {
                trace.append("empty-step");
            }
            if (oracle != @intFromEnum(selection) or
                @as(usize, @popCount(oracle)) != selection.count())
            {
                trace.reportFailure();
                return error.TestExpectedEqual;
            }
        }
        var iterator = selection.iterator();
        var previous: ?usize = null;
        var observed: u64 = 0;
        while (iterator.next()) |index| {
            if (previous) |value| {
                if (index.raw() <= value) {
                    trace.append("iterator-order");
                    trace.reportFailure();
                    return error.TestExpectedEqual;
                }
            }
            previous = index.raw();
            observed |= @as(u64, 1) << @intCast(index.raw());
        }
        if (oracle != observed) {
            trace.append("iterator-bits");
            trace.reportFailure();
            return error.TestExpectedEqual;
        }
    }
    try std.testing.expectError(error.OutOfRange, packet.PacketIndex.init(1, 1));
    try std.testing.expectError(
        error.BatchTooLarge,
        packet.PacketSelection.all(packet.max_batch + 1),
    );
}

fn tracedCheck(trace: anytype, condition: bool) !void {
    if (condition) return;
    trace.reportFailure();
    return error.TestExpectedEqual;
}

fn expectTracedError(trace: anytype, expected: anyerror, result: anytype) !void {
    if (result) |_| {
        trace.reportFailure();
        return error.TestExpectedError;
    } else |actual| {
        if (actual != expected) {
            trace.reportFailure();
            return error.TestUnexpectedError;
        }
    }
}

fn dispositionStateMatches(
    writer: packet.DispositionWriter,
    owner: *packet.PacketBatchOwner,
    active_bits: u64,
    expected: []const packet.PacketDisposition,
) !bool {
    if (@intFromEnum(try writer.activeSelection(owner)) != active_bits) return false;
    for (expected, 0..) |disposition, index|
        if (!std.meta.eql(disposition, try writer.get(owner, index))) return false;
    return true;
}

fn resolvedDisposition(
    disposition: packet.PacketDisposition,
    policy: packet.ContinuePolicy,
) packet.PacketDisposition {
    return switch (disposition) {
        .Continue => switch (policy) {
            .accept => |output| .{ .Accept = output },
            .drop => |reason| .{ .Drop = reason },
            .complete => |id| .{ .Complete = id },
        },
        else => disposition,
    };
}

test "FR-PKT-010 FR-PKT-011 M2 seeded reference model covers every disposition and token outcome" {
    const base_seed: u64 = 0x6d325f646973706f;
    const Trace = SeededTrace(4096);
    const batch_len = 12;
    const outputs = [_]packet.OutputId{ .init(1), .init(2), .init(3) };
    const fixture = [_]u8{0};
    const descriptors = [_]packet.SegmentDescriptor{.fromBytes(&fixture)};

    for (0..48) |case_index| {
        const seed = base_seed +% case_index;
        var trace = Trace.init(seed);
        const random = trace.random();
        var operation_buffer: [64]u8 = undefined;
        var tracker = try packet.TokenTracker.init(std.testing.allocator, batch_len);
        defer tracker.deinit();
        var tokens: [batch_len]packet.AdapterToken = undefined;
        var slots: [batch_len]packet.PacketSlot = undefined;
        for (&slots, &tokens, 0..) |*slot, *token, index| {
            token.* = try tracker.registerInput();
            try token.receive();
            slot.* = try packet.PacketSlot.init(
                token.*,
                &descriptors,
                fixture.len,
                index,
                .{},
                null,
            );
        }
        const owner = try packet.PacketBatchOwner.init(std.testing.allocator);
        defer owner.deinit();
        const batch = try owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            &slots,
        );
        const writer = try packet.DispositionWriter.init(batch, owner);
        var pool = try packet.RetentionPool.init(std.testing.allocator, 2);
        defer pool.deinit();

        var expected = [_]packet.PacketDisposition{.Continue} ** batch_len;
        var expected_active = (@as(u64, 1) << batch_len) - 1;
        var operation_order: [batch_len]usize = undefined;
        for (&operation_order, 0..) |*index, value| index.* = value;
        var remaining = operation_order.len;
        while (remaining > 1) {
            const swap_index = random.uintLessThan(usize, remaining);
            remaining -= 1;
            std.mem.swap(usize, &operation_order[remaining], &operation_order[swap_index]);
        }
        const rotation = random.uintLessThan(usize, 6);
        var retained_lease: ?packet.RetentionLease = null;
        var active_index: ?usize = null;
        var terminal_index: ?usize = null;

        for (operation_order) |index| {
            const kind = (index + rotation) % 6;
            const disposition: packet.PacketDisposition = switch (kind) {
                0 => .Continue,
                1 => .{ .Accept = if (random.boolean()) null else outputs[0] },
                2 => .{ .Drop = if (random.boolean()) null else .init(100 + index) },
                3 => .{ .Redirect = .{
                    .output = outputs[1 + random.uintLessThan(usize, 2)],
                    .metadata = if (random.boolean()) null else .init(200 + index),
                } },
                4 => .{ .Retain = undefined },
                5 => .{ .Complete = .init(300 + index) },
                else => unreachable,
            };
            trace.append(std.fmt.bufPrint(
                &operation_buffer,
                "{s}({d})",
                .{ @tagName(disposition), index },
            ) catch unreachable);
            if (kind == 0) {
                active_index = index;
            } else if (kind == 4) {
                const lease = writer.retain(batch, owner, &pool, index) catch |err| {
                    trace.reportFailure();
                    return err;
                };
                expected[index] = .{ .Retain = lease };
                retained_lease = lease;
                terminal_index = index;
                expected_active &= ~(@as(u64, 1) << @intCast(index));
            } else {
                writer.set(owner, index, disposition) catch |err| {
                    trace.reportFailure();
                    return err;
                };
                expected[index] = disposition;
                terminal_index = index;
                expected_active &= ~(@as(u64, 1) << @intCast(index));
            }
            try tracedCheck(
                &trace,
                dispositionStateMatches(writer, owner, expected_active, &expected) catch |err| {
                    trace.reportFailure();
                    return err;
                },
            );
        }

        const active = active_index.?;
        const terminal = terminal_index.?;
        const lease = retained_lease.?;
        const active_selection = try packet.PacketSelection.one(active, batch_len);
        const terminal_selection = try packet.PacketSelection.one(terminal, batch_len);
        const forged_selection: packet.PacketSelection = @enumFromInt(@as(u64, 1) << batch_len);
        trace.append("invalid(empty)");
        try expectTracedError(
            &trace,
            error.EmptySelection,
            writer.setSelection(owner, packet.PacketSelection.empty(), .{ .Drop = null }),
        );
        try tracedCheck(&trace, try dispositionStateMatches(writer, owner, expected_active, &expected));
        trace.append("invalid(continue)");
        try expectTracedError(
            &trace,
            error.NotTerminal,
            writer.setSelection(owner, active_selection, .Continue),
        );
        try tracedCheck(&trace, try dispositionStateMatches(writer, owner, expected_active, &expected));
        trace.append("invalid(stale)");
        try expectTracedError(
            &trace,
            error.StaleSelection,
            writer.setSelection(owner, terminal_selection, .{ .Drop = null }),
        );
        try tracedCheck(&trace, try dispositionStateMatches(writer, owner, expected_active, &expected));
        trace.append("invalid(range)");
        try expectTracedError(
            &trace,
            error.OutOfRange,
            writer.setSelection(owner, forged_selection, .{ .Drop = null }),
        );
        try tracedCheck(&trace, try dispositionStateMatches(writer, owner, expected_active, &expected));
        trace.append("invalid(retain)");
        try expectTracedError(
            &trace,
            error.RetentionRequiresBinding,
            writer.setSelection(owner, active_selection, .{ .Retain = lease }),
        );
        try tracedCheck(&trace, try dispositionStateMatches(writer, owner, expected_active, &expected));
        for (tokens, 0..) |token, index| {
            const expected_state: packet.TokenState = switch (expected[index]) {
                .Retain => .retained,
                else => .worker_owned,
            };
            try tracedCheck(&trace, try token.state() == expected_state);
        }

        const continue_policy: packet.ContinuePolicy = switch (case_index % 3) {
            0 => .{ .accept = if ((case_index / 3) % 2 == 0) null else outputs[0] },
            1 => .{ .drop = if ((case_index / 3) % 2 == 0) null else .init(901) },
            2 => .{ .complete = .init(902) },
            else => unreachable,
        };
        trace.append(std.fmt.bufPrint(
            &operation_buffer,
            "resolve({s})",
            .{@tagName(continue_policy)},
        ) catch unreachable);
        const groups = packet.DispositionGroups.resolve(writer, owner, .{
            .outputs = &outputs,
            .default_output = outputs[2],
            .continue_policy = continue_policy,
        }) catch |err| {
            trace.reportFailure();
            return err;
        };
        try tracedCheck(&trace, groups.output_count == outputs.len);
        var output_cursors = [_]usize{0} ** outputs.len;
        var drop_cursor: usize = 0;
        var completion_cursor: usize = 0;
        var retention_cursor: usize = 0;
        for (groups.outputs[0..groups.output_count], outputs) |group, output|
            try tracedCheck(&trace, group.output.raw() == output.raw());

        for (expected, 0..) |recorded, index| {
            const disposition = resolvedDisposition(recorded, continue_policy);
            switch (disposition) {
                .Continue => unreachable,
                .Accept => |maybe_output| {
                    const output = maybe_output orelse outputs[2];
                    var output_index: usize = 0;
                    while (outputs[output_index].raw() != output.raw()) : (output_index += 1) {}
                    try tracedCheck(
                        &trace,
                        output_cursors[output_index] < groups.outputs[output_index].count,
                    );
                    const item = groups.outputs[output_index].items[output_cursors[output_index]];
                    try tracedCheck(&trace, item.index.raw() == index);
                    try tracedCheck(&trace, item.redirect_metadata == null);
                    output_cursors[output_index] += 1;
                },
                .Redirect => |redirect| {
                    var output_index: usize = 0;
                    while (outputs[output_index].raw() != redirect.output.raw()) : (output_index += 1) {}
                    try tracedCheck(
                        &trace,
                        output_cursors[output_index] < groups.outputs[output_index].count,
                    );
                    const item = groups.outputs[output_index].items[output_cursors[output_index]];
                    try tracedCheck(&trace, item.index.raw() == index);
                    try tracedCheck(&trace, std.meta.eql(item.redirect_metadata, redirect.metadata));
                    output_cursors[output_index] += 1;
                },
                .Drop => |reason| {
                    try tracedCheck(&trace, drop_cursor < groups.drop_count);
                    const item = groups.drops[drop_cursor];
                    try tracedCheck(&trace, item.index.raw() == index);
                    try tracedCheck(&trace, std.meta.eql(item.reason, reason));
                    drop_cursor += 1;
                },
                .Complete => |id| {
                    try tracedCheck(&trace, completion_cursor < groups.completion_count);
                    const item = groups.completions[completion_cursor];
                    try tracedCheck(&trace, item.index.raw() == index);
                    try tracedCheck(&trace, item.id.raw() == id.raw());
                    completion_cursor += 1;
                },
                .Retain => |expected_lease| {
                    try tracedCheck(&trace, retention_cursor < groups.retention_count);
                    const item = groups.retentions[retention_cursor];
                    try tracedCheck(&trace, item.index.raw() == index);
                    try tracedCheck(&trace, @intFromEnum(item.lease) == @intFromEnum(expected_lease));
                    retention_cursor += 1;
                },
            }
        }
        for (groups.outputs[0..groups.output_count], output_cursors) |group, count|
            try tracedCheck(&trace, group.count == count);
        try tracedCheck(&trace, groups.drop_count == drop_cursor);
        try tracedCheck(&trace, groups.completion_count == completion_cursor);
        try tracedCheck(&trace, groups.retention_count == retention_cursor);

        try batch.invalidate(owner);
        for (expected, tokens, 0..) |recorded, token, index| {
            const disposition = resolvedDisposition(recorded, continue_policy);
            const final_state: packet.TokenState = switch (disposition) {
                .Accept, .Redirect => state: {
                    token.submitOutput() catch |err| {
                        trace.reportFailure();
                        return err;
                    };
                    token.completeOutput() catch |err| {
                        trace.reportFailure();
                        return err;
                    };
                    break :state .completed;
                },
                .Drop, .Complete => state: {
                    token.returnToInput() catch |err| {
                        trace.reportFailure();
                        return err;
                    };
                    break :state .returned_to_input;
                },
                .Retain => |retention| state: {
                    retention.complete(&pool) catch |err| {
                        trace.reportFailure();
                        return err;
                    };
                    break :state .completed;
                },
                .Continue => unreachable,
            };
            trace.append(std.fmt.bufPrint(
                &operation_buffer,
                "complete({d})",
                .{index},
            ) catch unreachable);
            try tracedCheck(&trace, try token.state() == final_state);
        }
        pool.verifyShutdown() catch |err| {
            trace.reportFailure();
            return err;
        };
        tracker.verifyReceivedCompleted() catch |err| {
            trace.reportFailure();
            return err;
        };
        try tracedCheck(&trace, tracker.receivedCount() == batch_len);
        try tracedCheck(&trace, tracker.completionCount() == batch_len);
    }
}
