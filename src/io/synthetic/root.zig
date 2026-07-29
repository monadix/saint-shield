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
    /// Inject descriptor adaptation failure at a later slot before any token
    /// or receive cursor changes.
    descriptor_failure: struct {
        ready: usize,
        at: usize,
    },
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
    Bounds,
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
    /// Bytes copied only because a caller explicitly invoked `PacketView.read`.
    explicit_read_bytes: usize = 0,
    /// Borrowed segment operations observed on the ordinary packet path.
    segment_borrows: usize = 0,
    /// Successful allocation-free receive operations.
    receive_calls: usize = 0,
    /// Attempted allocation-free output submissions.
    submit_calls: usize = 0,
};

/// Exact calls observed by an allocator wrapper.
pub const AllocationSnapshot = struct {
    alloc_calls: usize = 0,
    resize_calls: usize = 0,
    remap_calls: usize = 0,
    free_calls: usize = 0,

    /// Allocation or growth operations forbidden on the ordinary packet path.
    pub fn allocationActivity(self: AllocationSnapshot) usize {
        return self.alloc_calls + self.resize_calls + self.remap_calls;
    }
};

/// Address-stable allocator wrapper used to prove packet-path allocation
/// freedom. Construct it outside the queues and pass `allocator()` to every
/// queue whose activity must be included in the proof.
pub const CountingAllocator = struct {
    child: std.mem.Allocator,
    counts: AllocationSnapshot = .{},

    /// Wraps one backing allocator without allocating.
    pub fn init(child: std.mem.Allocator) CountingAllocator {
        return .{ .child = child };
    }

    /// Returns an allocator whose vtable records real allocator calls.
    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = allocate,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    /// Returns an immutable observation for before/after comparison.
    pub fn snapshot(self: *const CountingAllocator) AllocationSnapshot {
        return self.counts;
    }

    fn context(raw: *anyopaque) *CountingAllocator {
        return @ptrCast(@alignCast(raw));
    }

    fn allocate(
        raw: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) ?[*]u8 {
        const self = context(raw);
        self.counts.alloc_calls += 1;
        return self.child.rawAlloc(len, alignment, return_address);
    }

    fn resize(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        return_address: usize,
    ) bool {
        const self = context(raw);
        self.counts.resize_calls += 1;
        return self.child.rawResize(memory, alignment, new_len, return_address);
    }

    fn remap(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        return_address: usize,
    ) ?[*]u8 {
        const self = context(raw);
        self.counts.remap_calls += 1;
        return self.child.rawRemap(memory, alignment, new_len, return_address);
    }

    fn free(
        raw: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        return_address: usize,
    ) void {
        const self = context(raw);
        self.counts.free_calls += 1;
        self.child.rawFree(memory, alignment, return_address);
    }
};

/// Stable value representation of one adapter-owned segment.
pub const SegmentIdentity = struct {
    address: usize,
    len: usize,
};

/// PERF-CORE-004 guard failures.
pub const PacketPathGuardError = error{
    PayloadCopyObserved,
    GeneralAllocationObserved,
};

/// Rejects any abstraction payload copy or allocator activity between two
/// observations. Counter underflow also rejects the evidence.
pub fn verifyPacketPathGuard(
    before_path: packet.PacketPathSnapshot,
    after_path: packet.PacketPathSnapshot,
    before_allocator: AllocationSnapshot,
    after_allocator: AllocationSnapshot,
) PacketPathGuardError!void {
    if (after_path.abstraction_payload_copy_bytes <
        before_path.abstraction_payload_copy_bytes or
        after_path.abstraction_payload_copy_bytes !=
            before_path.abstraction_payload_copy_bytes)
    {
        return error.PayloadCopyObserved;
    }
    if (after_allocator.alloc_calls < before_allocator.alloc_calls or
        after_allocator.resize_calls < before_allocator.resize_calls or
        after_allocator.remap_calls < before_allocator.remap_calls or
        after_allocator.allocationActivity() != before_allocator.allocationActivity())
    {
        return error.GeneralAllocationObserved;
    }
}

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
    packet_path: packet.PacketPathInstrumentation = .{},

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

    /// Returns the number of adapter-owned segments for one queued record.
    /// This setup-time identity query never transfers packet ownership.
    pub fn queuedSegmentCount(self: *const InputQueue, record_index: usize) InputError!usize {
        if (record_index >= self.queued) return error.Bounds;
        return @as(usize, self.records[record_index].split_count) + 1;
    }

    /// Captures queue-owned segment identity before receive. PERF-CORE-004
    /// compares this value through output submission.
    pub fn queuedSegmentIdentity(
        self: *const InputQueue,
        record_index: usize,
        segment_index: usize,
    ) InputError!SegmentIdentity {
        if (record_index >= self.queued) return error.Bounds;
        const record = self.records[record_index];
        const segment_count = @as(usize, record.split_count) + 1;
        if (segment_index >= segment_count) return error.Bounds;
        const start = if (segment_index == 0)
            0
        else
            record.split_storage[segment_index - 1];
        const end = if (segment_index < record.split_count)
            record.split_storage[segment_index]
        else
            record.payload.len;
        const segment = record.payload[start..end];
        return .{ .address = @intFromPtr(segment.ptr), .len = segment.len };
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
        const injected_failure: ?usize = switch (action) {
            .descriptor_failure => |failure| failure.at,
            else => null,
        };
        const action_limit = switch (action) {
            .ready => |count| @min(count, requested),
            .idle => return 0,
            .fail => return error.InputFailure,
            .descriptor_failure => |failure| @min(failure.ready, requested),
        };
        const available = self.queued - self.next_receive;
        const count = @min(action_limit, available);
        const next_receive = std.math.add(usize, self.next_receive, count) catch
            return error.DescriptorFailure;
        const next_sequence = std.math.add(u64, self.receive_sequence, count) catch
            return error.DescriptorFailure;

        var prepared_slots: [packet.max_batch]packet.PacketSlot = undefined;
        for (0..count) |output_index| {
            const record = &self.records[self.next_receive + output_index];
            if (injected_failure == output_index) return error.DescriptorFailure;
            if ((record.token.state() catch return error.TokenFailure) != .input_owned)
                return error.TokenFailure;

            var descriptors: [packet.max_segments]packet.SegmentDescriptor = undefined;
            var start: usize = 0;
            for (record.split_storage[0..record.split_count], 0..) |end, segment_index| {
                descriptors[segment_index] = .fromBytes(record.payload[start..end]);
                start = end;
            }
            descriptors[record.split_count] = .fromBytes(record.payload[start..]);
            const descriptor_count: usize = @as(usize, record.split_count) + 1;
            const sequence = std.math.add(u64, self.receive_sequence, output_index) catch
                return error.DescriptorFailure;
            prepared_slots[output_index] = packet.PacketSlot.init(
                record.token,
                descriptors[0..descriptor_count],
                record.payload.len,
                sequence,
                .{ .timestamp_ns = self.clock.now().nanoseconds },
                &self.packet_path,
            ) catch return error.DescriptorFailure;
        }

        // INVARIANT(INV-PKT-001): every fallible descriptor, state, and
        // arithmetic check finished above. This single-worker transition loop
        // therefore cannot fail after an earlier token changes ownership.
        for (prepared_slots[0..count]) |slot|
            slot.adapterToken().receive() catch unreachable;
        @memcpy(slots[0..count], prepared_slots[0..count]);
        self.next_receive = next_receive;
        self.receive_sequence = next_sequence;
        self.packet_path.recordReceive();
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
        var counters = self.copies;
        counters.packet_path_bytes = self.packet_path.abstraction_payload_copy_bytes;
        counters.explicit_read_bytes = self.packet_path.explicit_read_bytes;
        counters.segment_borrows = self.packet_path.segment_borrows;
        counters.receive_calls = self.packet_path.receive_calls;
        counters.submit_calls = self.packet_path.submit_calls;
        return counters;
    }

    /// Returns the queue's packet-path instrumentation snapshot.
    pub fn packetPathSnapshot(self: *const InputQueue) packet.PacketPathSnapshot {
        return self.packet_path.snapshot();
    }

    /// Exercises the sole instrumented abstraction-copy path for negative
    /// controls. Ordinary receive/output traversal does not call this method.
    pub fn copyPayloadForNegativeControl(
        self: *InputQueue,
        destination: []u8,
        source: []const u8,
    ) error{DestinationTooSmall}!void {
        try self.packet_path.copyPayload(destination, source);
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
        if (slot.instrumentation) |instrumentation|
            instrumentation.recordSubmit();
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
        for (0..slot.segmentCount()) |index| {
            observation.segments[index] = slot.adapterSegment(index) catch return error.Bounds;
            if (slot.instrumentation) |instrumentation|
                instrumentation.recordSegmentBorrow();
        }
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

    /// Returns one output-borrowed segment for identity evidence.
    pub fn borrowedSegment(self: *const OutputQueue, index: usize, segment_index: usize) SubmitError![]const u8 {
        if (index >= self.count) return error.Bounds;
        const observation = self.observations[index];
        if (segment_index >= observation.segment_count) return error.Bounds;
        return observation.segments[segment_index];
    }

    /// Returns output-borrowed segment identity without exposing mutable
    /// adapter storage.
    pub fn borrowedSegmentIdentity(
        self: *const OutputQueue,
        index: usize,
        segment_index: usize,
    ) SubmitError!SegmentIdentity {
        const segment = try self.borrowedSegment(index, segment_index);
        return .{ .address = @intFromPtr(segment.ptr), .len = segment.len };
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
    const batch_owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer batch_owner.deinit();
    const received_batch = try batch_owner.begin(.{ .input_id = .init(1), .queue_id = .init(2) }, slots[0..3]);
    try std.testing.expectEqual(@as(u64, 10), (try (try received_batch.view(batch_owner, 0)).metadata(batch_owner)).timestamp_ns.?);
    try received_batch.invalidate(batch_owner);

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
    try std.testing.expectEqual(@as(usize, 0), input.copyCounters().packet_path_bytes);
}

test "INV-PKT-001 synthetic receive failures are transactional and queue outcomes match the reference states" {
    var input = try InputQueue.init(std.testing.allocator, .{
        .capacity = 2,
        .max_packet_length = 4,
    }, 0);
    defer input.deinit();
    try input.enqueue(&.{ 1, 2 }, &.{1});
    try input.enqueue(&.{ 3, 4 }, &.{1});

    var sentinel_tracker = try packet.TokenTracker.init(std.testing.allocator, 1);
    defer sentinel_tracker.deinit();
    const sentinel_token = try sentinel_tracker.registerInput();
    const sentinel_bytes = [_]u8{9};
    const sentinel_descriptors = [_]packet.SegmentDescriptor{
        packet.SegmentDescriptor.fromBytes(&sentinel_bytes),
    };
    const sentinel_slot = try packet.PacketSlot.init(
        sentinel_token,
        &sentinel_descriptors,
        1,
        777,
        .{},
        null,
    );
    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    slots[0] = sentinel_slot;
    slots[1] = sentinel_slot;
    slots[1].receive_order = 778;
    try input.setScript(&.{.{ .descriptor_failure = .{ .ready = 2, .at = 1 } }});
    try std.testing.expectError(error.DescriptorFailure, input.receive(&slots, 2));
    try std.testing.expectEqual(@as(usize, 0), input.next_receive);
    try std.testing.expectEqual(@as(u64, 0), input.receive_sequence);
    try std.testing.expectEqual(@as(usize, 0), input.tracker.receivedCount());
    try std.testing.expectEqual(@as(usize, 0), input.tracker.completionCount());
    try std.testing.expectEqual(packet.TokenState.input_owned, try input.records[0].token.state());
    try std.testing.expectEqual(packet.TokenState.input_owned, try input.records[1].token.state());
    try std.testing.expectEqual(@as(u64, 777), slots[0].receive_order);
    try std.testing.expectEqual(@as(u64, 778), slots[1].receive_order);
    try std.testing.expectEqual(
        @intFromPtr(sentinel_bytes[0..].ptr),
        @intFromPtr((try slots[0].adapterSegment(0)).ptr),
    );
    try input.verifyCompleted();

    input.receive_sequence = std.math.maxInt(u64);
    try input.setScript(&.{.{ .ready = 1 }});
    try std.testing.expectError(error.DescriptorFailure, input.receive(&slots, 1));
    try std.testing.expectEqual(@as(usize, 0), input.next_receive);
    try std.testing.expectEqual(@as(usize, 0), input.tracker.receivedCount());
    try std.testing.expectEqual(packet.TokenState.input_owned, try input.records[0].token.state());
    try std.testing.expectEqual(@as(u64, 777), slots[0].receive_order);
    input.receive_sequence = 0;

    try input.setScript(&.{.{ .ready = 2 }});
    try std.testing.expectEqual(@as(usize, 2), try input.receive(&slots, 2));
    try std.testing.expectEqual(@as(usize, 2), input.next_receive);
    try std.testing.expectEqual(@as(u64, 2), input.receive_sequence);
    try std.testing.expectEqual(@as(usize, 2), input.tracker.receivedCount());
    try std.testing.expectEqual(@as(usize, 0), input.tracker.completionCount());
    for (slots[0..2]) |slot|
        try std.testing.expectEqual(packet.TokenState.worker_owned, try slot.adapterToken().state());
    try std.testing.expectError(error.MissingCompletion, input.verifyCompleted());

    var output = try OutputQueue.init(std.testing.allocator, 2);
    defer output.deinit();
    try output.setScript(&.{ .backpressure, .fail, .accept_delayed, .accept_immediate });
    try std.testing.expectError(error.Backpressure, output.submit(&slots[0]));
    try std.testing.expectEqual(packet.TokenState.worker_owned, try slots[0].adapterToken().state());
    try std.testing.expectEqual(@as(usize, 0), input.tracker.completionCount());
    try std.testing.expectError(error.OutputFailure, output.submit(&slots[0]));
    try std.testing.expectEqual(packet.TokenState.worker_owned, try slots[0].adapterToken().state());
    try output.submit(&slots[0]);
    try std.testing.expectEqual(packet.TokenState.output_owned, try slots[0].adapterToken().state());
    try std.testing.expectError(error.MissingCompletion, input.verifyCompleted());
    try output.complete(0);
    try std.testing.expectEqual(packet.TokenState.completed, try slots[0].adapterToken().state());
    try std.testing.expectEqual(@as(usize, 1), input.tracker.completionCount());
    try std.testing.expectError(error.TokenFailure, output.complete(0));
    try output.submit(&slots[1]);
    try std.testing.expectEqual(packet.TokenState.completed, try slots[1].adapterToken().state());
    try std.testing.expectEqual(input.tracker.receivedCount(), input.tracker.completionCount());
    try input.verifyCompleted();
}

const QueueModelAction = enum {
    submit_backpressure,
    submit_failure,
    submit_delayed,
    submit_immediate,
    complete,
    return_input,
};

const QueueModelOutcome = enum {
    ok,
    backpressure,
    output_failure,
    bounds,
    invalid_transition,
    already_completed,
};

const QueueReference = struct {
    state: packet.TokenState = .worker_owned,
    received: usize = 1,
    completions: usize = 0,
    accepted: usize = 0,
    pending: bool = false,

    fn apply(self: *QueueReference, action: QueueModelAction) QueueModelOutcome {
        return switch (action) {
            .submit_backpressure => .backpressure,
            .submit_failure => .output_failure,
            .submit_delayed, .submit_immediate => blk: {
                if (self.state == .completed or self.state == .returned_to_input)
                    break :blk .invalid_transition;
                if (self.state != .worker_owned) break :blk .invalid_transition;
                self.accepted += 1;
                if (action == .submit_delayed) {
                    self.state = .output_owned;
                    self.pending = true;
                } else {
                    self.state = .completed;
                    self.completions += 1;
                }
                break :blk .ok;
            },
            .complete => blk: {
                if (self.accepted == 0) break :blk .bounds;
                if (!self.pending) break :blk .invalid_transition;
                self.pending = false;
                self.state = .completed;
                self.completions += 1;
                break :blk .ok;
            },
            .return_input => blk: {
                if (self.state == .completed or self.state == .returned_to_input)
                    break :blk .already_completed;
                if (self.state != .worker_owned) break :blk .invalid_transition;
                self.state = .returned_to_input;
                self.completions += 1;
                break :blk .ok;
            },
        };
    }

    fn shutdownComplete(self: QueueReference) bool {
        return self.received == self.completions and
            (self.state == .completed or self.state == .returned_to_input);
    }
};

fn classifySubmitError(result: SubmitError!void) QueueModelOutcome {
    result catch |submit_error| return switch (submit_error) {
        error.Backpressure => .backpressure,
        error.OutputFailure => .output_failure,
        error.Bounds => .bounds,
        error.TokenFailure => .invalid_transition,
        error.ScriptTooLong => unreachable,
    };
    return .ok;
}

fn classifyTokenError(result: packet.TokenError!void) QueueModelOutcome {
    result catch |token_error| return switch (token_error) {
        error.InvalidTransition => .invalid_transition,
        error.AlreadyCompleted => .already_completed,
        error.InvalidToken, error.OutOfCapacity, error.MissingCompletion => unreachable,
    };
    return .ok;
}

fn applyRealQueueAction(
    output: *OutputQueue,
    slot: *const packet.PacketSlot,
    action: QueueModelAction,
) QueueModelOutcome {
    return switch (action) {
        .submit_backpressure => blk: {
            output.setScript(&.{.backpressure}) catch unreachable;
            break :blk classifySubmitError(output.submit(slot));
        },
        .submit_failure => blk: {
            output.setScript(&.{.fail}) catch unreachable;
            break :blk classifySubmitError(output.submit(slot));
        },
        .submit_delayed => blk: {
            output.setScript(&.{.accept_delayed}) catch unreachable;
            break :blk classifySubmitError(output.submit(slot));
        },
        .submit_immediate => blk: {
            output.setScript(&.{.accept_immediate}) catch unreachable;
            break :blk classifySubmitError(output.submit(slot));
        },
        .complete => classifySubmitError(output.complete(0)),
        .return_input => classifyTokenError(slot.adapterToken().returnToInput()),
    };
}

test "INV-PKT-001 independent queue model exhausts backpressure failure delayed completion and shutdown sequences" {
    const actions = std.enums.values(QueueModelAction);
    const sequence_length = 4;
    const sequence_count = std.math.pow(usize, actions.len, sequence_length);
    for (0..sequence_count) |encoded| {
        var input = try InputQueue.init(std.testing.allocator, .{
            .capacity = 1,
            .max_packet_length = 1,
        }, 0);
        defer input.deinit();
        try input.enqueue(&.{1}, &.{});
        var slots: [1]packet.PacketSlot = undefined;
        try std.testing.expectEqual(@as(usize, 1), try input.receive(&slots, 1));
        var output = try OutputQueue.init(std.testing.allocator, 2);
        defer output.deinit();

        var reference = QueueReference{};
        var remaining_code = encoded;
        for (0..sequence_length) |_| {
            const action = actions[remaining_code % actions.len];
            remaining_code /= actions.len;
            const expected = reference.apply(action);
            try std.testing.expectEqual(
                expected,
                applyRealQueueAction(&output, &slots[0], action),
            );
            try std.testing.expectEqual(reference.state, try slots[0].adapterToken().state());
            try std.testing.expectEqual(reference.received, input.tracker.receivedCount());
            try std.testing.expectEqual(reference.completions, input.tracker.completionCount());
            try std.testing.expectEqual(reference.accepted, output.acceptedCount());
            if (reference.accepted != 0)
                try std.testing.expectEqual(reference.pending, output.observations[0].pending);
            if (reference.shutdownComplete()) {
                try input.verifyCompleted();
            } else {
                try std.testing.expectError(error.MissingCompletion, input.verifyCompleted());
            }
        }
    }
}

test "FR-PKT-004 receive accepts requested batch sizes zero through 64 and rejects 65" {
    var input = try InputQueue.init(std.testing.allocator, .{
        .capacity = 0,
        .max_packet_length = 0,
        .zero_length = .allow,
    }, 0);
    defer input.deinit();
    var slots: [packet.max_batch + 1]packet.PacketSlot = undefined;
    for (0..packet.max_batch + 1) |requested|
        try std.testing.expectEqual(@as(usize, 0), try input.receive(&slots, requested));
    try std.testing.expectError(
        error.InvalidReceiveRequest,
        input.receive(&slots, packet.max_batch + 1),
    );
}

test "FR-TEST-002 INV-PKT-001 PERF-CORE-004 linear and segmented packet sizes traverse unchanged with borrowed identity and no packet-path allocation or payload copy" {
    const configured_max: usize = 256;
    const traversal_count = (configured_max + 1) * 2;
    const max_fixture_segments = 6;
    var counting_allocator = CountingAllocator.init(std.testing.allocator);
    const observed_allocator = counting_allocator.allocator();
    var input = try InputQueue.init(observed_allocator, .{
        .capacity = (configured_max + 1) * 2,
        .max_packet_length = configured_max,
        .zero_length = .allow,
    }, 0);
    defer input.deinit();
    var expected: [configured_max]u8 = undefined;
    for (&expected, 0..) |*byte, index| byte.* = @truncate(index *% 37);
    for (0..configured_max + 1) |size| {
        try input.enqueue(expected[0..size], &.{});
        try input.enqueue(
            expected[0..size],
            &.{ 0, size / 3, size / 3, (size * 2) / 3, size },
        );
    }

    var pre_receive_identities: [traversal_count][max_fixture_segments]SegmentIdentity = undefined;
    var pre_receive_segment_counts: [traversal_count]usize = undefined;
    for (0..traversal_count) |record_index| {
        const segment_count = try input.queuedSegmentCount(record_index);
        pre_receive_segment_counts[record_index] = segment_count;
        for (0..segment_count) |segment_index|
            pre_receive_identities[record_index][segment_index] =
                try input.queuedSegmentIdentity(record_index, segment_index);
    }

    var output = try OutputQueue.init(observed_allocator, traversal_count);
    defer output.deinit();
    const allocator_before = counting_allocator.snapshot();
    const packet_path_before = input.packetPathSnapshot();
    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    var accepted: usize = 0;
    while (accepted < traversal_count) {
        const count = try input.receive(&slots, packet.max_batch);
        try std.testing.expect(count > 0);
        for (slots[0..count]) |*slot| {
            try output.submit(slot);
            const size = accepted / 2;
            try std.testing.expect(try output.matches(accepted, expected[0..size]));
            try std.testing.expectEqual(
                pre_receive_segment_counts[accepted],
                slot.segmentCount(),
            );
            for (0..pre_receive_segment_counts[accepted]) |segment_index| {
                try std.testing.expectEqual(
                    pre_receive_identities[accepted][segment_index],
                    try output.borrowedSegmentIdentity(accepted, segment_index),
                );
            }
            accepted += 1;
        }
    }
    try input.verifyCompleted();
    try verifyPacketPathGuard(
        packet_path_before,
        input.packetPathSnapshot(),
        allocator_before,
        counting_allocator.snapshot(),
    );
    const counters = input.copyCounters();
    try std.testing.expectEqual(@as(usize, 0), counters.packet_path_bytes);
    try std.testing.expectEqual(@as(usize, 0), counters.explicit_read_bytes);
    try std.testing.expectEqual(@as(usize, 9), counters.receive_calls);
    try std.testing.expectEqual(traversal_count, counters.submit_calls);
    try std.testing.expect(counters.segment_borrows >= traversal_count);

    var rejecting = try InputQueue.init(std.testing.allocator, .{
        .capacity = 1,
        .max_packet_length = 1,
        .zero_length = .reject,
    }, 0);
    defer rejecting.deinit();
    try std.testing.expectError(error.ZeroLengthForbidden, rejecting.enqueue(&.{}, &.{}));
}

test "PERF-CORE-004 allocation and abstraction-copy negative controls trip the packet-path guard" {
    var counting_allocator = CountingAllocator.init(std.testing.allocator);
    const observed_allocator = counting_allocator.allocator();
    var input = try InputQueue.init(observed_allocator, .{
        .capacity = 0,
        .max_packet_length = 0,
        .zero_length = .allow,
    }, 0);
    defer input.deinit();

    const clean_path = input.packetPathSnapshot();
    const clean_allocator = counting_allocator.snapshot();
    try verifyPacketPathGuard(
        clean_path,
        input.packetPathSnapshot(),
        clean_allocator,
        counting_allocator.snapshot(),
    );

    const unexpected = try observed_allocator.alloc(u8, 1);
    defer observed_allocator.free(unexpected);
    try std.testing.expectError(
        error.GeneralAllocationObserved,
        verifyPacketPathGuard(
            clean_path,
            input.packetPathSnapshot(),
            clean_allocator,
            counting_allocator.snapshot(),
        ),
    );

    const allocation_after = counting_allocator.snapshot();
    var destination: [1]u8 = undefined;
    try input.copyPayloadForNegativeControl(&destination, &.{0xa5});
    try std.testing.expectEqual(@as(u8, 0xa5), destination[0]);
    try std.testing.expectError(
        error.PayloadCopyObserved,
        verifyPacketPathGuard(
            clean_path,
            input.packetPathSnapshot(),
            allocation_after,
            counting_allocator.snapshot(),
        ),
    );
}

test "FR-PKT-002 every possible segment split preserves packet bytes and receive order" {
    const bytes = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    var input = try InputQueue.init(std.testing.allocator, .{ .capacity = bytes.len + 1, .max_packet_length = bytes.len }, 0);
    defer input.deinit();
    for (0..bytes.len + 1) |split| try input.enqueue(&bytes, &.{split});

    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    const count = try input.receive(&slots, packet.max_batch);
    try std.testing.expectEqual(bytes.len + 1, count);
    const batch_owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer batch_owner.deinit();
    const batch = try batch_owner.begin(.{ .input_id = .init(4), .queue_id = .init(9) }, slots[0..count]);
    for (0..count) |index| {
        var actual: [bytes.len]u8 = undefined;
        try (try batch.view(batch_owner, index)).read(batch_owner, .{ .offset = 0, .len = bytes.len }, &actual);
        try std.testing.expectEqualSlices(u8, &bytes, &actual);
    }
    try batch.invalidate(batch_owner);
    for (slots[0..count]) |slot| try slot.adapterToken().returnToInput();
    try input.verifyCompleted();
    try std.testing.expectEqual(
        bytes.len * count,
        input.copyCounters().explicit_read_bytes,
    );
}
