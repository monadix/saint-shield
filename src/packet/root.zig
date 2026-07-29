// SPDX-License-Identifier: Apache-2.0
//! Backend-neutral packet storage ownership, segmented read-only views, input
//! origin, and receive-order contracts. Adapter tokens are single-worker-owned
//! and every transition is checked; opaque packet handles use an address-stable
//! owner and become stale when their owner-controlled generation is invalidated.

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

/// Mechanically observable packet-path work used by PERF-CORE-004 evidence.
///
/// The counters are single-worker-owned, never allocate, and distinguish an
/// explicit caller-requested `PacketView.read` copy from an abstraction copy.
pub const PacketPathInstrumentation = struct {
    receive_calls: usize = 0,
    submit_calls: usize = 0,
    segment_borrows: usize = 0,
    explicit_read_bytes: usize = 0,
    abstraction_payload_copy_bytes: usize = 0,

    /// Records one allocation-free adapter receive operation.
    pub fn recordReceive(self: *PacketPathInstrumentation) void {
        self.receive_calls += 1;
    }

    /// Records one allocation-free output submission operation.
    pub fn recordSubmit(self: *PacketPathInstrumentation) void {
        self.submit_calls += 1;
    }

    /// Records one borrowed adapter segment without copying its payload.
    pub fn recordSegmentBorrow(self: *PacketPathInstrumentation) void {
        self.segment_borrows += 1;
    }

    /// Centralized abstraction-copy path. Ordinary receive, view traversal,
    /// and output submission never call this method.
    pub fn copyPayload(
        self: *PacketPathInstrumentation,
        destination: []u8,
        source: []const u8,
    ) error{DestinationTooSmall}!void {
        if (destination.len < source.len) return error.DestinationTooSmall;
        @memcpy(destination[0..source.len], source);
        self.abstraction_payload_copy_bytes += source.len;
    }

    /// Returns an immutable counter snapshot for before/after gate checks.
    pub fn snapshot(self: *const PacketPathInstrumentation) PacketPathSnapshot {
        return .{
            .receive_calls = self.receive_calls,
            .submit_calls = self.submit_calls,
            .segment_borrows = self.segment_borrows,
            .explicit_read_bytes = self.explicit_read_bytes,
            .abstraction_payload_copy_bytes = self.abstraction_payload_copy_bytes,
        };
    }
};

/// Immutable observation of all instrumented packet-path operations.
pub const PacketPathSnapshot = struct {
    receive_calls: usize,
    submit_calls: usize,
    segment_borrows: usize,
    explicit_read_bytes: usize,
    abstraction_payload_copy_bytes: usize,
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
    instrumentation: ?*PacketPathInstrumentation,

    /// Validates a segment descriptor and constructs a non-owning packet slot.
    pub fn init(
        token: AdapterToken,
        descriptors: []const SegmentDescriptor,
        declared_total: usize,
        receive_order: u64,
        metadata: PacketMetadata,
        instrumentation: ?*PacketPathInstrumentation,
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
            .instrumentation = instrumentation,
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

const HandleInt = u128;
const handle_component_bits = 64;
const view_index_bits = 8;
const max_generation = (@as(u64, 1) << (64 - view_index_bits)) - 1;

const BatchOwnerImpl = struct {
    allocator: std.mem.Allocator,
    owner_identity: u64,
    next_generation: u64 = 0,
    live_generation: u64 = 0,
    origin: InputOrigin = undefined,
    slots: [max_batch]PacketSlot = undefined,
    slot_count: usize = 0,
};

const OwnerIdentityError = error{OwnerIdentityExhausted};
var owner_identity_counter = std.atomic.Value(u64).init(0);

fn allocateOwnerIdentity(
    counter: *std.atomic.Value(u64),
) OwnerIdentityError!u64 {
    var current = counter.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64))
            return error.OwnerIdentityExhausted;
        const next = current + 1;
        if (counter.cmpxchgWeak(
            current,
            next,
            .monotonic,
            .monotonic,
        )) |observed| {
            current = observed;
            continue;
        }
        return next;
    }
}

fn ownerImpl(owner: *PacketBatchOwner) *BatchOwnerImpl {
    return @ptrCast(@alignCast(owner));
}

fn handleOwnerIdentity(raw: HandleInt) u64 {
    return @truncate(raw >> handle_component_bits);
}

fn handleLocalTag(raw: HandleInt) u64 {
    return @truncate(raw);
}

fn encodeHandle(owner_identity: u64, local_tag: u64) HandleInt {
    return (@as(HandleInt, owner_identity) << handle_component_bits) |
        @as(HandleInt, local_tag);
}

fn batchOwnerIdentity(batch: PacketBatch) u64 {
    return handleOwnerIdentity(@intFromEnum(batch));
}

fn batchGeneration(batch: PacketBatch) u64 {
    return handleLocalTag(@intFromEnum(batch));
}

fn viewOwnerIdentity(view: PacketView) u64 {
    return handleOwnerIdentity(@intFromEnum(view));
}

fn viewGeneration(view: PacketView) u64 {
    return handleLocalTag(@intFromEnum(view)) >> view_index_bits;
}

fn viewIndex(view: PacketView) usize {
    return @as(u8, @truncate(handleLocalTag(@intFromEnum(view))));
}

fn ensureViewLive(
    owner_handle: *PacketBatchOwner,
    view: PacketView,
) ViewError!*const PacketSlot {
    const owner = ownerImpl(owner_handle);
    const identity = viewOwnerIdentity(view);
    const generation = viewGeneration(view);
    const index = viewIndex(view);
    // INVARIANT(INV-PKT-002): validate the non-pointer owner identity and then
    // the owner-local generation/index before indexing owner-owned metadata.
    if (identity == 0 or owner.owner_identity != identity)
        return error.StaleView;
    if (generation == 0 or owner.live_generation != generation)
        return error.StaleView;
    if (index >= owner.slot_count) return error.StaleView;
    return &owner.slots[index];
}

fn validateViewRange(
    owner: *PacketBatchOwner,
    view: PacketView,
    range: ByteRange,
) ViewError!struct {
    slot: *const PacketSlot,
    range_end: usize,
} {
    const slot = try ensureViewLive(owner, view);
    const range_end = range.end() catch return error.Overflow;
    if (range_end > slot.total_len) return error.Bounds;
    return .{ .slot = slot, .range_end = range_end };
}

/// Address-stable allocation owning batch generations and copied slot metadata.
///
/// Construct once in adapter/worker setup, keep it alive across processing
/// calls, and destroy only after no handle will be accessed again. `begin`
/// allocates nothing and internally advances a generation that never resets.
/// Construction assigns a process-unique, monotonic non-pointer identity.
pub const PacketBatchOwner = opaque {
    /// Owner construction errors.
    pub const InitError = std.mem.Allocator.Error || OwnerIdentityError;

    /// Allocates one address-stable owner and a non-reusable identity.
    pub fn init(allocator: std.mem.Allocator) InitError!*PacketBatchOwner {
        const owner = try allocator.create(BatchOwnerImpl);
        errdefer allocator.destroy(owner);
        const identity = try allocateOwnerIdentity(&owner_identity_counter);
        owner.* = .{
            .allocator = allocator,
            .owner_identity = identity,
        };
        return @ptrCast(owner);
    }

    /// Releases owner metadata after all batch/view handles are unreachable.
    pub fn deinit(self: *PacketBatchOwner) void {
        const owner = ownerImpl(self);
        const allocator = owner.allocator;
        allocator.destroy(owner);
    }

    /// Starts one allocation-free generation and copies slot metadata only.
    pub fn begin(
        self: *PacketBatchOwner,
        input_origin: InputOrigin,
        slots: []const PacketSlot,
    ) PacketBatch.Error!PacketBatch {
        const owner = ownerImpl(self);
        if (owner.live_generation != 0) return error.BatchAlreadyLive;
        if (slots.len > max_batch) return error.BatchTooLarge;
        for (slots, 0..) |slot, index| {
            if (index != 0 and slot.receive_order <= slots[index - 1].receive_order)
                return error.ReceiveOrderViolation;
        }
        if (owner.next_generation == max_generation)
            return error.GenerationExhausted;

        owner.next_generation += 1;
        owner.live_generation = owner.next_generation;
        owner.origin = input_origin;
        owner.slot_count = slots.len;
        @memcpy(owner.slots[0..slots.len], slots);
        return @enumFromInt(encodeHandle(
            owner.owner_identity,
            owner.live_generation,
        ));
    }
};

/// Opaque ordered-batch handle for one owner-controlled processing generation.
///
/// The scalar contains only a non-pointer owner identity and bounded generation
/// tag. Every operation also requires the valid opaque owner whose private
/// state establishes provenance.
pub const PacketBatch = enum(HandleInt) {
    _,

    /// Batch construction and access errors.
    pub const Error = error{
        BatchTooLarge,
        ReceiveOrderViolation,
        BatchAlreadyLive,
        GenerationExhausted,
        BatchReleased,
        Bounds,
    };

    fn ensureLive(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
    ) Error!*BatchOwnerImpl {
        const owner = ownerImpl(owner_handle);
        const identity = batchOwnerIdentity(self);
        const generation = batchGeneration(self);
        if (identity == 0 or owner.owner_identity != identity)
            return error.BatchReleased;
        if (generation == 0 or owner.live_generation != generation)
            return error.BatchReleased;
        return owner;
    }

    /// Number of packets actually received; partial and empty batches are valid.
    pub fn len(self: PacketBatch, owner: *PacketBatchOwner) Error!usize {
        return (try self.ensureLive(owner)).slot_count;
    }

    /// Returns the configured input origin while this generation is live.
    pub fn origin(self: PacketBatch, owner: *PacketBatchOwner) Error!InputOrigin {
        return (try self.ensureLive(owner)).origin;
    }

    /// Creates an opaque read-only view valid until this generation ends.
    pub fn view(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) Error!PacketView {
        const owner = try self.ensureLive(owner_handle);
        if (index >= owner.slot_count) return error.Bounds;
        const tag = (batchGeneration(self) << view_index_bits) | @as(u8, @intCast(index));
        return @enumFromInt(encodeHandle(owner.owner_identity, tag));
    }

    /// Ends this generation for every copied batch, view, and iterator.
    pub fn invalidate(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
    ) Error!void {
        const owner = try self.ensureLive(owner_handle);
        owner.live_generation = 0;
    }
};

/// Opaque read-only packet handle for one owner-controlled generation.
///
/// The scalar contains only a non-pointer owner identity and bounded
/// generation/index tag. Every operation requires the valid opaque owner
/// separately.
pub const PacketView = enum(HandleInt) {
    _,

    /// Returns total packet length after validating owner liveness.
    pub fn length(self: PacketView, owner: *PacketBatchOwner) ViewError!usize {
        return (try ensureViewLive(owner, self)).total_len;
    }

    /// Returns a zero-copy slice only when the checked range is one segment.
    pub fn contiguous(
        self: PacketView,
        owner: *PacketBatchOwner,
        range: ByteRange,
    ) ViewError!?[]const u8 {
        const validated = try validateViewRange(owner, self, range);
        if (range.len == 0) return &.{};

        var segment_start: usize = 0;
        for (validated.slot.segment_storage[0..validated.slot.segment_count]) |segment| {
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
    pub fn read(
        self: PacketView,
        owner: *PacketBatchOwner,
        range: ByteRange,
        destination: []u8,
    ) ViewError!void {
        const validated = try validateViewRange(owner, self, range);
        if (destination.len < range.len) return error.DestinationTooSmall;
        if (range.len == 0) return;

        var remaining = range.len;
        var source_offset = range.offset;
        var destination_offset: usize = 0;
        var segment_start: usize = 0;
        for (validated.slot.segment_storage[0..validated.slot.segment_count]) |segment| {
            const segment_end = segment_start + segment.declared_len;
            if (source_offset < segment_end and remaining != 0) {
                const local = if (source_offset > segment_start) source_offset - segment_start else 0;
                const amount = @min(remaining, segment.declared_len - local);
                @memcpy(destination[destination_offset .. destination_offset + amount], segment.bytes[local .. local + amount]);
                if (validated.slot.instrumentation) |instrumentation|
                    instrumentation.explicit_read_bytes += amount;
                remaining -= amount;
                destination_offset += amount;
                source_offset += amount;
            }
            segment_start = segment_end;
        }
        std.debug.assert(remaining == 0);
    }

    /// Creates a bounded iterator over pieces intersecting a checked range.
    pub fn segments(
        self: PacketView,
        owner: *PacketBatchOwner,
        range: ByteRange,
    ) ViewError!SegmentIterator {
        const validated = try validateViewRange(owner, self, range);
        return .{
            .view_handle = self,
            .range_start = range.offset,
            .range_end = validated.range_end,
        };
    }

    /// Returns normalized bounded adapter metadata.
    pub fn metadata(self: PacketView, owner: *PacketBatchOwner) ViewError!PacketMetadata {
        return (try ensureViewLive(owner, self)).metadata_value;
    }
};

/// Iterator state containing only an opaque view handle and numeric progress.
pub const SegmentIterator = struct {
    view_handle: PacketView,
    range_start: usize,
    range_end: usize,
    segment_index: usize = 0,

    /// Returns the next intersecting segment slice, or null at range end.
    /// Every call revalidates all public numeric state against the owner and
    /// recomputes descriptor progress with checked arithmetic.
    pub fn next(
        self: *SegmentIterator,
        owner: *PacketBatchOwner,
    ) ViewError!?[]const u8 {
        const slot = try ensureViewLive(owner, self.view_handle);
        if (self.range_start > self.range_end or self.range_end > slot.total_len)
            return error.Bounds;
        if (self.segment_index > slot.segment_count) return error.Bounds;

        var segment_start: usize = 0;
        for (slot.segment_storage[0..self.segment_index]) |segment| {
            segment_start = std.math.add(
                usize,
                segment_start,
                segment.declared_len,
            ) catch return error.Overflow;
            if (segment_start > slot.total_len) return error.Bounds;
        }
        if (self.range_start == self.range_end) return null;
        while (self.segment_index < slot.segment_count) {
            const segment = slot.segment_storage[self.segment_index];
            const segment_end = std.math.add(
                usize,
                segment_start,
                segment.declared_len,
            ) catch return error.Overflow;
            if (segment_end > slot.total_len) return error.Bounds;
            self.segment_index = std.math.add(
                usize,
                self.segment_index,
                1,
            ) catch return error.Overflow;

            const overlap_start = @max(self.range_start, segment_start);
            const overlap_end = @min(self.range_end, segment_end);
            if (overlap_start < overlap_end) {
                const local_start = overlap_start - segment_start;
                const local_end = overlap_end - segment_start;
                return segment.bytes[local_start..local_end];
            }
            segment_start = segment_end;
        }
        return null;
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

fn allocationBatchOwnerCase(allocator: std.mem.Allocator) !void {
    const owner = try PacketBatchOwner.init(allocator);
    defer owner.deinit();
}

test "packet allocating constructors clean up at every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationTrackerCase, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationBatchOwnerCase, .{});
}

const ReferenceToken = struct {
    state: TokenState = .input_owned,
    received: usize = 0,
    completions: usize = 0,

    fn apply(self: *ReferenceToken, action: TokenAction) TokenError!void {
        if (self.state == .completed or self.state == .returned_to_input)
            return error.AlreadyCompleted;
        const next: TokenState = switch (action) {
            .receive => if (self.state == .input_owned) .worker_owned else return error.InvalidTransition,
            .submit_output => if (self.state == .worker_owned) .output_owned else return error.InvalidTransition,
            .return_input => if (self.state == .worker_owned) .returned_to_input else return error.InvalidTransition,
            .retain => if (self.state == .worker_owned) .retained else return error.InvalidTransition,
            .complete_output => if (self.state == .output_owned) .completed else return error.InvalidTransition,
            .complete_retained => if (self.state == .retained) .completed else return error.InvalidTransition,
        };
        self.state = next;
        if (action == .receive) self.received += 1;
        if (next == .completed or next == .returned_to_input)
            self.completions += 1;
    }

    fn verify(self: ReferenceToken) TokenError!void {
        switch (self.state) {
            .worker_owned, .output_owned, .retained => return error.MissingCompletion,
            .input_owned, .returned_to_input, .completed => {},
        }
        if (self.received != self.completions) return error.MissingCompletion;
    }
};

fn applyTokenAction(token: AdapterToken, action: TokenAction) TokenError!void {
    return switch (action) {
        .receive => token.receive(),
        .submit_output => token.submitOutput(),
        .return_input => token.returnToInput(),
        .retain => token.retain(),
        .complete_output => token.completeOutput(),
        .complete_retained => token.completeRetention(),
    };
}

test "INV-PKT-001 independent reference model exhausts bounded operation sequences through the real tracker" {
    const actions = std.enums.values(TokenAction);
    const sequence_length = 5;
    const sequence_count = std.math.pow(usize, actions.len, sequence_length);

    for (0..sequence_count) |encoded| {
        var tracker = try TokenTracker.init(std.testing.allocator, 1);
        defer tracker.deinit();
        const token = try tracker.registerInput();
        var reference = ReferenceToken{};
        var remaining_code = encoded;

        for (0..sequence_length) |_| {
            const action = actions[remaining_code % actions.len];
            remaining_code /= actions.len;
            if (reference.apply(action)) {
                try applyTokenAction(token, action);
            } else |expected_error| {
                try std.testing.expectError(expected_error, applyTokenAction(token, action));
            }
            try std.testing.expectEqual(reference.state, try token.state());
            try std.testing.expectEqual(reference.received, tracker.receivedCount());
            try std.testing.expectEqual(reference.completions, tracker.completionCount());
            if (reference.verify()) {
                try tracker.verifyReceivedCompleted();
            } else |expected_error| {
                try std.testing.expectError(expected_error, tracker.verifyReceivedCompleted());
            }
        }
    }

    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    _ = try tracker.registerInput();
    const invalid_id: TokenId = @enumFromInt(1);
    try std.testing.expectError(error.InvalidToken, tracker.state(invalid_id));
    const invalid = AdapterToken{ .tracker = &tracker, .id = invalid_id };
    try std.testing.expectError(error.InvalidToken, invalid.receive());
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
    return PacketSlot.init(token, segments, total, 0, .{}, null);
}

test "slot rejects malformed descriptors and checked arithmetic overflow" {
    var tracker = try TokenTracker.init(std.testing.allocator, 3);
    defer tracker.deinit();
    const token = try tracker.registerInput();

    const malformed = [_]SegmentDescriptor{.{ .bytes = &.{1}, .declared_len = 2 }};
    try std.testing.expectError(error.MalformedDescriptor, PacketSlot.init(token, &malformed, 2, 0, .{}, null));
    const mismatch = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&.{ 1, 2 })};
    try std.testing.expectError(error.MalformedDescriptor, PacketSlot.init(token, &mismatch, 1, 0, .{}, null));
    const overflow = [_]SegmentDescriptor{
        .{ .bytes = &.{}, .declared_len = std.math.maxInt(usize) },
        .{ .bytes = &.{}, .declared_len = 1 },
    };
    try std.testing.expectError(error.DescriptorOverflow, PacketSlot.init(token, &overflow, 0, 0, .{}, null));

    var too_many: [max_segments + 1]SegmentDescriptor = undefined;
    for (&too_many) |*segment| segment.* = SegmentDescriptor.fromBytes(&.{});
    try std.testing.expectError(error.TooManySegments, PacketSlot.init(token, &too_many, 0, 0, .{}, null));
}

fn expectedContiguous(
    descriptors: []const SegmentDescriptor,
    range: ByteRange,
) ?[]const u8 {
    if (range.len == 0) return &.{};
    var segment_start: usize = 0;
    for (descriptors) |segment| {
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

fn exerciseAllRanges(
    owner: *PacketBatchOwner,
    view: PacketView,
    descriptors: []const SegmentDescriptor,
    payload: []const u8,
) !void {
    for (0..payload.len + 1) |start| for (start..payload.len + 1) |end| {
        const range = ByteRange{ .offset = start, .len = end - start };
        var actual: [32]u8 = undefined;
        try view.read(owner, range, &actual);
        try std.testing.expectEqualSlices(u8, payload[start..end], actual[0 .. end - start]);

        const expected_contiguous = expectedContiguous(descriptors, range);
        const actual_contiguous = try view.contiguous(owner, range);
        try std.testing.expectEqual(expected_contiguous != null, actual_contiguous != null);
        if (expected_contiguous) |expected| {
            const contiguous = actual_contiguous.?;
            try std.testing.expectEqualSlices(u8, expected, contiguous);
            if (expected.len != 0)
                try std.testing.expectEqual(@intFromPtr(expected.ptr), @intFromPtr(contiguous.ptr));
        }

        var iterator = try view.segments(owner, range);
        var iterator_offset = start;
        while (try iterator.next(owner)) |piece| {
            try std.testing.expectEqualSlices(
                u8,
                payload[iterator_offset .. iterator_offset + piece.len],
                piece,
            );
            iterator_offset += piece.len;
        }
        try std.testing.expectEqual(end, iterator_offset);
    };
}

test "FR-PKT-006 all ranges cover 1 through 16 segments and empty boundaries" {
    const payload = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (1..max_segments + 1) |segment_count| {
        var tracker = try TokenTracker.init(std.testing.allocator, 1);
        defer tracker.deinit();
        var segments: [max_segments]SegmentDescriptor = undefined;
        var start: usize = 0;
        for (0..segment_count) |segment_index| {
            const end = if (segment_index + 1 == segment_count)
                payload.len
            else
                ((segment_index + 1) * payload.len) / segment_count;
            segments[segment_index] = SegmentDescriptor.fromBytes(payload[start..end]);
            start = end;
        }
        const slot = try makeLiveSlot(&tracker, segments[0..segment_count], payload.len);
        var slots = [_]PacketSlot{slot};
        const owner = try PacketBatchOwner.init(std.testing.allocator);
        defer owner.deinit();
        const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(2) }, &slots);
        defer {
            batch.invalidate(owner) catch unreachable;
            slots[0].token.returnToInput() catch unreachable;
            tracker.verifyReceivedCompleted() catch unreachable;
        }
        const view = try batch.view(owner, 0);
        try exerciseAllRanges(owner, view, segments[0..segment_count], &payload);
        var too_small: [1]u8 = undefined;
        try std.testing.expectError(error.DestinationTooSmall, view.read(owner, .{ .offset = 0, .len = 2 }, &too_small));
        try std.testing.expectError(error.Bounds, view.read(owner, .{ .offset = payload.len, .len = 1 }, &.{}));
        try std.testing.expectError(error.Overflow, view.read(owner, .{ .offset = std.math.maxInt(usize), .len = 2 }, &.{}));
    }

    const empty_boundaries = [_]usize{ 0, 2, 2, payload.len };
    var empty_segments: [empty_boundaries.len + 1]SegmentDescriptor = undefined;
    var empty_start: usize = 0;
    for (empty_boundaries, 0..) |end, index| {
        empty_segments[index] = SegmentDescriptor.fromBytes(payload[empty_start..end]);
        empty_start = end;
    }
    empty_segments[empty_boundaries.len] = SegmentDescriptor.fromBytes(payload[empty_start..]);
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const slot = try makeLiveSlot(&tracker, &empty_segments, payload.len);
    var slots = [_]PacketSlot{slot};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(2) }, &slots);
    try exerciseAllRanges(owner, try batch.view(owner, 0), &empty_segments, &payload);
    try batch.invalidate(owner);
    try slots[0].token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-001 batch sizes zero through 64 are valid and 65 is rejected" {
    var tracker = try TokenTracker.init(std.testing.allocator, max_batch + 1);
    defer tracker.deinit();
    const bytes = [_]u8{1};
    const descriptor = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    var slots: [max_batch + 1]PacketSlot = undefined;
    for (&slots, 0..) |*slot, index| {
        slot.* = try makeLiveSlot(&tracker, &descriptor, 1);
        slot.receive_order = index;
    }
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    for (0..max_batch + 1) |size| {
        const batch = try owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            slots[0..size],
        );
        try std.testing.expectEqual(size, try batch.len(owner));
        try batch.invalidate(owner);
    }
    try std.testing.expectError(
        error.BatchTooLarge,
        owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots),
    );
    for (&slots) |slot| try slot.token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

fn escapeViewAfterProcessingCall(
    owner: *PacketBatchOwner,
    slots: []const PacketSlot,
) !PacketView {
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        slots,
    );
    const escaped = try batch.view(owner, 0);
    try batch.invalidate(owner);
    return escaped;
}

test "FR-PKT-002 FR-PKT-003 FR-PKT-012 INV-PKT-002 pointer-free owner-bound handles resist escape reuse forging and iterator mutation" {
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const bytes = [_]u8{1};
    const descriptor = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    var first = try makeLiveSlot(&tracker, &descriptor, 1);
    first.receive_order = 2;
    var second = try makeLiveSlot(&tracker, &descriptor, 1);
    second.receive_order = 1;
    var reversed = [_]PacketSlot{ first, second };
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    try std.testing.expectError(
        error.ReceiveOrderViolation,
        owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &reversed),
    );

    var ordered = [_]PacketSlot{ second, first };
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &ordered);
    const copied_batch = batch;
    const origin = try copied_batch.origin(owner);
    try std.testing.expectEqual(@as(u64, 1), origin.input_id.raw());
    try std.testing.expectEqual(@as(u64, 1), origin.queue_id.raw());
    const view = try copied_batch.view(owner, 0);
    try std.testing.expectEqual(@as(usize, 1), try view.length(owner));
    var iterator = try view.segments(owner, .{ .offset = 0, .len = 1 });

    const zero_batch: PacketBatch = @enumFromInt(0);
    const random_batch: PacketBatch = @enumFromInt(std.math.maxInt(HandleInt));
    const modified_batch: PacketBatch = @enumFromInt(@intFromEnum(batch) + 1);
    inline for (.{ zero_batch, random_batch, modified_batch }) |forged| {
        try std.testing.expectError(error.BatchReleased, forged.len(owner));
        try std.testing.expectError(error.BatchReleased, forged.origin(owner));
        try std.testing.expectError(error.BatchReleased, forged.view(owner, 0));
        try std.testing.expectError(error.BatchReleased, forged.invalidate(owner));
    }

    const zero_view: PacketView = @enumFromInt(0);
    const random_view: PacketView = @enumFromInt(std.math.maxInt(HandleInt));
    const modified_view: PacketView = @enumFromInt(
        (@intFromEnum(view) & ~@as(HandleInt, 0xff)) | 0xff,
    );
    inline for (.{ zero_view, random_view, modified_view }) |forged| {
        try std.testing.expectError(error.StaleView, forged.length(owner));
        try std.testing.expectError(error.StaleView, forged.metadata(owner));
        try std.testing.expectError(
            error.StaleView,
            forged.contiguous(owner, .{ .offset = 0, .len = 0 }),
        );
        var forged_destination = [_]u8{0};
        try std.testing.expectError(
            error.StaleView,
            forged.read(owner, .{ .offset = 0, .len = 0 }, &forged_destination),
        );
        try std.testing.expectError(
            error.StaleView,
            forged.segments(owner, .{ .offset = 0, .len = 0 }),
        );
    }
    try std.testing.expectEqual(@as(usize, 1), try view.length(owner));

    var forged_iterator = iterator;
    forged_iterator.view_handle = zero_view;
    try std.testing.expectError(error.StaleView, forged_iterator.next(owner));
    forged_iterator = iterator;
    forged_iterator.range_start = std.math.maxInt(usize);
    try std.testing.expectError(error.Bounds, forged_iterator.next(owner));
    forged_iterator = iterator;
    forged_iterator.range_end = std.math.maxInt(usize);
    try std.testing.expectError(error.Bounds, forged_iterator.next(owner));
    forged_iterator = iterator;
    forged_iterator.range_start = 1;
    forged_iterator.range_end = 0;
    try std.testing.expectError(error.Bounds, forged_iterator.next(owner));
    forged_iterator = iterator;
    forged_iterator.segment_index = std.math.maxInt(usize);
    try std.testing.expectError(error.Bounds, forged_iterator.next(owner));
    try std.testing.expectEqualSlices(u8, &bytes, (try iterator.next(owner)).?);
    try std.testing.expect((try iterator.next(owner)) == null);

    try batch.invalidate(owner);

    try std.testing.expectError(error.BatchReleased, batch.len(owner));
    try std.testing.expectError(error.BatchReleased, copied_batch.len(owner));
    try std.testing.expectError(error.BatchReleased, copied_batch.origin(owner));
    try std.testing.expectError(error.BatchReleased, copied_batch.view(owner, 0));
    try std.testing.expectError(error.StaleView, view.length(owner));
    try std.testing.expectError(error.StaleView, view.metadata(owner));
    try std.testing.expectError(error.StaleView, view.contiguous(owner, .{ .offset = 0, .len = 1 }));
    var stale_destination = [_]u8{0};
    try std.testing.expectError(error.StaleView, view.read(owner, .{ .offset = 0, .len = 1 }, &stale_destination));
    try std.testing.expectError(error.StaleView, view.segments(owner, .{ .offset = 0, .len = 1 }));
    try std.testing.expectError(error.StaleView, iterator.next(owner));
    try std.testing.expectError(error.BatchReleased, batch.view(owner, 0));
    try std.testing.expectError(error.BatchReleased, copied_batch.invalidate(owner));

    const escaped = try escapeViewAfterProcessingCall(owner, &ordered);
    try std.testing.expectError(error.StaleView, escaped.length(owner));

    const next_batch = try owner.begin(
        .{ .input_id = .init(2), .queue_id = .init(3) },
        &ordered,
    );
    const next_view = try next_batch.view(owner, 0);
    try std.testing.expectEqual(@as(usize, 1), try next_view.length(owner));
    try std.testing.expectError(error.StaleView, view.length(owner));
    try std.testing.expectError(error.StaleView, escaped.length(owner));
    try next_batch.invalidate(owner);

    const implementation = ownerImpl(owner);
    implementation.next_generation = max_generation;
    try std.testing.expectError(
        error.GenerationExhausted,
        owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &ordered),
    );
    try std.testing.expectError(error.StaleView, next_view.length(owner));

    try ordered[0].token.returnToInput();
    try ordered[1].token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "INV-PKT-002 public handle surface contains no backing pointers or mutable generation fields" {
    try std.testing.expect(@typeInfo(PacketBatch) == .@"enum");
    try std.testing.expect(@typeInfo(PacketView) == .@"enum");
    try std.testing.expect(@typeInfo(PacketBatchOwner) == .@"opaque");
    try std.testing.expectEqual(@as(usize, @sizeOf(u128)), @sizeOf(PacketBatch));
    try std.testing.expectEqual(@as(usize, @sizeOf(u128)), @sizeOf(PacketView));
    inline for (std.meta.fields(SegmentIterator)) |field|
        try std.testing.expect(@typeInfo(field.type) != .pointer);
}

fn expectCrossOwnerViewRejected(
    view: PacketView,
    wrong_owner: *PacketBatchOwner,
) !void {
    try std.testing.expectError(error.StaleView, view.length(wrong_owner));
    try std.testing.expectError(error.StaleView, view.metadata(wrong_owner));
    try std.testing.expectError(
        error.StaleView,
        view.contiguous(wrong_owner, .{ .offset = 0, .len = 0 }),
    );
    var destination = [_]u8{0};
    try std.testing.expectError(
        error.StaleView,
        view.read(
            wrong_owner,
            .{ .offset = 0, .len = 0 },
            &destination,
        ),
    );
    try std.testing.expectError(
        error.StaleView,
        view.segments(wrong_owner, .{ .offset = 0, .len = 0 }),
    );
}

test "INV-PKT-002 owner identities reject every cross-owner handle and exhaust without reuse" {
    var tracker = try TokenTracker.init(std.testing.allocator, 3);
    defer tracker.deinit();
    const bytes_a = [_]u8{0xa1};
    const bytes_b0 = [_]u8{ 0xb1, 0xb2 };
    const bytes_b1 = [_]u8{ 0xc1, 0xc2, 0xc3 };
    const descriptor_a = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes_a)};
    const descriptor_b0 = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes_b0)};
    const descriptor_b1 = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes_b1)};
    var slot_a = try makeLiveSlot(&tracker, &descriptor_a, bytes_a.len);
    slot_a.receive_order = 1;
    var slot_b0 = try makeLiveSlot(&tracker, &descriptor_b0, bytes_b0.len);
    slot_b0.receive_order = 1;
    var slot_b1 = try makeLiveSlot(&tracker, &descriptor_b1, bytes_b1.len);
    slot_b1.receive_order = 2;
    var slots_a = [_]PacketSlot{slot_a};
    var slots_b = [_]PacketSlot{ slot_b0, slot_b1 };

    const owner_a = try PacketBatchOwner.init(std.testing.allocator);
    defer owner_a.deinit();
    const owner_b = try PacketBatchOwner.init(std.testing.allocator);
    defer owner_b.deinit();
    const batch_a = try owner_a.begin(
        .{ .input_id = .init(101), .queue_id = .init(1) },
        &slots_a,
    );
    const batch_b = try owner_b.begin(
        .{ .input_id = .init(202), .queue_id = .init(2) },
        &slots_b,
    );
    const view_a = try batch_a.view(owner_a, 0);
    const view_b = try batch_b.view(owner_b, 1);
    var iterator_a = try view_a.segments(
        owner_a,
        .{ .offset = 0, .len = bytes_a.len },
    );
    var iterator_b = try view_b.segments(
        owner_b,
        .{ .offset = 0, .len = bytes_b1.len },
    );

    try std.testing.expectError(error.BatchReleased, batch_a.len(owner_b));
    try std.testing.expectError(error.BatchReleased, batch_a.origin(owner_b));
    try std.testing.expectError(error.BatchReleased, batch_a.view(owner_b, 0));
    try std.testing.expectError(error.BatchReleased, batch_a.invalidate(owner_b));
    try std.testing.expectError(error.BatchReleased, batch_b.len(owner_a));
    try std.testing.expectError(error.BatchReleased, batch_b.origin(owner_a));
    try std.testing.expectError(error.BatchReleased, batch_b.view(owner_a, 0));
    try std.testing.expectError(error.BatchReleased, batch_b.invalidate(owner_a));
    try expectCrossOwnerViewRejected(view_a, owner_b);
    try expectCrossOwnerViewRejected(view_b, owner_a);
    try std.testing.expectError(error.StaleView, iterator_a.next(owner_b));
    try std.testing.expectError(error.StaleView, iterator_b.next(owner_a));

    const forged_batch_identity: PacketBatch = @enumFromInt(
        @intFromEnum(batch_a) ^ (@as(HandleInt, 1) << handle_component_bits),
    );
    const forged_view_identity: PacketView = @enumFromInt(
        @intFromEnum(view_a) ^ (@as(HandleInt, 1) << handle_component_bits),
    );
    try std.testing.expectError(
        error.BatchReleased,
        forged_batch_identity.len(owner_a),
    );
    try expectCrossOwnerViewRejected(forged_view_identity, owner_a);

    try std.testing.expectEqual(@as(usize, 1), try batch_a.len(owner_a));
    try std.testing.expectEqual(@as(usize, 2), try batch_b.len(owner_b));
    try std.testing.expectEqual(
        @as(u64, 101),
        (try batch_a.origin(owner_a)).input_id.raw(),
    );
    try std.testing.expectEqual(
        @as(u64, 202),
        (try batch_b.origin(owner_b)).input_id.raw(),
    );
    try std.testing.expectEqual(bytes_a.len, try view_a.length(owner_a));
    try std.testing.expectEqual(bytes_b1.len, try view_b.length(owner_b));
    try std.testing.expectEqualSlices(u8, &bytes_a, (try iterator_a.next(owner_a)).?);
    try std.testing.expectEqualSlices(u8, &bytes_b1, (try iterator_b.next(owner_b)).?);

    try batch_a.invalidate(owner_a);
    try batch_b.invalidate(owner_b);
    try slots_a[0].token.returnToInput();
    try slots_b[0].token.returnToInput();
    try slots_b[1].token.returnToInput();
    try tracker.verifyReceivedCompleted();

    var exhaustion_counter = std.atomic.Value(u64).init(std.math.maxInt(u64) - 1);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        try allocateOwnerIdentity(&exhaustion_counter),
    );
    try std.testing.expectError(
        error.OwnerIdentityExhausted,
        allocateOwnerIdentity(&exhaustion_counter),
    );
    try std.testing.expectError(
        error.OwnerIdentityExhausted,
        allocateOwnerIdentity(&exhaustion_counter),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        exhaustion_counter.load(.monotonic),
    );
}
