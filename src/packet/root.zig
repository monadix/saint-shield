// SPDX-License-Identifier: Apache-2.0
//! Backend-neutral packet storage ownership, segmented read-only views, input
//! origin, and receive-order contracts. Adapter tokens are single-worker-owned
//! and every transition is checked; packet views borrow an address-stable batch
//! and become stale when that batch is invalidated.

const std = @import("std");
const foundation = @import("../foundation/root.zig");

const InputTag = enum { input };
const QueueTag = enum { queue };
const OutputTag = enum { output };
const GenerationTag = enum { generation };
const MetadataTag = enum { adapter_metadata };

/// Stable application input identity.
pub const InputId = foundation.StableId(InputTag);
/// Stable input-queue identity within an adapter configuration.
pub const QueueId = foundation.StableId(QueueTag);
/// Stable application output identity.
pub const OutputId = foundation.StableId(OutputTag);
/// Stable generation identity used by later batch contracts.
pub const GenerationId = foundation.StableId(GenerationTag);
/// Optional stable identity for adapter-specific metadata schemas.
pub const AdapterMetadataId = foundation.StableId(MetadataTag);

/// Identifies the one configured input queue that formed a batch.
pub const InputOrigin = struct {
    input_id: InputId,
    queue_id: QueueId,
    adapter_metadata_id: ?AdapterMetadataId = null,
};

/// Maximum packet segments accepted by the M1 backend-neutral slot.
pub const max_segments: usize = 16;
/// Initial fixed upper bound used by all M1 batch storage.
pub const max_batch: usize = 64;

/// Numeric identity allocated by one adapter token tracker.
pub const TokenId = enum(u32) { _ };

/// Exact ownership state of a registered adapter token.
pub const TokenState = enum(u8) {
    input_owned,
    worker_owned,
    output_owned,
    retained,
    returned_to_input,
    completed,
};

const TokenAction = enum {
    receive,
    submit_output,
    return_input,
    retain,
    complete_output,
    complete_retained,
};

/// Token transition and shutdown-accounting errors.
pub const TokenError = error{
    OutOfCapacity,
    InvalidToken,
    InvalidTransition,
    AlreadyCompleted,
    MissingCompletion,
};

fn transitioned(state: TokenState, action: TokenAction) TokenError!TokenState {
    if (state == .completed or state == .returned_to_input)
        return error.AlreadyCompleted;
    return switch (action) {
        .receive => if (state == .input_owned) .worker_owned else error.InvalidTransition,
        .submit_output => if (state == .worker_owned) .output_owned else error.InvalidTransition,
        .return_input => if (state == .worker_owned) .returned_to_input else error.InvalidTransition,
        .retain => if (state == .worker_owned) .retained else error.InvalidTransition,
        .complete_output => if (state == .output_owned) .completed else error.InvalidTransition,
        .complete_retained => if (state == .retained) .completed else error.InvalidTransition,
    };
}

/// Single-adapter token registry with exact state and completion accounting.
///
/// Context: one adapter/worker owner. Complexity: transitions O(1), shutdown
/// verification O(capacity). Allocation: one state array at initialization.
/// Blocking: never. `deinit` releases registry memory but callers must first
/// obtain a successful `verifyReceivedCompleted` result.
pub const TokenTracker = struct {
    allocator: std.mem.Allocator,
    states: []TokenState,
    registered: usize = 0,
    received: usize = 0,
    final_completions: usize = 0,

    /// Allocates a tracker for at most `capacity` adapter tokens.
    pub fn init(allocator: std.mem.Allocator, capacity: usize) std.mem.Allocator.Error!TokenTracker {
        return .{
            .allocator = allocator,
            .states = try allocator.alloc(TokenState, capacity),
        };
    }

    /// Releases tracker storage. It does not waive outstanding obligations.
    pub fn deinit(self: *TokenTracker) void {
        self.allocator.free(self.states);
        self.* = undefined;
    }

    /// Registers a token currently owned by the input adapter.
    pub fn registerInput(self: *TokenTracker) TokenError!AdapterToken {
        if (self.registered == self.states.len) return error.OutOfCapacity;
        const raw = std.math.cast(u32, self.registered) orelse
            return error.OutOfCapacity;
        self.states[self.registered] = .input_owned;
        self.registered += 1;
        return .{ .tracker = self, .id = @enumFromInt(raw) };
    }

    fn statePointer(self: *TokenTracker, id: TokenId) TokenError!*TokenState {
        const index: usize = @intFromEnum(id);
        if (index >= self.registered) return error.InvalidToken;
        return &self.states[index];
    }

    fn apply(self: *TokenTracker, id: TokenId, action: TokenAction) TokenError!void {
        const state_ptr = try self.statePointer(id);
        const next = try transitioned(state_ptr.*, action);
        state_ptr.* = next;
        if (action == .receive) self.received += 1;
        if (next == .completed or next == .returned_to_input)
            self.final_completions += 1;
    }

    /// Returns the current state after validating token provenance.
    pub fn state(self: *TokenTracker, id: TokenId) TokenError!TokenState {
        return (try self.statePointer(id)).*;
    }

    /// Verifies every received token has exactly one final outcome.
    pub fn verifyReceivedCompleted(self: *const TokenTracker) TokenError!void {
        for (self.states[0..self.registered]) |token_state| switch (token_state) {
            .worker_owned, .output_owned, .retained => return error.MissingCompletion,
            .input_owned, .returned_to_input, .completed => {},
        };
        if (self.final_completions != self.received) return error.MissingCompletion;
    }

    /// Number of receive transitions observed by this tracker.
    pub fn receivedCount(self: *const TokenTracker) usize {
        return self.received;
    }

    /// Number of exact final completion transitions observed by this tracker.
    pub fn completionCount(self: *const TokenTracker) usize {
        return self.final_completions;
    }
};

/// Adapter token handle tied to exactly one live `TokenTracker`.
/// Ordinary processors do not receive this handle directly.
pub const AdapterToken = struct {
    tracker: *TokenTracker,
    id: TokenId,

    /// Transfers an input-owned token into one worker.
    pub fn receive(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .receive);
    }

    /// Transfers a worker-owned token to an output queue.
    pub fn submitOutput(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .submit_output);
    }

    /// Completes a worker-owned token by returning it to input/pool ownership.
    pub fn returnToInput(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .return_input);
    }

    /// Transfers a worker-owned token into an explicit retention obligation.
    pub fn retain(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .retain);
    }

    /// Completes a token previously accepted by an output.
    pub fn completeOutput(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .complete_output);
    }

    /// Completes a token held by an explicit retention obligation.
    pub fn completeRetention(self: AdapterToken) TokenError!void {
        try self.tracker.apply(self.id, .complete_retained);
    }

    /// Returns the exact current ownership state.
    pub fn state(self: AdapterToken) TokenError!TokenState {
        return self.tracker.state(self.id);
    }
};

/// Untrusted adapter segment descriptor. `declared_len` must not exceed
/// `bytes.len`; the separation permits malformed-descriptor injection tests.
pub const SegmentDescriptor = struct {
    bytes: []const u8,
    declared_len: usize,

    /// Describes an entire backing slice.
    pub fn fromBytes(bytes: []const u8) SegmentDescriptor {
        return .{ .bytes = bytes, .declared_len = bytes.len };
    }
};

/// Optional bounded packet metadata normalized by an adapter.
pub const PacketMetadata = struct {
    timestamp_ns: ?u64 = null,
    flags: u32 = 0,
};

/// Descriptor and slot construction errors.
pub const SlotError = error{
    TooManySegments,
    DescriptorOverflow,
    MalformedDescriptor,
};

/// One receive-order slot borrowing adapter-owned payload segments.
///
/// The adapter token remains worker-owned while views exist. Segment bytes are
/// never copied during construction. The backing storage and tracker must
/// outlive every batch containing this slot.
pub const PacketSlot = struct {
    token: AdapterToken,
    segment_storage: [max_segments]SegmentDescriptor = undefined,
    segment_count: u8,
    total_len: usize,
    receive_order: u64,
    metadata_value: PacketMetadata,

    /// Validates a segment descriptor and constructs a non-owning packet slot.
    pub fn init(
        token: AdapterToken,
        descriptors: []const SegmentDescriptor,
        declared_total: usize,
        receive_order: u64,
        metadata: PacketMetadata,
    ) SlotError!PacketSlot {
        if (descriptors.len > max_segments) return error.TooManySegments;

        var total: usize = 0;
        for (descriptors) |descriptor| {
            total = std.math.add(usize, total, descriptor.declared_len) catch
                return error.DescriptorOverflow;
        }
        for (descriptors) |descriptor| {
            if (descriptor.declared_len > descriptor.bytes.len)
                return error.MalformedDescriptor;
        }
        if (total != declared_total) return error.MalformedDescriptor;

        var slot = PacketSlot{
            .token = token,
            .segment_count = @intCast(descriptors.len),
            .total_len = total,
            .receive_order = receive_order,
            .metadata_value = metadata,
        };
        @memcpy(slot.segment_storage[0..descriptors.len], descriptors);
        return slot;
    }

    /// Returns total packet bytes described by all validated segments.
    pub fn length(self: *const PacketSlot) usize {
        return self.total_len;
    }

    /// Returns the adapter token for runtime completion code.
    pub fn adapterToken(self: *const PacketSlot) AdapterToken {
        return self.token;
    }

    /// Returns one validated segment for adapter/output traversal.
    pub fn adapterSegment(self: *const PacketSlot, index: usize) error{Bounds}![]const u8 {
        if (index >= self.segment_count) return error.Bounds;
        const segment = self.segment_storage[index];
        return segment.bytes[0..segment.declared_len];
    }

    /// Returns the number of validated payload segments.
    pub fn segmentCount(self: *const PacketSlot) usize {
        return self.segment_count;
    }
};

/// Checked packet byte range.
pub const ByteRange = struct {
    offset: usize,
    len: usize,

    /// Returns the exclusive end or `Overflow` without wrapping.
    pub fn end(self: ByteRange) error{Overflow}!usize {
        return std.math.add(usize, self.offset, self.len) catch error.Overflow;
    }
};

/// Segment-aware packet read errors.
pub const ViewError = error{
    Bounds,
    Overflow,
    DestinationTooSmall,
    StaleView,
};

/// Read-only borrow of one packet slot for one live batch call.
///
/// Context: packet worker. Complexity: O(segments), bounded by 16. Allocation:
/// none. Blocking: never. `read` copies only because the caller explicitly
/// requests a cross-segment destination; `contiguous` is the zero-copy path.
pub const PacketView = struct {
    slot: *const PacketSlot,
    cookie_source: *const u64,
    expected_cookie: u64,

    fn ensureLive(self: PacketView) ViewError!void {
        // INVARIANT(INV-PKT-002): invalidation changes the batch cookie before
        // caller-owned slot storage may be reused, so stale borrows fail.
        if (self.cookie_source.* != self.expected_cookie) return error.StaleView;
    }

    fn validateRange(self: PacketView, range: ByteRange) ViewError!usize {
        try self.ensureLive();
        const range_end = range.end() catch return error.Overflow;
        if (range_end > self.slot.total_len) return error.Bounds;
        return range_end;
    }

    /// Returns total packet length after validating the lifetime cookie.
    pub fn length(self: PacketView) ViewError!usize {
        try self.ensureLive();
        return self.slot.total_len;
    }

    /// Returns a zero-copy slice only when the whole range is one segment.
    pub fn contiguous(self: PacketView, range: ByteRange) ViewError!?[]const u8 {
        _ = try self.validateRange(range);
        if (range.len == 0) return &.{};

        var segment_start: usize = 0;
        for (self.slot.segment_storage[0..self.slot.segment_count]) |segment| {
            const segment_end = segment_start + segment.declared_len;
            if (range.offset >= segment_start and range.offset < segment_end) {
                const local = range.offset - segment_start;
                if (range.len <= segment.declared_len - local)
                    return segment.bytes[local .. local + range.len];
                return null;
            }
            segment_start = segment_end;
        }
        return null;
    }

    /// Copies a checked range into `destination[0..range.len]`.
    pub fn read(self: PacketView, range: ByteRange, destination: []u8) ViewError!void {
        _ = try self.validateRange(range);
        if (destination.len < range.len) return error.DestinationTooSmall;
        if (range.len == 0) return;

        var remaining = range.len;
        var source_offset = range.offset;
        var destination_offset: usize = 0;
        var segment_start: usize = 0;
        for (self.slot.segment_storage[0..self.slot.segment_count]) |segment| {
            const segment_end = segment_start + segment.declared_len;
            if (source_offset < segment_end and remaining != 0) {
                const local = if (source_offset > segment_start) source_offset - segment_start else 0;
                const amount = @min(remaining, segment.declared_len - local);
                @memcpy(destination[destination_offset .. destination_offset + amount], segment.bytes[local .. local + amount]);
                remaining -= amount;
                destination_offset += amount;
                source_offset += amount;
            }
            segment_start = segment_end;
        }
        std.debug.assert(remaining == 0);
    }

    /// Creates a bounded zero-copy iterator over the pieces intersecting a
    /// checked range. Each returned slice borrows the same live batch.
    pub fn segments(self: PacketView, range: ByteRange) ViewError!SegmentIterator {
        const range_end = try self.validateRange(range);
        return .{
            .view = self,
            .range_start = range.offset,
            .range_end = range_end,
        };
    }

    /// Returns normalized bounded adapter metadata.
    pub fn metadata(self: PacketView) ViewError!PacketMetadata {
        try self.ensureLive();
        return self.slot.metadata_value;
    }
};

/// Zero-copy iterator over at most `max_segments` checked packet pieces.
pub const SegmentIterator = struct {
    view: PacketView,
    range_start: usize,
    range_end: usize,
    segment_index: usize = 0,
    segment_start: usize = 0,

    /// Returns the next intersecting segment slice, or null at range end.
    pub fn next(self: *SegmentIterator) ViewError!?[]const u8 {
        try self.view.ensureLive();
        if (self.range_start == self.range_end) return null;
        while (self.segment_index < self.view.slot.segment_count) {
            const segment = self.view.slot.segment_storage[self.segment_index];
            const segment_end = self.segment_start + segment.declared_len;
            self.segment_index += 1;
            defer self.segment_start = segment_end;

            const overlap_start = @max(self.range_start, self.segment_start);
            const overlap_end = @min(self.range_end, segment_end);
            if (overlap_start < overlap_end) {
                const local_start = overlap_start - self.segment_start;
                return segment.bytes[local_start .. local_start + (overlap_end - overlap_start)];
            }
        }
        return null;
    }
};

/// Ordered batch of packet slots borrowed for one processing call.
/// Keep its address stable after creating a `PacketView`.
pub const PacketBatch = struct {
    origin: InputOrigin,
    slots: []PacketSlot,
    lifetime_cookie: u64,
    live: bool = true,

    /// Batch construction errors.
    pub const Error = error{ BatchTooLarge, ReceiveOrderViolation, BatchReleased, Bounds };

    /// Validates maximum size and strictly increasing adapter receive order.
    pub fn init(origin: InputOrigin, slots: []PacketSlot, lifetime_cookie: u64) Error!PacketBatch {
        if (slots.len > max_batch) return error.BatchTooLarge;
        if (lifetime_cookie == 0) return error.BatchReleased;
        for (slots, 0..) |slot, index| {
            if (index != 0 and slot.receive_order <= slots[index - 1].receive_order)
                return error.ReceiveOrderViolation;
        }
        return .{ .origin = origin, .slots = slots, .lifetime_cookie = lifetime_cookie };
    }

    /// Number of packets actually received; partial and empty batches are valid.
    pub fn len(self: *const PacketBatch) usize {
        return self.slots.len;
    }

    /// Creates a read-only view valid until `invalidate`.
    pub fn view(self: *const PacketBatch, index: usize) Error!PacketView {
        if (!self.live) return error.BatchReleased;
        if (index >= self.slots.len) return error.Bounds;
        return .{
            .slot = &self.slots[index],
            .cookie_source = &self.lifetime_cookie,
            .expected_cookie = self.lifetime_cookie,
        };
    }

    /// Ends the processing-call borrow and invalidates all outstanding views.
    pub fn invalidate(self: *PacketBatch) void {
        if (!self.live) return;
        self.live = false;
        self.lifetime_cookie +%= 1;
        if (self.lifetime_cookie == 0) self.lifetime_cookie = 1;
    }
};

fn allocationTrackerCase(allocator: std.mem.Allocator) !void {
    var tracker = try TokenTracker.init(allocator, 4);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "token tracker constructor cleans up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationTrackerCase, .{});
}

test "INV-PKT-001 adapter token transition table is exhaustive for every small state and action" {
    const states = std.enums.values(TokenState);
    const actions = std.enums.values(TokenAction);
    var valid: usize = 0;
    var rejected: usize = 0;
    for (states) |state| for (actions) |action| {
        if (transitioned(state, action)) |_| {
            valid += 1;
        } else |_| {
            rejected += 1;
        }
    };
    try std.testing.expectEqual(@as(usize, 6), valid);
    try std.testing.expectEqual(states.len * actions.len - 6, rejected);
}

test "FR-PKT-011 INV-PKT-001 exact token completion detects double and missing completion" {
    var tracker = try TokenTracker.init(std.testing.allocator, 3);
    defer tracker.deinit();

    const output = try tracker.registerInput();
    try output.receive();
    try output.submitOutput();
    try std.testing.expectError(error.MissingCompletion, tracker.verifyReceivedCompleted());
    try output.completeOutput();
    try std.testing.expectError(error.AlreadyCompleted, output.completeOutput());

    const returned = try tracker.registerInput();
    try returned.receive();
    try returned.returnToInput();
    try std.testing.expectError(error.AlreadyCompleted, returned.returnToInput());

    const retained = try tracker.registerInput();
    try retained.receive();
    try retained.retain();
    try std.testing.expectError(error.MissingCompletion, tracker.verifyReceivedCompleted());
    try retained.completeRetention();

    try tracker.verifyReceivedCompleted();
    try std.testing.expectEqual(tracker.receivedCount(), tracker.completionCount());
}

fn makeLiveSlot(tracker: *TokenTracker, segments: []const SegmentDescriptor, total: usize) !PacketSlot {
    const token = try tracker.registerInput();
    try token.receive();
    return PacketSlot.init(token, segments, total, 0, .{});
}

test "slot rejects malformed descriptors and checked arithmetic overflow" {
    var tracker = try TokenTracker.init(std.testing.allocator, 3);
    defer tracker.deinit();
    const token = try tracker.registerInput();

    const malformed = [_]SegmentDescriptor{.{ .bytes = &.{1}, .declared_len = 2 }};
    try std.testing.expectError(error.MalformedDescriptor, PacketSlot.init(token, &malformed, 2, 0, .{}));
    const mismatch = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&.{ 1, 2 })};
    try std.testing.expectError(error.MalformedDescriptor, PacketSlot.init(token, &mismatch, 1, 0, .{}));
    const overflow = [_]SegmentDescriptor{
        .{ .bytes = &.{}, .declared_len = std.math.maxInt(usize) },
        .{ .bytes = &.{}, .declared_len = 1 },
    };
    try std.testing.expectError(error.DescriptorOverflow, PacketSlot.init(token, &overflow, 0, 0, .{}));

    var too_many: [max_segments + 1]SegmentDescriptor = undefined;
    for (&too_many) |*segment| segment.* = SegmentDescriptor.fromBytes(&.{});
    try std.testing.expectError(error.TooManySegments, PacketSlot.init(token, &too_many, 0, 0, .{}));
}

test "FR-PKT-006 all ranges and every segment split read exactly" {
    const payload = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (0..payload.len + 1) |split| {
        var tracker = try TokenTracker.init(std.testing.allocator, 1);
        defer tracker.deinit();
        const segments = [_]SegmentDescriptor{
            SegmentDescriptor.fromBytes(payload[0..split]),
            SegmentDescriptor.fromBytes(payload[split..]),
        };
        const slot = try makeLiveSlot(&tracker, &segments, payload.len);
        var slots = [_]PacketSlot{slot};
        var batch = try PacketBatch.init(.{ .input_id = .init(1), .queue_id = .init(2) }, &slots, 99);
        defer {
            batch.invalidate();
            slots[0].token.returnToInput() catch unreachable;
            tracker.verifyReceivedCompleted() catch unreachable;
        }
        const view = try batch.view(0);
        for (0..payload.len + 1) |start| for (start..payload.len + 1) |end| {
            var actual: [payload.len]u8 = undefined;
            try view.read(.{ .offset = start, .len = end - start }, &actual);
            try std.testing.expectEqualSlices(u8, payload[start..end], actual[0 .. end - start]);
            if (try view.contiguous(.{ .offset = start, .len = end - start })) |contiguous| {
                try std.testing.expectEqualSlices(u8, payload[start..end], contiguous);
            }
            var iterator = try view.segments(.{ .offset = start, .len = end - start });
            var iterator_offset = start;
            while (try iterator.next()) |piece| {
                try std.testing.expectEqualSlices(u8, payload[iterator_offset .. iterator_offset + piece.len], piece);
                iterator_offset += piece.len;
            }
            try std.testing.expectEqual(end, iterator_offset);
        };
        var too_small: [1]u8 = undefined;
        try std.testing.expectError(error.DestinationTooSmall, view.read(.{ .offset = 0, .len = 2 }, &too_small));
        try std.testing.expectError(error.Bounds, view.read(.{ .offset = payload.len, .len = 1 }, &.{}));
        try std.testing.expectError(error.Overflow, view.read(.{ .offset = std.math.maxInt(usize), .len = 2 }, &.{}));
    }
}

test "FR-PKT-002 FR-PKT-003 FR-PKT-012 INV-PKT-002 batch origin order and stale lifetime cookie are enforced" {
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const bytes = [_]u8{1};
    const descriptor = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    var first = try makeLiveSlot(&tracker, &descriptor, 1);
    first.receive_order = 2;
    var second = try makeLiveSlot(&tracker, &descriptor, 1);
    second.receive_order = 1;
    var reversed = [_]PacketSlot{ first, second };
    try std.testing.expectError(error.ReceiveOrderViolation, PacketBatch.init(.{ .input_id = .init(1), .queue_id = .init(1) }, &reversed, 1));

    var ordered = [_]PacketSlot{ second, first };
    var batch = try PacketBatch.init(.{ .input_id = .init(1), .queue_id = .init(1) }, &ordered, 41);
    try std.testing.expectEqual(@as(u64, 1), batch.origin.input_id.raw());
    try std.testing.expectEqual(@as(u64, 1), batch.origin.queue_id.raw());
    const view = try batch.view(0);
    try std.testing.expectEqual(@as(usize, 1), try view.length());
    batch.invalidate();
    try std.testing.expectError(error.StaleView, view.length());
    try std.testing.expectError(error.BatchReleased, batch.view(0));

    try ordered[0].token.returnToInput();
    try ordered[1].token.returnToInput();
    try tracker.verifyReceivedCompleted();
}
