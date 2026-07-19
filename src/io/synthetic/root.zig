// SPDX-License-Identifier: Apache-2.0
//! Deterministic single-worker synthetic input/output queues. Setup owns copied
//! fixture bytes; receive, view, output submission, and completion only borrow
//! or transfer adapter tokens and never copy payload bytes.

const std = @import("std");
const foundation = @import("../../foundation/root.zig");
const packet = @import("../../packet/root.zig");

/// Whether a configured synthetic input accepts an empty packet record.
pub const ZeroLengthPolicy = enum { allow, reject };

/// Fixed input queue limits selected at construction.
pub const InputConfig = struct {
    capacity: usize,
    max_packet_length: usize,
    zero_length: ZeroLengthPolicy = .reject,
};

/// Receive scripting action consumed once per receive call.
pub const ReceiveAction = union(enum) {
    /// Return at most this many immediately available packets.
    ready: usize,
    /// Return an empty poll result even if input remains queued.
    idle,
    /// Return a deterministic input failure without changing tokens.
    fail,
};

/// Input setup/receive errors with bounded categories.
pub const InputError = error{
    OutOfMemory,
    QueueFull,
    PacketTooLarge,
    ZeroLengthForbidden,
    TooManySegments,
    InvalidSplit,
    ScriptTooLong,
    InvalidReceiveRequest,
    InputFailure,
    TokenFailure,
    DescriptorFailure,
};

const Record = struct {
    payload: []u8,
    split_storage: [packet.max_segments - 1]usize = undefined,
    split_count: u8,
    token: packet.AdapterToken,
};

/// Payload-copy instrumentation separates fixture setup from packet traversal.
pub const CopyCounters = struct {
    /// Bytes copied into queue-owned fixture storage before processing.
    setup_bytes: usize = 0,
    /// Payload bytes copied solely by receive/output abstraction. Must stay zero.
    packet_path_bytes: usize = 0,
};

/// Address-stable synthetic input queue and token owner.
///
/// Context: one test/worker thread. Allocation: construction and `enqueue`
/// only. `receive` is allocation-free and bounded by 64 packets × 16 segments.
/// Blocking: never. Call `verifyCompleted` before `deinit`; output traces that
/// borrow fixture slices must be destroyed first.
pub const InputQueue = struct {
    allocator: std.mem.Allocator,
    config: InputConfig,
    tracker: packet.TokenTracker,
    records: []Record,
    queued: usize = 0,
    next_receive: usize = 0,
    receive_sequence: u64 = 0,
    script: [packet.max_batch * 2]ReceiveAction = undefined,
    script_len: usize = 0,
    script_index: usize = 0,
    clock: foundation.DeterministicClock,
    copies: CopyCounters = .{},

    /// Allocates a fixed queue and exact token registry. Zero capacity is valid.
    pub fn init(allocator: std.mem.Allocator, config: InputConfig, start_time_ns: u64) InputError!InputQueue {
        var tracker = packet.TokenTracker.init(allocator, config.capacity) catch
            return error.OutOfMemory;
        errdefer tracker.deinit();
        const records = allocator.alloc(Record, config.capacity) catch
            return error.OutOfMemory;
        return .{
            .allocator = allocator,
            .config = config,
            .tracker = tracker,
            .records = records,
            .clock = .init(start_time_ns),
        };
    }

    /// Frees all setup-owned payloads and queue storage.
    /// Outstanding received tokens are a caller error detected by
    /// `verifyCompleted`; no payload is silently completed here.
    pub fn deinit(self: *InputQueue) void {
        for (self.records[0..self.queued]) |record|
            self.allocator.free(record.payload);
        self.allocator.free(self.records);
        self.tracker.deinit();
        self.* = undefined;
    }

    /// Copies one fixture packet into setup-owned storage. Split offsets are
    /// nondecreasing boundaries in `payload`; empty segments are valid.
    pub fn enqueue(self: *InputQueue, payload: []const u8, split_offsets: []const usize) InputError!void {
        if (self.queued == self.records.len) return error.QueueFull;
        if (payload.len > self.config.max_packet_length) return error.PacketTooLarge;
        if (payload.len == 0 and self.config.zero_length == .reject)
            return error.ZeroLengthForbidden;
        if (split_offsets.len + 1 > packet.max_segments) return error.TooManySegments;

        var previous: usize = 0;
        for (split_offsets) |offset| {
            if (offset < previous or offset > payload.len) return error.InvalidSplit;
            previous = offset;
        }

        const owned = self.allocator.dupe(u8, payload) catch return error.OutOfMemory;
        errdefer self.allocator.free(owned);
        const token = self.tracker.registerInput() catch return error.TokenFailure;

        var record = Record{
            .payload = owned,
            .split_count = @intCast(split_offsets.len),
            .token = token,
        };
        @memcpy(record.split_storage[0..split_offsets.len], split_offsets);
        self.records[self.queued] = record;
        self.queued += 1;
        self.copies.setup_bytes += payload.len;
    }

    /// Replaces the bounded deterministic receive script without allocation.
    pub fn setScript(self: *InputQueue, actions: []const ReceiveAction) InputError!void {
        if (actions.len > self.script.len) return error.ScriptTooLong;
        @memcpy(self.script[0..actions.len], actions);
        self.script_len = actions.len;
        self.script_index = 0;
    }

    fn nextAction(self: *InputQueue, requested: usize) ReceiveAction {
        if (self.script_index == self.script_len) return .{ .ready = requested };
        defer self.script_index += 1;
        return self.script[self.script_index];
    }

    /// Receives an immediately available partial batch in original queue order.
    /// `requested` must fit both caller slots and the framework maximum.
    pub fn receive(self: *InputQueue, slots: []packet.PacketSlot, requested: usize) InputError!usize {
        if (requested > slots.len or requested > packet.max_batch)
            return error.InvalidReceiveRequest;
        const action = self.nextAction(requested);
        const action_limit = switch (action) {
            .ready => |count| @min(count, requested),
            .idle => return 0,
            .fail => return error.InputFailure,
        };
        const available = self.queued - self.next_receive;
        const count = @min(action_limit, available);

        for (0..count) |output_index| {
            const record = &self.records[self.next_receive + output_index];
            record.token.receive() catch return error.TokenFailure;
            errdefer record.token.returnToInput() catch {};

            var descriptors: [packet.max_segments]packet.SegmentDescriptor = undefined;
            var start: usize = 0;
            for (record.split_storage[0..record.split_count], 0..) |end, segment_index| {
                descriptors[segment_index] = .fromBytes(record.payload[start..end]);
                start = end;
            }
            descriptors[record.split_count] = .fromBytes(record.payload[start..]);
            const descriptor_count: usize = @as(usize, record.split_count) + 1;
            slots[output_index] = packet.PacketSlot.init(
                record.token,
                descriptors[0..descriptor_count],
                record.payload.len,
                self.receive_sequence,
                .{ .timestamp_ns = self.clock.now().nanoseconds },
            ) catch return error.DescriptorFailure;
            self.receive_sequence = std.math.add(u64, self.receive_sequence, 1) catch
                return error.DescriptorFailure;
        }
        self.next_receive += count;
        return count;
    }

    /// Returns deterministic monotonic time for synthetic processing.
    pub fn now(self: *const InputQueue) foundation.MonotonicInstant {
        return self.clock.now();
    }

    /// Advances deterministic time or leaves it unchanged on overflow.
    pub fn advanceTime(self: *InputQueue, delta_ns: u64) error{Overflow}!void {
        try self.clock.advance(delta_ns);
    }

    /// Verifies INV-PKT-001 for every token that entered worker ownership.
    pub fn verifyCompleted(self: *const InputQueue) packet.TokenError!void {
        try self.tracker.verifyReceivedCompleted();
    }

    /// Returns setup-versus-packet-path payload-copy instrumentation.
    pub fn copyCounters(self: *const InputQueue) CopyCounters {
        return self.copies;
    }
};

/// Deterministic output behavior consumed once per submit attempt.
pub const SubmitAction = enum {
    accept_immediate,
    accept_delayed,
    backpressure,
    fail,
};

/// Bounded submit outcome. Backpressure/failure leave the token worker-owned.
pub const SubmitError = error{ Backpressure, OutputFailure, ScriptTooLong, TokenFailure, Bounds };

const Observation = struct {
    token: packet.AdapterToken,
    segments: [packet.max_segments][]const u8 = undefined,
    segment_count: u8,
    total_len: usize,
    pending: bool,
};

/// Address-stable deterministic output queue. Observations borrow payload owned
/// by the input queue and therefore must not outlive that queue.
pub const OutputQueue = struct {
    allocator: std.mem.Allocator,
    observations: []Observation,
    count: usize = 0,
    script: [packet.max_batch * 2]SubmitAction = undefined,
    script_len: usize = 0,
    script_index: usize = 0,
    packet_path_payload_copies: usize = 0,

    /// Allocates bounded output-observation storage.
    pub fn init(allocator: std.mem.Allocator, capacity: usize) std.mem.Allocator.Error!OutputQueue {
        return .{
            .allocator = allocator,
            .observations = try allocator.alloc(Observation, capacity),
        };
    }

    /// Releases observation metadata. It does not complete pending tokens.
    pub fn deinit(self: *OutputQueue) void {
        self.allocator.free(self.observations);
        self.* = undefined;
    }

    /// Replaces the bounded deterministic submission script.
    pub fn setScript(self: *OutputQueue, actions: []const SubmitAction) SubmitError!void {
        if (actions.len > self.script.len) return error.ScriptTooLong;
        @memcpy(self.script[0..actions.len], actions);
        self.script_len = actions.len;
        self.script_index = 0;
    }

    fn nextAction(self: *OutputQueue) SubmitAction {
        if (self.script_index == self.script_len) return .accept_immediate;
        defer self.script_index += 1;
        return self.script[self.script_index];
    }

    /// Attempts one output transfer without allocation or payload copy.
    pub fn submit(self: *OutputQueue, slot: *const packet.PacketSlot) SubmitError!void {
        if (self.count == self.observations.len) return error.Backpressure;
        const action = self.nextAction();
        switch (action) {
            .backpressure => return error.Backpressure,
            .fail => return error.OutputFailure,
            .accept_immediate, .accept_delayed => {},
        }

        const token = slot.adapterToken();
        token.submitOutput() catch return error.TokenFailure;
        errdefer token.completeOutput() catch {};

        var observation = Observation{
            .token = token,
            .segment_count = @intCast(slot.segmentCount()),
            .total_len = slot.length(),
            .pending = action == .accept_delayed,
        };
        for (0..slot.segmentCount()) |index|
            observation.segments[index] = slot.adapterSegment(index) catch return error.Bounds;
        self.observations[self.count] = observation;
        self.count += 1;

        if (action == .accept_immediate)
            token.completeOutput() catch return error.TokenFailure;
    }

    /// Completes one delayed observation. Completing it twice is rejected.
    pub fn complete(self: *OutputQueue, index: usize) SubmitError!void {
        if (index >= self.count) return error.Bounds;
        const observation = &self.observations[index];
        if (!observation.pending) return error.TokenFailure;
        observation.token.completeOutput() catch return error.TokenFailure;
        observation.pending = false;
    }

    /// Exact byte comparison over borrowed output segments without copying.
    pub fn matches(self: *const OutputQueue, index: usize, expected: []const u8) SubmitError!bool {
        if (index >= self.count) return error.Bounds;
        const observation = self.observations[index];
        if (expected.len != observation.total_len) return false;
        var offset: usize = 0;
        for (observation.segments[0..observation.segment_count]) |segment| {
            if (!std.mem.eql(u8, segment, expected[offset .. offset + segment.len])) return false;
            offset += segment.len;
        }
        return offset == expected.len;
    }

    /// Number of payload bytes copied solely by output abstraction.
    pub fn payloadCopyBytes(self: *const OutputQueue) usize {
        return self.packet_path_payload_copies;
    }

    /// Number of successfully accepted output records.
    pub fn acceptedCount(self: *const OutputQueue) usize {
        return self.count;
    }
};

fn inputConstructorCase(allocator: std.mem.Allocator) !void {
    var queue = try InputQueue.init(allocator, .{ .capacity = 2, .max_packet_length = 8 }, 0);
    defer queue.deinit();
}

fn inputEnqueueCase(allocator: std.mem.Allocator) !void {
    var queue = try InputQueue.init(allocator, .{ .capacity = 1, .max_packet_length = 8 }, 0);
    defer queue.deinit();
    try queue.enqueue(&.{ 1, 2, 3 }, &.{});
}

fn outputConstructorCase(allocator: std.mem.Allocator) !void {
    var queue = try OutputQueue.init(allocator, 2);
    defer queue.deinit();
}

test "every synthetic allocating constructor cleans up at every failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, inputConstructorCase, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, inputEnqueueCase, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, outputConstructorCase, .{});
}

test "FR-PKT-004 partial receive, scripted failure, backpressure, and delayed completion are deterministic" {
    var input = try InputQueue.init(std.testing.allocator, .{ .capacity = 3, .max_packet_length = 8 }, 10);
    defer input.deinit();
    try input.enqueue(&.{1}, &.{});
    try input.enqueue(&.{ 2, 3 }, &.{1});
    try input.enqueue(&.{4}, &.{});
    try input.setScript(&.{ .{ .ready = 2 }, .fail, .{ .ready = 1 } });

    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    try std.testing.expectEqual(@as(usize, 2), try input.receive(&slots, packet.max_batch));
    try std.testing.expectError(error.InputFailure, input.receive(&slots, packet.max_batch));
    try std.testing.expectEqual(@as(usize, 1), try input.receive(slots[2..], packet.max_batch - 2));
    var received_batch = try packet.PacketBatch.init(.{ .input_id = .init(1), .queue_id = .init(2) }, slots[0..3], 1);
    try std.testing.expectEqual(@as(u64, 10), (try (try received_batch.view(0)).metadata()).timestamp_ns.?);
    received_batch.invalidate();

    var output = try OutputQueue.init(std.testing.allocator, 3);
    defer output.deinit();
    try output.setScript(&.{ .backpressure, .fail, .accept_delayed, .accept_immediate, .accept_immediate });
    try std.testing.expectError(error.Backpressure, output.submit(&slots[0]));
    try std.testing.expectEqual(packet.TokenState.worker_owned, try slots[0].adapterToken().state());
    try std.testing.expectError(error.OutputFailure, output.submit(&slots[0]));
    try output.submit(&slots[0]);
    try std.testing.expectError(error.MissingCompletion, input.verifyCompleted());
    try output.complete(0);
    try output.submit(&slots[1]);
    try output.submit(&slots[2]);
    try input.verifyCompleted();
    try std.testing.expectEqual(@as(usize, 0), output.payloadCopyBytes());
}

test "FR-TEST-002 INV-PKT-001 PERF-CORE-004 all packet sizes traverse unchanged under explicit zero-length policy without payload copy" {
    const configured_max: usize = 256;
    var input = try InputQueue.init(std.testing.allocator, .{
        .capacity = configured_max + 1,
        .max_packet_length = configured_max,
        .zero_length = .allow,
    }, 0);
    defer input.deinit();
    var expected: [configured_max]u8 = undefined;
    for (&expected, 0..) |*byte, index| byte.* = @truncate(index *% 37);
    for (0..configured_max + 1) |size|
        try input.enqueue(expected[0..size], if (size > 1) &.{size / 2} else &.{});

    var output = try OutputQueue.init(std.testing.allocator, configured_max + 1);
    defer output.deinit();
    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    var accepted: usize = 0;
    while (accepted < configured_max + 1) {
        const count = try input.receive(&slots, packet.max_batch);
        try std.testing.expect(count > 0);
        for (slots[0..count]) |*slot| {
            try output.submit(slot);
            const size = accepted;
            try std.testing.expect(try output.matches(accepted, expected[0..size]));
            accepted += 1;
        }
    }
    try input.verifyCompleted();
    try std.testing.expectEqual(@as(usize, 0), input.copyCounters().packet_path_bytes);
    try std.testing.expectEqual(@as(usize, 0), output.payloadCopyBytes());

    var rejecting = try InputQueue.init(std.testing.allocator, .{
        .capacity = 1,
        .max_packet_length = 1,
        .zero_length = .reject,
    }, 0);
    defer rejecting.deinit();
    try std.testing.expectError(error.ZeroLengthForbidden, rejecting.enqueue(&.{}, &.{}));
}

test "FR-PKT-002 every possible segment split preserves packet bytes and receive order" {
    const bytes = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    var input = try InputQueue.init(std.testing.allocator, .{ .capacity = bytes.len + 1, .max_packet_length = bytes.len }, 0);
    defer input.deinit();
    for (0..bytes.len + 1) |split| try input.enqueue(&bytes, &.{split});

    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    const count = try input.receive(&slots, packet.max_batch);
    try std.testing.expectEqual(bytes.len + 1, count);
    var batch = try packet.PacketBatch.init(.{ .input_id = .init(4), .queue_id = .init(9) }, slots[0..count], 17);
    for (0..count) |index| {
        var actual: [bytes.len]u8 = undefined;
        try (try batch.view(index)).read(.{ .offset = 0, .len = bytes.len }, &actual);
        try std.testing.expectEqualSlices(u8, &bytes, &actual);
    }
    batch.invalidate();
    for (slots[0..count]) |slot| try slot.adapterToken().returnToInput();
    try input.verifyCompleted();
}
