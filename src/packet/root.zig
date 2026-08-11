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
const DropReasonTag = enum { drop_reason };
const CompletionTag = enum { completion };

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
/// Bounded application-defined drop reason identity.
pub const DropReasonId = foundation.StableId(DropReasonTag);
/// Bounded application-defined completion handler identity.
pub const CompletionId = foundation.StableId(CompletionTag);

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

/// Mutation abilities associated with one explicit mutable descriptor.
pub const MutationCapabilities = packed struct(u8) {
    same_length: bool = true,
    resize: bool = false,
    _reserved: u6 = 0,
};

/// Explicit mutable packet storage and its active byte range.
///
/// The active range, headroom, and tailroom are validated independently; no
/// read-only descriptor is ever converted back to mutable storage.
pub const MutableSegmentDescriptor = struct {
    storage: []u8,
    active_offset: usize,
    active_len: usize,
    headroom: usize,
    tailroom: usize,
    capabilities: MutationCapabilities = .{},

    /// Mutable descriptor validation errors.
    pub const Error = error{ Overflow, MalformedDescriptor };

    /// Constructs a descriptor whose declared room exactly partitions storage.
    pub fn init(
        storage: []u8,
        active_offset: usize,
        active_len: usize,
        capabilities: MutationCapabilities,
    ) Error!MutableSegmentDescriptor {
        const end = std.math.add(usize, active_offset, active_len) catch
            return error.Overflow;
        if (end > storage.len) return error.MalformedDescriptor;
        return .{
            .storage = storage,
            .active_offset = active_offset,
            .active_len = active_len,
            .headroom = active_offset,
            .tailroom = storage.len - end,
            .capabilities = capabilities,
        };
    }

    fn validate(self: MutableSegmentDescriptor) Error!void {
        const end = std.math.add(usize, self.active_offset, self.active_len) catch
            return error.Overflow;
        const partition = std.math.add(usize, self.headroom, self.active_len) catch
            return error.Overflow;
        const total = std.math.add(usize, partition, self.tailroom) catch
            return error.Overflow;
        if (self.headroom != self.active_offset or end > self.storage.len or
            total != self.storage.len)
            return error.MalformedDescriptor;
    }

    fn active(self: MutableSegmentDescriptor) []u8 {
        return self.storage[self.active_offset .. self.active_offset + self.active_len];
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
    mutable_storage: [max_segments]?MutableSegmentDescriptor = [_]?MutableSegmentDescriptor{null} ** max_segments,

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

    /// Validates explicit mutable descriptors and constructs a mutable slot.
    pub fn initMutable(
        token: AdapterToken,
        descriptors: []const MutableSegmentDescriptor,
        declared_total: usize,
        receive_order: u64,
        metadata: PacketMetadata,
        instrumentation: ?*PacketPathInstrumentation,
    ) SlotError!PacketSlot {
        if (descriptors.len > max_segments) return error.TooManySegments;
        var readonly: [max_segments]SegmentDescriptor = undefined;
        var total: usize = 0;
        for (descriptors, 0..) |descriptor, index| {
            descriptor.validate() catch return error.MalformedDescriptor;
            total = std.math.add(usize, total, descriptor.active_len) catch
                return error.DescriptorOverflow;
            readonly[index] = SegmentDescriptor.fromBytes(descriptor.active());
        }
        if (total != declared_total) return error.MalformedDescriptor;
        var slot = try PacketSlot.init(
            token,
            readonly[0..descriptors.len],
            declared_total,
            receive_order,
            metadata,
            instrumentation,
        );
        for (descriptors, 0..) |descriptor, index|
            slot.mutable_storage[index] = descriptor;
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

    fn refreshMutableSegment(self: *PacketSlot, index: usize) void {
        const descriptor = self.mutable_storage[index].?;
        self.segment_storage[index] = SegmentDescriptor.fromBytes(descriptor.active());
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

/// Checked receive-order packet index within one bounded batch.
pub const PacketIndex = enum(u8) {
    _,

    /// Index construction errors.
    pub const Error = error{OutOfRange};

    /// Constructs an index only when it is inside `batch_len` and the M2 cap.
    pub fn init(value: usize, batch_len: usize) Error!PacketIndex {
        if (batch_len > max_batch or value >= batch_len) return error.OutOfRange;
        return @enumFromInt(@as(u8, @intCast(value)));
    }

    /// Returns the receive-order numeric index.
    pub fn raw(self: PacketIndex) usize {
        return @intFromEnum(self);
    }
};

/// Opaque one-word packet selection for batches of at most 64 packets.
pub const PacketSelection = enum(u64) {
    _,

    /// Selection construction and membership errors.
    pub const Error = error{ BatchTooLarge, OutOfRange };

    /// Constructs the selection containing every packet in `batch_len`.
    pub fn all(batch_len: usize) Error!PacketSelection {
        if (batch_len > max_batch) return error.BatchTooLarge;
        if (batch_len == max_batch) return @enumFromInt(std.math.maxInt(u64));
        return @enumFromInt((@as(u64, 1) << @intCast(batch_len)) - 1);
    }

    /// Constructs an empty selection.
    pub fn empty() PacketSelection {
        return @enumFromInt(0);
    }

    /// Constructs a singleton after checking the batch bound.
    pub fn one(index: usize, batch_len: usize) Error!PacketSelection {
        const checked = try PacketIndex.init(index, batch_len);
        return @enumFromInt(@as(u64, 1) << @intCast(checked.raw()));
    }

    /// Returns whether an index is selected after validating this batch bound.
    pub fn contains(
        self: PacketSelection,
        index: PacketIndex,
        batch_len: usize,
    ) Error!bool {
        const valid = (try PacketSelection.all(batch_len)).bits();
        const checked = try PacketIndex.init(index.raw(), batch_len);
        if ((self.bits() & ~valid) != 0) return error.OutOfRange;
        return (self.bits() & (@as(u64, 1) << @intCast(checked.raw()))) != 0;
    }

    /// Returns the intersection of two selections.
    pub fn intersect(self: PacketSelection, other: PacketSelection) PacketSelection {
        return @enumFromInt(@intFromEnum(self) & @intFromEnum(other));
    }

    /// Returns a selection with one batch-validated packet removed.
    pub fn without(
        self: PacketSelection,
        index: PacketIndex,
        batch_len: usize,
    ) Error!PacketSelection {
        const valid = (try PacketSelection.all(batch_len)).bits();
        const checked = try PacketIndex.init(index.raw(), batch_len);
        if ((self.bits() & ~valid) != 0) return error.OutOfRange;
        return @enumFromInt(self.bits() & ~(@as(u64, 1) << @intCast(checked.raw())));
    }

    /// Returns the number of selected packets.
    pub fn count(self: PacketSelection) usize {
        return @popCount(@intFromEnum(self));
    }

    /// Returns whether no packet is selected.
    pub fn isEmpty(self: PacketSelection) bool {
        return @intFromEnum(self) == 0;
    }

    /// Iterates set bits in ascending receive order.
    pub fn iterator(self: PacketSelection) SelectionIterator {
        return .{ .remaining = @intFromEnum(self) };
    }

    fn bits(self: PacketSelection) u64 {
        return @intFromEnum(self);
    }
};

/// Allocation-free ascending set-bit iterator.
pub const SelectionIterator = struct {
    remaining: u64,

    /// Returns the next set packet index.
    pub fn next(self: *SelectionIterator) ?PacketIndex {
        if (self.remaining == 0) return null;
        const bit: u6 = @intCast(@ctz(self.remaining));
        self.remaining &= self.remaining - 1;
        return @enumFromInt(@as(u8, bit));
    }
};

/// Segment-aware packet read errors.
pub const ViewError = error{
    Bounds,
    Overflow,
    DestinationTooSmall,
    StaleView,
    AccessRevoked,
};

/// Lazy cache status for each protocol layer.
pub const ParseStatus = enum(u8) {
    unparsed,
    present,
    absent,
    truncated,
    malformed,
    unsupported,
};

/// Bounded IPv6 extension traversal configuration.
pub const ParserConfig = struct {
    max_ipv6_extension_headers: u8 = 8,
    max_ipv6_extension_bytes: u16 = 256,

    /// Configuration errors are rejected before cache mutation.
    pub const Error = error{InvalidParserLimit};

    fn validate(self: ParserConfig) Error!void {
        if (self.max_ipv6_extension_headers > 16 or
            self.max_ipv6_extension_bytes > 1024)
            return error.InvalidParserLimit;
    }

    fn eql(self: ParserConfig, other: ParserConfig) bool {
        return self.max_ipv6_extension_headers == other.max_ipv6_extension_headers and
            self.max_ipv6_extension_bytes == other.max_ipv6_extension_bytes;
    }
};

/// Parsed network protocol category.
pub const NetworkProtocol = enum { none, ipv4, ipv6 };
/// Parsed transport protocol category.
pub const TransportProtocol = enum { none, tcp, udp, icmpv4, icmpv6 };

/// Selected Ethernet/VLAN fields cached per packet.
pub const EthernetFields = struct {
    destination: [6]u8 = [_]u8{0} ** 6,
    source: [6]u8 = [_]u8{0} ** 6,
    ether_type: u16 = 0,
    vlan_count: u8 = 0,
    vlan_tci: [2]u16 = [_]u16{0} ** 2,
    header_len: usize = 0,
};

/// Selected IPv4 fields and fragmentation facts.
pub const Ipv4Fields = struct {
    header_offset: usize = 0,
    header_len: usize = 0,
    total_len: u16 = 0,
    dscp: u6 = 0,
    ttl: u8 = 0,
    protocol: u8 = 0,
    source: [4]u8 = [_]u8{0} ** 4,
    destination: [4]u8 = [_]u8{0} ** 4,
    fragment_offset: u13 = 0,
    more_fragments: bool = false,
};

/// Selected IPv6 fields and bounded extension/fragment facts.
pub const Ipv6Fields = struct {
    header_offset: usize = 0,
    payload_len: u16 = 0,
    traffic_class: u8 = 0,
    hop_limit: u8 = 0,
    source: [16]u8 = [_]u8{0} ** 16,
    destination: [16]u8 = [_]u8{0} ** 16,
    extension_headers: u8 = 0,
    extension_bytes: u16 = 0,
    fragment_offset: u13 = 0,
    more_fragments: bool = false,
};

/// Selected TCP fields.
pub const TcpFields = struct {
    header_offset: usize = 0,
    header_len: usize = 0,
    source_port: u16 = 0,
    destination_port: u16 = 0,
    flags: u8 = 0,
};

/// Selected UDP fields.
pub const UdpFields = struct {
    header_offset: usize = 0,
    source_port: u16 = 0,
    destination_port: u16 = 0,
    length: u16 = 0,
    checksum: u16 = 0,
};

/// Selected ICMP fields; ICMP mutation is intentionally outside M2.
pub const IcmpFields = struct {
    header_offset: usize = 0,
    kind: u8 = 0,
    code: u8 = 0,
};

/// One preallocated lazy parse cache entry.
pub const ParsedPacket = struct {
    ethernet_status: ParseStatus = .unparsed,
    network_status: ParseStatus = .unparsed,
    transport_status: ParseStatus = .unparsed,
    network_protocol: NetworkProtocol = .none,
    transport_protocol: TransportProtocol = .none,
    ethernet: EthernetFields = .{},
    ipv4: Ipv4Fields = .{},
    ipv6: Ipv6Fields = .{},
    tcp: TcpFields = .{},
    udp: UdpFields = .{},
    icmp: IcmpFields = .{},
    non_initial_fragment: bool = false,
    incomplete_fragment: bool = false,
    config: ParserConfig = .{},
};

/// Layers changed by structured or explicitly unsafe mutation.
pub const DirtyLayers = packed struct(u8) {
    l2: bool = false,
    l3: bool = false,
    l4: bool = false,
    _reserved: u5 = 0,

    fn any(self: DirtyLayers) bool {
        return self.l2 or self.l3 or self.l4;
    }
};

/// Checksum work recorded by mutation operations.
pub const ChecksumDependencies = packed struct(u8) {
    ipv4_header: bool = false,
    transport: bool = false,
    pseudo_header: bool = false,
    _reserved: u5 = 0,
};

/// Per-slot preallocated mutation and finalization state.
pub const MutationJournal = struct {
    dirty: DirtyLayers = .{},
    signed_length_delta: i32 = 0,
    tail_length_delta: i32 = 0,
    checksums: ChecksumDependencies = .{},
    pre_tail_resize_parsed: ParsedPacket = .{},
    pre_tail_resize_frame_len: usize = 0,
    has_pre_tail_resize: bool = false,
    cache_invalidated: bool = false,
    offload_eligible: bool = true,
    invalid: bool = false,
    finalized: bool = true,
    edit_failed: bool = false,

    fn needsFinalize(self: MutationJournal) bool {
        return self.dirty.any() or self.signed_length_delta != 0;
    }
};

/// Declaration required for explicitly unsafe raw writes.
pub const RawWriteDeclaration = struct {
    invalidates: DirtyLayers = .{},
    full_software_validation: bool = false,
};

const HandleInt = u128;
const handle_component_bits = 64;
const view_index_bits = 8;
const max_generation = (@as(u64, 1) << (64 - view_index_bits)) - 1;
const raw_capability_domain: u8 = 0x80;
const raw_capability_derivation_attempts = max_batch + 1;

const RawCapabilityAuthority = struct {
    token: u64 = 0,
    batch_generation: u64 = 0,
};

const SlotAccess = enum {
    unavailable,
    batch_owned,
    retained,
};

const BatchOwnerImpl = struct {
    allocator: std.mem.Allocator,
    owner_identity: u64,
    next_generation: u64 = 0,
    live_generation: u64 = 0,
    origin: InputOrigin = undefined,
    slots: [max_batch]PacketSlot = undefined,
    slot_count: usize = 0,
    slot_access: [max_batch]SlotAccess = [_]SlotAccess{.unavailable} ** max_batch,
    nonrevocable_access_issued: [max_batch]bool = [_]bool{false} ** max_batch,
    parse_cache: [max_batch]ParsedPacket = [_]ParsedPacket{.{}} ** max_batch,
    journals: [max_batch]MutationJournal = [_]MutationJournal{.{}} ** max_batch,
    mutation_fail_after: ?usize = null,
    mutation_attempts: usize = 0,
    raw_capability_secret: [32]u8,
    raw_capability_mint_counter: u64 = 0,
    raw_capability_authorities: [max_batch]RawCapabilityAuthority =
        [_]RawCapabilityAuthority{.{}} ** max_batch,
    next_disposition_generation: u64 = 0,
    disposition: DispositionWriterState = .{},
};

const OwnerIdentityError = error{OwnerIdentityExhausted};
const EntropyError = error{EntropyUnavailable};
var owner_identity_counter = std.atomic.Value(u64).init(0);

fn fillSecureRandom(buffer: []u8) EntropyError!void {
    var offset: usize = 0;
    while (offset != buffer.len) {
        const remaining = buffer[offset..];
        const result = std.os.linux.getrandom(remaining.ptr, remaining.len, 0);
        switch (std.posix.errno(result)) {
            .SUCCESS => {
                const received: usize = @intCast(result);
                if (received == 0) return error.EntropyUnavailable;
                offset += received;
            },
            .INTR => continue,
            else => return error.EntropyUnavailable,
        }
    }
}

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

fn deriveRawCapabilityToken(owner: *const BatchOwnerImpl, counter: u64) u64 {
    var input: [16]u8 = undefined;
    std.mem.writeInt(u64, input[0..8], owner.owner_identity, .little);
    std.mem.writeInt(u64, input[8..16], counter, .little);
    var digest: [32]u8 = undefined;
    var hasher = std.crypto.hash.Blake3.init(.{ .key = owner.raw_capability_secret });
    hasher.update(&input);
    hasher.final(&digest);
    const opaque_bits = std.mem.readInt(u64, digest[0..8], .little);
    return (opaque_bits & ~@as(u64, 0xff)) |
        raw_capability_domain |
        (@as(u8, @truncate(opaque_bits)) & 0x3f);
}

fn rawCapabilityTokenAvailable(owner: *const BatchOwnerImpl, token: u64) bool {
    const public_prefix = token >> view_index_bits;
    if (token == 0 or public_prefix <= raw_capability_derivation_attempts or
        public_prefix == owner.live_generation)
        return false;
    for (owner.raw_capability_authorities[0..owner.slot_count]) |authority|
        if (authority.batch_generation == owner.live_generation and authority.token == token)
            return false;
    return true;
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
    if (owner.slot_access[index] != .batch_owned) return error.AccessRevoked;
    return &owner.slots[index];
}

fn ensureSlotBatchAccess(owner: *const BatchOwnerImpl, index: usize) error{ Bounds, AccessRevoked }!void {
    if (index >= owner.slot_count) return error.Bounds;
    if (owner.slot_access[index] != .batch_owned) return error.AccessRevoked;
}

fn markNonrevocableAccess(owner_handle: *PacketBatchOwner, index: usize) void {
    ownerImpl(owner_handle).nonrevocable_access_issued[index] = true;
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

fn slotByte(slot: *const PacketSlot, offset: usize) ViewError!u8 {
    if (offset >= slot.total_len) return error.Bounds;
    var segment_start: usize = 0;
    for (slot.segment_storage[0..slot.segment_count]) |segment| {
        const segment_end = std.math.add(usize, segment_start, segment.declared_len) catch
            return error.Overflow;
        if (offset < segment_end) return segment.bytes[offset - segment_start];
        segment_start = segment_end;
    }
    return error.Bounds;
}

fn slotRead(slot: *const PacketSlot, offset: usize, destination: []u8) ViewError!void {
    const end = std.math.add(usize, offset, destination.len) catch return error.Overflow;
    if (end > slot.total_len) return error.Bounds;
    for (destination, 0..) |*byte, index|
        byte.* = try slotByte(slot, offset + index);
}

fn slotU16(slot: *const PacketSlot, offset: usize) ViewError!u16 {
    var bytes: [2]u8 = undefined;
    try slotRead(slot, offset, &bytes);
    return std.mem.readInt(u16, &bytes, .big);
}

fn isVlanEtherType(ether_type: u16) bool {
    return ether_type == 0x8100 or ether_type == 0x88a8;
}

fn setNetworkFailure(entry: *ParsedPacket, status: ParseStatus) void {
    entry.network_status = status;
    entry.transport_status = .absent;
    entry.network_protocol = .none;
    entry.transport_protocol = .none;
}

fn setTransportFailure(entry: *ParsedPacket, status: ParseStatus) void {
    entry.transport_status = status;
    entry.transport_protocol = .none;
}

fn parseTransport(
    slot: *const PacketSlot,
    entry: *ParsedPacket,
    protocol: u8,
    offset: usize,
    available: usize,
) void {
    switch (protocol) {
        6 => {
            entry.transport_protocol = .tcp;
            if (available < 20) return setTransportFailure(entry, .truncated);
            const data_offset = slotByte(slot, offset + 12) catch
                return setTransportFailure(entry, .truncated);
            const header_len: usize = @as(usize, data_offset >> 4) * 4;
            if (header_len < 20) return setTransportFailure(entry, .malformed);
            if (header_len > available) return setTransportFailure(entry, .truncated);
            entry.tcp = .{
                .header_offset = offset,
                .header_len = header_len,
                .source_port = slotU16(slot, offset) catch
                    return setTransportFailure(entry, .truncated),
                .destination_port = slotU16(slot, offset + 2) catch
                    return setTransportFailure(entry, .truncated),
                .flags = slotByte(slot, offset + 13) catch
                    return setTransportFailure(entry, .truncated),
            };
            entry.transport_status = .present;
        },
        17 => {
            entry.transport_protocol = .udp;
            if (available < 8) return setTransportFailure(entry, .truncated);
            const length = slotU16(slot, offset + 4) catch
                return setTransportFailure(entry, .truncated);
            if (length < 8) return setTransportFailure(entry, .malformed);
            if (length > available and !entry.incomplete_fragment)
                return setTransportFailure(entry, .malformed);
            entry.udp = .{
                .header_offset = offset,
                .source_port = slotU16(slot, offset) catch
                    return setTransportFailure(entry, .truncated),
                .destination_port = slotU16(slot, offset + 2) catch
                    return setTransportFailure(entry, .truncated),
                .length = length,
                .checksum = slotU16(slot, offset + 6) catch
                    return setTransportFailure(entry, .truncated),
            };
            entry.transport_status = .present;
        },
        1, 58 => {
            entry.transport_protocol = if (protocol == 1) .icmpv4 else .icmpv6;
            if (available < 4) return setTransportFailure(entry, .truncated);
            entry.icmp = .{
                .header_offset = offset,
                .kind = slotByte(slot, offset) catch
                    return setTransportFailure(entry, .truncated),
                .code = slotByte(slot, offset + 1) catch
                    return setTransportFailure(entry, .truncated),
            };
            entry.transport_status = .present;
        },
        59 => setTransportFailure(entry, .absent),
        else => setTransportFailure(entry, .unsupported),
    }
}

fn parseIpv4(slot: *const PacketSlot, entry: *ParsedPacket, offset: usize) void {
    entry.network_protocol = .ipv4;
    const available = slot.total_len - offset;
    if (available < 20) return setNetworkFailure(entry, .truncated);
    const version_ihl = slotByte(slot, offset) catch
        return setNetworkFailure(entry, .truncated);
    if (version_ihl >> 4 != 4) return setNetworkFailure(entry, .malformed);
    const header_len: usize = @as(usize, version_ihl & 0x0f) * 4;
    if (header_len < 20) return setNetworkFailure(entry, .malformed);
    if (header_len > available) return setNetworkFailure(entry, .truncated);
    const total_len = slotU16(slot, offset + 2) catch
        return setNetworkFailure(entry, .truncated);
    if (total_len < header_len) return setNetworkFailure(entry, .malformed);
    if (total_len > available) return setNetworkFailure(entry, .truncated);
    const fragment = slotU16(slot, offset + 6) catch
        return setNetworkFailure(entry, .truncated);
    var source: [4]u8 = undefined;
    var destination: [4]u8 = undefined;
    slotRead(slot, offset + 12, &source) catch
        return setNetworkFailure(entry, .truncated);
    slotRead(slot, offset + 16, &destination) catch
        return setNetworkFailure(entry, .truncated);
    entry.ipv4 = .{
        .header_offset = offset,
        .header_len = header_len,
        .total_len = total_len,
        .dscp = @truncate((slotByte(slot, offset + 1) catch
            return setNetworkFailure(entry, .truncated)) >> 2),
        .ttl = slotByte(slot, offset + 8) catch
            return setNetworkFailure(entry, .truncated),
        .protocol = slotByte(slot, offset + 9) catch
            return setNetworkFailure(entry, .truncated),
        .source = source,
        .destination = destination,
        .fragment_offset = @truncate(fragment & 0x1fff),
        .more_fragments = (fragment & 0x2000) != 0,
    };
    entry.network_status = .present;
    entry.non_initial_fragment = entry.ipv4.fragment_offset != 0;
    entry.incomplete_fragment = entry.non_initial_fragment or entry.ipv4.more_fragments;
    if (entry.non_initial_fragment) return setTransportFailure(entry, .absent);
    parseTransport(
        slot,
        entry,
        entry.ipv4.protocol,
        offset + header_len,
        @as(usize, total_len) - header_len,
    );
}

fn isIpv6Extension(next_header: u8) bool {
    return switch (next_header) {
        0, 43, 44, 51, 60 => true,
        else => false,
    };
}

fn parseIpv6(
    slot: *const PacketSlot,
    entry: *ParsedPacket,
    offset: usize,
    config: ParserConfig,
) void {
    entry.network_protocol = .ipv6;
    const available = slot.total_len - offset;
    if (available < 40) return setNetworkFailure(entry, .truncated);
    const first = slotByte(slot, offset) catch
        return setNetworkFailure(entry, .truncated);
    if (first >> 4 != 6) return setNetworkFailure(entry, .malformed);
    const payload_len = slotU16(slot, offset + 4) catch
        return setNetworkFailure(entry, .truncated);
    const total_len = std.math.add(usize, 40, payload_len) catch
        return setNetworkFailure(entry, .malformed);
    if (total_len > available) return setNetworkFailure(entry, .truncated);
    var source: [16]u8 = undefined;
    var destination: [16]u8 = undefined;
    slotRead(slot, offset + 8, &source) catch
        return setNetworkFailure(entry, .truncated);
    slotRead(slot, offset + 24, &destination) catch
        return setNetworkFailure(entry, .truncated);
    const second = slotByte(slot, offset + 1) catch
        return setNetworkFailure(entry, .truncated);
    entry.ipv6 = .{
        .header_offset = offset,
        .payload_len = payload_len,
        .traffic_class = (first & 0x0f) << 4 | (second >> 4),
        .hop_limit = slotByte(slot, offset + 7) catch
            return setNetworkFailure(entry, .truncated),
        .source = source,
        .destination = destination,
    };
    entry.network_status = .present;

    var next_header = slotByte(slot, offset + 6) catch
        return setNetworkFailure(entry, .truncated);
    var cursor = offset + 40;
    const payload_end = offset + total_len;
    var saw_fragment = false;
    while (isIpv6Extension(next_header)) {
        if (entry.ipv6.extension_headers == config.max_ipv6_extension_headers)
            return setTransportFailure(entry, .unsupported);
        if (cursor >= payload_end) return setTransportFailure(entry, .truncated);
        if (next_header == 0 and entry.ipv6.extension_headers != 0)
            return setTransportFailure(entry, .malformed);
        if (next_header == 44 and saw_fragment)
            return setTransportFailure(entry, .malformed);
        const following = slotByte(slot, cursor) catch
            return setTransportFailure(entry, .truncated);
        const extension_len: usize = if (next_header == 44)
            8
        else if (next_header == 51)
            (@as(usize, slotByte(slot, cursor + 1) catch
                return setTransportFailure(entry, .truncated)) + 2) * 4
        else
            (@as(usize, slotByte(slot, cursor + 1) catch
                return setTransportFailure(entry, .truncated)) + 1) * 8;
        const next_extension_bytes = std.math.add(
            usize,
            entry.ipv6.extension_bytes,
            extension_len,
        ) catch return setTransportFailure(entry, .malformed);
        if (next_extension_bytes > config.max_ipv6_extension_bytes)
            return setTransportFailure(entry, .unsupported);
        const extension_end = std.math.add(usize, cursor, extension_len) catch
            return setTransportFailure(entry, .malformed);
        if (extension_end > payload_end) return setTransportFailure(entry, .truncated);
        if (next_header == 44) {
            saw_fragment = true;
            const fragment = slotU16(slot, cursor + 2) catch
                return setTransportFailure(entry, .truncated);
            entry.ipv6.fragment_offset = @truncate(fragment >> 3);
            entry.ipv6.more_fragments = (fragment & 1) != 0;
            entry.non_initial_fragment = entry.ipv6.fragment_offset != 0;
            entry.incomplete_fragment = entry.non_initial_fragment or
                entry.ipv6.more_fragments;
        }
        entry.ipv6.extension_headers += 1;
        entry.ipv6.extension_bytes = @intCast(next_extension_bytes);
        next_header = following;
        cursor = extension_end;
        if (entry.non_initial_fragment) return setTransportFailure(entry, .absent);
    }
    if (next_header == 50) return setTransportFailure(entry, .unsupported);
    parseTransport(slot, entry, next_header, cursor, payload_end - cursor);
}

fn parseSlot(slot: *const PacketSlot, entry: *ParsedPacket, config: ParserConfig) void {
    entry.* = .{ .config = config };
    if (slot.total_len < 14) {
        entry.ethernet_status = .truncated;
        setNetworkFailure(entry, .absent);
        return;
    }
    slotRead(slot, 0, &entry.ethernet.destination) catch {
        entry.ethernet_status = .truncated;
        setNetworkFailure(entry, .absent);
        return;
    };
    slotRead(slot, 6, &entry.ethernet.source) catch {
        entry.ethernet_status = .truncated;
        setNetworkFailure(entry, .absent);
        return;
    };
    var ether_type = slotU16(slot, 12) catch {
        entry.ethernet_status = .truncated;
        setNetworkFailure(entry, .absent);
        return;
    };
    var cursor: usize = 14;
    while (isVlanEtherType(ether_type)) {
        if (entry.ethernet.vlan_count == 2) {
            entry.ethernet_status = .unsupported;
            setNetworkFailure(entry, .absent);
            return;
        }
        if (slot.total_len - cursor < 4) {
            entry.ethernet_status = .truncated;
            setNetworkFailure(entry, .absent);
            return;
        }
        entry.ethernet.vlan_tci[entry.ethernet.vlan_count] = slotU16(slot, cursor) catch {
            entry.ethernet_status = .truncated;
            setNetworkFailure(entry, .absent);
            return;
        };
        entry.ethernet.vlan_count += 1;
        ether_type = slotU16(slot, cursor + 2) catch {
            entry.ethernet_status = .truncated;
            setNetworkFailure(entry, .absent);
            return;
        };
        cursor += 4;
    }
    entry.ethernet.ether_type = ether_type;
    entry.ethernet.header_len = cursor;
    entry.ethernet_status = .present;
    switch (ether_type) {
        0x0800 => parseIpv4(slot, entry, cursor),
        0x86dd => parseIpv6(slot, entry, cursor, config),
        else => setNetworkFailure(entry, .absent),
    }
}

/// Address-stable allocation owning batch generations and copied slot metadata.
///
/// Construct once in adapter/worker setup, keep it alive across processing
/// calls, and destroy only after no handle will be accessed again. `begin`
/// allocates nothing and internally advances a generation that never resets.
/// Construction assigns a process-unique, monotonic non-pointer identity.
pub const PacketBatchOwner = opaque {
    /// Owner construction errors.
    pub const InitError = std.mem.Allocator.Error || OwnerIdentityError || EntropyError;

    /// Allocates one address-stable owner and a non-reusable identity.
    pub fn init(allocator: std.mem.Allocator) InitError!*PacketBatchOwner {
        const owner = try allocator.create(BatchOwnerImpl);
        errdefer allocator.destroy(owner);
        const identity = try allocateOwnerIdentity(&owner_identity_counter);
        var raw_capability_secret: [32]u8 = undefined;
        try fillSecureRandom(&raw_capability_secret);
        owner.* = .{
            .allocator = allocator,
            .owner_identity = identity,
            .raw_capability_secret = raw_capability_secret,
        };
        return @ptrCast(owner);
    }

    /// Releases owner metadata after all batch/view handles are unreachable.
    pub fn deinit(self: *PacketBatchOwner) void {
        const owner = ownerImpl(self);
        const allocator = owner.allocator;
        @memset(&owner.raw_capability_secret, 0);
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
        @memset(&owner.slot_access, .unavailable);
        @memset(owner.slot_access[0..slots.len], .batch_owned);
        @memset(&owner.nonrevocable_access_issued, false);
        for (owner.parse_cache[0..slots.len], owner.journals[0..slots.len]) |*entry, *journal| {
            entry.* = .{};
            journal.* = .{};
        }
        @memset(owner.raw_capability_authorities[0..], .{});
        owner.mutation_attempts = 0;
        owner.disposition = .{};
        return @enumFromInt(encodeHandle(
            owner.owner_identity,
            owner.live_generation,
        ));
    }

    /// Injects one deterministic pre-write mutation failure for tests.
    pub fn injectMutationFailure(self: *PacketBatchOwner, attempt: ?usize) void {
        const owner = ownerImpl(self);
        owner.mutation_fail_after = attempt;
        owner.mutation_attempts = 0;
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
        AccessRevoked,
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
        try ensureSlotBatchAccess(owner, index);
        const tag = (batchGeneration(self) << view_index_bits) | @as(u8, @intCast(index));
        return @enumFromInt(encodeHandle(owner.owner_identity, tag));
    }

    /// Creates a structured owner-bound editor for one mutable packet slot.
    pub fn editor(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) Error!PacketEditor {
        return @enumFromInt(@intFromEnum(try self.view(owner_handle, index)));
    }

    /// Mints the explicitly unsafe raw editor used by trusted assembly/tests.
    ///
    /// SAFETY: the caller owns the live batch generation and adapter token;
    /// descriptor alignment/bounds were validated at receive, writes are
    /// owner-thread-only, and every raw write declares invalidated layers or
    /// requests full software validation before output.
    pub fn unsafeRawEditorForTesting(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) Error!RawPacketEditor {
        const owner = try self.ensureLive(owner_handle);
        try ensureSlotBatchAccess(owner, index);
        for (0..raw_capability_derivation_attempts) |_| {
            if (owner.raw_capability_mint_counter == std.math.maxInt(u64))
                return error.GenerationExhausted;
            owner.raw_capability_mint_counter += 1;
            const token = deriveRawCapabilityToken(owner, owner.raw_capability_mint_counter);
            if (!rawCapabilityTokenAvailable(owner, token)) continue;
            owner.raw_capability_authorities[index] = .{
                .token = token,
                .batch_generation = batchGeneration(self),
            };
            return @enumFromInt(encodeHandle(owner.owner_identity, token));
        }
        return error.GenerationExhausted;
    }

    /// Mints a checked output handle without exposing owner slot storage.
    pub fn outputPacket(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) Error!OutputPacket {
        const owner = try self.ensureLive(owner_handle);
        try ensureSlotBatchAccess(owner, index);
        const tag = (batchGeneration(self) << view_index_bits) | @as(u8, @intCast(index));
        return @enumFromInt(encodeHandle(owner.owner_identity, tag));
    }

    /// Returns a mutation-journal snapshot for deterministic observations.
    pub fn mutationJournal(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) Error!MutationJournal {
        const owner = try self.ensureLive(owner_handle);
        try ensureSlotBatchAccess(owner, index);
        return owner.journals[index];
    }

    /// Rejects invalid, failed, or unfinalized mutation before adapter output.
    pub fn validateForOutput(
        self: PacketBatch,
        owner_handle: *PacketBatchOwner,
        index: usize,
    ) (Error || OutputValidationError)!void {
        const owner = try self.ensureLive(owner_handle);
        try ensureSlotBatchAccess(owner, index);
        const journal = owner.journals[index];
        if (journal.invalid or journal.edit_failed) return error.InvalidMutation;
        if (journal.needsFinalize() and !journal.finalized) return error.UnfinalizedMutation;
        var parsed = ParsedPacket{};
        parseSlot(&owner.slots[index], &parsed, .{});
        if (parsed.network_protocol == .ipv6 and parsed.transport_protocol == .udp and
            parsed.transport_status == .present and parsed.udp.checksum == 0)
            return error.InvalidIpv6UdpZero;
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

/// Opaque adapter-output handle for one owner-controlled packet generation.
///
/// Every operation revalidates owner identity, generation, slot index, and
/// current batch access. Methods returning a raw segment slice or adapter token
/// make retention fail for that slot until the generation ends because those
/// returned values cannot themselves be revoked.
pub const OutputPacket = enum(HandleInt) {
    _,

    fn asView(self: OutputPacket) PacketView {
        return @enumFromInt(@intFromEnum(self));
    }

    /// Returns the current packet length after complete access validation.
    pub fn length(self: OutputPacket, owner: *PacketBatchOwner) ViewError!usize {
        return (try ensureViewLive(owner, self.asView())).total_len;
    }

    /// Returns the current segment count after complete access validation.
    pub fn segmentCount(self: OutputPacket, owner: *PacketBatchOwner) ViewError!usize {
        return (try ensureViewLive(owner, self.asView())).segment_count;
    }

    /// Returns one checked adapter segment and records an escaping raw borrow.
    pub fn adapterSegment(
        self: OutputPacket,
        owner: *PacketBatchOwner,
        index: usize,
    ) ViewError![]const u8 {
        const view = self.asView();
        const slot = try ensureViewLive(owner, view);
        if (index >= slot.segment_count) return error.Bounds;
        markNonrevocableAccess(owner, viewIndex(view));
        if (slot.instrumentation) |instrumentation|
            instrumentation.recordSegmentBorrow();
        const segment = slot.segment_storage[index];
        return segment.bytes[0..segment.declared_len];
    }

    /// Returns the adapter token and records escaping raw token authority.
    pub fn adapterToken(
        self: OutputPacket,
        owner: *PacketBatchOwner,
    ) ViewError!AdapterToken {
        const view = self.asView();
        const slot = try ensureViewLive(owner, view);
        markNonrevocableAccess(owner, viewIndex(view));
        return slot.token;
    }

    /// Records one checked allocation-free output submission attempt.
    pub fn recordSubmit(self: OutputPacket, owner: *PacketBatchOwner) ViewError!void {
        const slot = try ensureViewLive(owner, self.asView());
        if (slot.instrumentation) |instrumentation|
            instrumentation.recordSubmit();
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
                if (range.len <= segment.declared_len - local) {
                    markNonrevocableAccess(owner, viewIndex(self));
                    return segment.bytes[local .. local + range.len];
                }
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

    /// Lazily parses and caches bounded Ethernet/L3/L4 metadata, returning an
    /// owned snapshot that cannot expose cache storage across generations.
    pub fn parse(
        self: PacketView,
        owner_handle: *PacketBatchOwner,
        config: ParserConfig,
    ) (ViewError || ParserConfig.Error)!ParsedPacket {
        try config.validate();
        const slot = try ensureViewLive(owner_handle, self);
        const owner = ownerImpl(owner_handle);
        const index = viewIndex(self);
        const entry = &owner.parse_cache[index];
        if (entry.ethernet_status == .unparsed or !entry.config.eql(config))
            parseSlot(slot, entry, config);
        return entry.*;
    }
};

/// Structured mutation failures. Any failure after editor validation marks the
/// packet journal invalid so output must follow an explicit caller policy.
pub const MutationError = ViewError || ParserConfig.Error || error{
    InvalidRawCapability,
    ReadOnly,
    UnsupportedProtocol,
    IncompleteFragment,
    ResizeRequiresLinear,
    InsufficientHeadroom,
    InsufficientTailroom,
    LengthOverflow,
    MissingInvalidationDeclaration,
    InjectedFailure,
};

const EditorContext = struct {
    owner: *BatchOwnerImpl,
    index: usize,
    slot: *PacketSlot,
    journal: *MutationJournal,
};

fn editorContext(
    raw: HandleInt,
    owner_handle: *PacketBatchOwner,
) ViewError!EditorContext {
    const view: PacketView = @enumFromInt(raw);
    _ = try ensureViewLive(owner_handle, view);
    const owner = ownerImpl(owner_handle);
    const index = viewIndex(view);
    return .{
        .owner = owner,
        .index = index,
        .slot = &owner.slots[index],
        .journal = &owner.journals[index],
    };
}

fn rawEditorContext(
    raw: HandleInt,
    owner_handle: *PacketBatchOwner,
) MutationError!EditorContext {
    const owner = ownerImpl(owner_handle);
    const identity = handleOwnerIdentity(raw);
    const token = handleLocalTag(raw);
    const domain: u8 = @truncate(token);
    if (identity == 0 or identity != owner.owner_identity or
        owner.live_generation == 0 or token == 0 or
        (domain & 0xc0) != raw_capability_domain)
        return error.InvalidRawCapability;

    var matched_index: ?usize = null;
    for (owner.raw_capability_authorities[0..owner.slot_count], 0..) |authority, index| {
        if (authority.token == token and authority.batch_generation == owner.live_generation) {
            if (matched_index != null) return error.InvalidRawCapability;
            matched_index = index;
        }
    }
    const index = matched_index orelse return error.InvalidRawCapability;
    if (owner.slot_access[index] != .batch_owned)
        return error.InvalidRawCapability;

    return .{
        .owner = owner,
        .index = index,
        .slot = &owner.slots[index],
        .journal = &owner.journals[index],
    };
}

fn markMutationFailure(context: EditorContext) void {
    context.journal.invalid = true;
    context.journal.edit_failed = true;
    context.journal.finalized = false;
}

fn beginMutationAttempt(context: EditorContext) MutationError!void {
    const attempt = context.owner.mutation_attempts;
    context.owner.mutation_attempts += 1;
    if (context.owner.mutation_fail_after == attempt) {
        markMutationFailure(context);
        return error.InjectedFailure;
    }
}

fn validateWritable(slot: *const PacketSlot, range: ByteRange) MutationError!void {
    const end = range.end() catch return error.Overflow;
    if (end > slot.total_len) return error.Bounds;
    if (range.len == 0) return;
    var segment_start: usize = 0;
    var covered: usize = 0;
    for (slot.segment_storage[0..slot.segment_count], 0..) |segment, index| {
        const segment_end = std.math.add(usize, segment_start, segment.declared_len) catch
            return error.Overflow;
        const overlap_start = @max(range.offset, segment_start);
        const overlap_end = @min(end, segment_end);
        if (overlap_start < overlap_end) {
            const mutable = slot.mutable_storage[index] orelse return error.ReadOnly;
            if (!mutable.capabilities.same_length) return error.ReadOnly;
            covered += overlap_end - overlap_start;
        }
        segment_start = segment_end;
    }
    if (covered != range.len) return error.Bounds;
}

fn writeSlotUnchecked(slot: *PacketSlot, offset: usize, source: []const u8) void {
    var remaining = source.len;
    var packet_offset = offset;
    var source_offset: usize = 0;
    var segment_start: usize = 0;
    for (slot.segment_storage[0..slot.segment_count], 0..) |segment, index| {
        const segment_end = segment_start + segment.declared_len;
        if (packet_offset < segment_end and remaining != 0) {
            const local = if (packet_offset > segment_start) packet_offset - segment_start else 0;
            const amount = @min(remaining, segment.declared_len - local);
            const mutable = slot.mutable_storage[index].?;
            const active = mutable.active();
            @memcpy(active[local .. local + amount], source[source_offset .. source_offset + amount]);
            remaining -= amount;
            source_offset += amount;
            packet_offset += amount;
        }
        segment_start = segment_end;
    }
    std.debug.assert(remaining == 0);
}

fn invalidateParseCache(context: EditorContext) void {
    context.owner.parse_cache[context.index] = .{};
    context.journal.cache_invalidated = true;
}

fn recordMutation(
    context: EditorContext,
    dirty: DirtyLayers,
    checksums: ChecksumDependencies,
) void {
    context.journal.dirty.l2 = context.journal.dirty.l2 or dirty.l2;
    context.journal.dirty.l3 = context.journal.dirty.l3 or dirty.l3;
    context.journal.dirty.l4 = context.journal.dirty.l4 or dirty.l4;
    context.journal.checksums.ipv4_header = context.journal.checksums.ipv4_header or
        checksums.ipv4_header;
    context.journal.checksums.transport = context.journal.checksums.transport or
        checksums.transport;
    context.journal.checksums.pseudo_header = context.journal.checksums.pseudo_header or
        checksums.pseudo_header;
    context.journal.finalized = false;
    context.journal.offload_eligible = false;
    invalidateParseCache(context);
}

fn checkedWrite(
    context: EditorContext,
    offset: usize,
    source: []const u8,
    dirty: DirtyLayers,
    checksums: ChecksumDependencies,
) MutationError!void {
    try beginMutationAttempt(context);
    validateWritable(context.slot, .{ .offset = offset, .len = source.len }) catch |write_error| {
        markMutationFailure(context);
        return write_error;
    };
    writeSlotUnchecked(context.slot, offset, source);
    recordMutation(context, dirty, checksums);
}

fn currentParsed(context: EditorContext) MutationError!ParsedPacket {
    const view: PacketView = @enumFromInt(encodeHandle(
        context.owner.owner_identity,
        (context.owner.live_generation << view_index_bits) | @as(u8, @intCast(context.index)),
    ));
    return view.parse(@ptrCast(context.owner), .{});
}

fn expectIpv4(context: EditorContext) MutationError!ParsedPacket {
    const parsed = try currentParsed(context);
    if (parsed.network_status != .present or parsed.network_protocol != .ipv4) {
        markMutationFailure(context);
        return error.UnsupportedProtocol;
    }
    return parsed;
}

fn expectIpv6(context: EditorContext) MutationError!ParsedPacket {
    const parsed = try currentParsed(context);
    if (parsed.network_status != .present or parsed.network_protocol != .ipv6) {
        markMutationFailure(context);
        return error.UnsupportedProtocol;
    }
    return parsed;
}

fn expectTransport(
    context: EditorContext,
    protocol: TransportProtocol,
) MutationError!ParsedPacket {
    const parsed = try currentParsed(context);
    if (parsed.incomplete_fragment) {
        markMutationFailure(context);
        return error.IncompleteFragment;
    }
    if (parsed.transport_status != .present or parsed.transport_protocol != protocol) {
        markMutationFailure(context);
        return error.UnsupportedProtocol;
    }
    return parsed;
}

fn checkedLengthDelta(current: i32, delta: i64) MutationError!i32 {
    const next = std.math.add(i64, current, delta) catch return error.LengthOverflow;
    return std.math.cast(i32, next) orelse error.LengthOverflow;
}

fn resizeLinear(
    context: EditorContext,
    operation: enum { prepend, append, trim_head, trim_tail },
    bytes: []const u8,
    trim_len: usize,
) MutationError!void {
    try beginMutationAttempt(context);
    if (context.slot.segment_count != 1) {
        markMutationFailure(context);
        return error.ResizeRequiresLinear;
    }
    const descriptor = if (context.slot.mutable_storage[0]) |*mutable|
        mutable
    else {
        markMutationFailure(context);
        return error.ReadOnly;
    };
    if (!descriptor.capabilities.resize) {
        markMutationFailure(context);
        return error.ResizeRequiresLinear;
    }
    const amount = if (operation == .prepend or operation == .append) bytes.len else trim_len;
    if ((operation == .trim_head or operation == .trim_tail) and amount > descriptor.active_len) {
        markMutationFailure(context);
        return error.Bounds;
    }
    const delta: i64 = if (operation == .prepend or operation == .append)
        std.math.cast(i64, amount) orelse {
            markMutationFailure(context);
            return error.LengthOverflow;
        }
    else
        -(std.math.cast(i64, amount) orelse {
            markMutationFailure(context);
            return error.LengthOverflow;
        });
    const next_total = if (delta >= 0)
        std.math.add(usize, context.slot.total_len, amount) catch {
            markMutationFailure(context);
            return error.LengthOverflow;
        }
    else
        context.slot.total_len - amount;
    const next_delta = checkedLengthDelta(context.journal.signed_length_delta, delta) catch |length_error| {
        markMutationFailure(context);
        return length_error;
    };
    const is_tail_operation = operation == .append or operation == .trim_tail;
    const next_tail_delta = if (is_tail_operation)
        checkedLengthDelta(context.journal.tail_length_delta, delta) catch |length_error| {
            markMutationFailure(context);
            return length_error;
        }
    else
        context.journal.tail_length_delta;
    switch (operation) {
        .prepend => {
            if (amount > descriptor.headroom) {
                markMutationFailure(context);
                return error.InsufficientHeadroom;
            }
        },
        .append => {
            if (amount > descriptor.tailroom) {
                markMutationFailure(context);
                return error.InsufficientTailroom;
            }
        },
        .trim_head, .trim_tail => {},
    }

    const pre_tail_parsed = if (is_tail_operation and !context.journal.has_pre_tail_resize)
        currentParsed(context) catch |parse_error| {
            markMutationFailure(context);
            return parse_error;
        }
    else
        null;

    // All fallible validation precedes the first descriptor or byte change.
    if (pre_tail_parsed) |parsed| {
        context.journal.pre_tail_resize_parsed = parsed;
        context.journal.pre_tail_resize_frame_len = context.slot.total_len;
        context.journal.has_pre_tail_resize = true;
    }
    switch (operation) {
        .prepend => {
            descriptor.active_offset -= amount;
            descriptor.active_len += amount;
            descriptor.headroom -= amount;
            @memcpy(descriptor.storage[descriptor.active_offset .. descriptor.active_offset + amount], bytes);
        },
        .append => {
            const destination = descriptor.active_offset + descriptor.active_len;
            @memcpy(descriptor.storage[destination .. destination + amount], bytes);
            descriptor.active_len += amount;
            descriptor.tailroom -= amount;
        },
        .trim_head => {
            descriptor.active_offset += amount;
            descriptor.active_len -= amount;
            descriptor.headroom += amount;
        },
        .trim_tail => {
            descriptor.active_len -= amount;
            descriptor.tailroom += amount;
        },
    }
    context.slot.total_len = next_total;
    context.slot.refreshMutableSegment(0);
    context.journal.signed_length_delta = next_delta;
    context.journal.tail_length_delta = next_tail_delta;
    recordMutation(context, .{ .l2 = true, .l3 = true, .l4 = true }, .{
        .ipv4_header = true,
        .transport = true,
        .pseudo_header = true,
    });
}

/// Software finalization and output-readiness failures.
pub const FinalizeError = MutationError || error{
    InvalidJournal,
    InvalidPacket,
    InvalidIpv6UdpZero,
    PacketTooLarge,
};

const ProtocolExtents = struct {
    network_offset: usize,
    network_header_len: usize,
    network_len: usize,
    transport_offset: usize = 0,
    transport_header_len: usize = 0,
    transport_len: usize = 0,
};

fn declaredProtocolExtents(
    parsed: *const ParsedPacket,
    frame_len: usize,
) error{ InvalidPacket, PacketTooLarge }!ProtocolExtents {
    if (parsed.ethernet_status != .present or parsed.network_status != .present)
        return error.InvalidPacket;
    const network_offset, const network_header_len, const network_len = switch (parsed.network_protocol) {
        .ipv4 => .{
            parsed.ipv4.header_offset,
            parsed.ipv4.header_len,
            @as(usize, parsed.ipv4.total_len),
        },
        .ipv6 => .{
            parsed.ipv6.header_offset,
            @as(usize, 40),
            std.math.add(usize, 40, parsed.ipv6.payload_len) catch
                return error.PacketTooLarge,
        },
        .none => return error.InvalidPacket,
    };
    if (network_len < network_header_len) return error.InvalidPacket;
    const network_end = std.math.add(usize, network_offset, network_len) catch
        return error.PacketTooLarge;
    if (network_end > frame_len) return error.InvalidPacket;

    var result = ProtocolExtents{
        .network_offset = network_offset,
        .network_header_len = network_header_len,
        .network_len = network_len,
    };
    if (parsed.transport_status != .present or
        (parsed.transport_protocol != .tcp and parsed.transport_protocol != .udp))
        return result;
    result.transport_offset = if (parsed.transport_protocol == .tcp)
        parsed.tcp.header_offset
    else
        parsed.udp.header_offset;
    const network_payload_start = std.math.add(usize, network_offset, network_header_len) catch
        return error.PacketTooLarge;
    if (result.transport_offset < network_payload_start or result.transport_offset > network_end)
        return error.InvalidPacket;
    result.transport_len = if (parsed.transport_protocol == .udp)
        parsed.udp.length
    else
        network_end - result.transport_offset;
    const minimum_transport_len: usize = if (parsed.transport_protocol == .udp)
        8
    else
        parsed.tcp.header_len;
    result.transport_header_len = minimum_transport_len;
    if (result.transport_len < minimum_transport_len) return error.InvalidPacket;
    const transport_end = std.math.add(
        usize,
        result.transport_offset,
        result.transport_len,
    ) catch return error.PacketTooLarge;
    if (transport_end > network_end) return error.InvalidPacket;
    return result;
}

fn tailResizedProtocolExtents(
    base: ProtocolExtents,
    base_frame_len: usize,
    current_frame_len: usize,
    tail_delta: i32,
    protocol: TransportProtocol,
) error{ InvalidPacket, PacketTooLarge }!ProtocolExtents {
    const expected_frame_len = if (tail_delta >= 0)
        std.math.add(usize, base_frame_len, @intCast(tail_delta)) catch
            return error.PacketTooLarge
    else
        std.math.sub(usize, base_frame_len, @intCast(-@as(i64, tail_delta))) catch
            return error.InvalidPacket;
    if (expected_frame_len != current_frame_len) return error.InvalidPacket;
    const base_network_end = std.math.add(usize, base.network_offset, base.network_len) catch
        return error.PacketTooLarge;
    var network_end = base_network_end;
    if (tail_delta > 0 and base_network_end == base_frame_len)
        network_end = current_frame_len;
    if (tail_delta < 0 and current_frame_len < network_end)
        network_end = current_frame_len;
    const network_header_end = std.math.add(
        usize,
        base.network_offset,
        base.network_header_len,
    ) catch return error.PacketTooLarge;
    if (network_end < network_header_end) return error.InvalidPacket;

    var result = base;
    result.network_len = network_end - base.network_offset;
    if (base.transport_len == 0) return result;
    const base_transport_end = std.math.add(
        usize,
        base.transport_offset,
        base.transport_len,
    ) catch return error.PacketTooLarge;
    var transport_end = base_transport_end;
    if (tail_delta > 0 and base_transport_end == base_network_end and
        base_network_end == base_frame_len)
        transport_end = network_end;
    if (tail_delta < 0 and network_end < transport_end)
        transport_end = network_end;
    if (transport_end < base.transport_offset) return error.InvalidPacket;
    result.transport_len = transport_end - base.transport_offset;
    const minimum_transport_len: usize = if (protocol == .udp) 8 else base.transport_header_len;
    if (result.transport_len < minimum_transport_len) return error.InvalidPacket;
    return result;
}

/// Packet conditions that are never eligible for output submission.
pub const OutputValidationError = error{
    InvalidMutation,
    UnfinalizedMutation,
    InvalidIpv6UdpZero,
};

fn addChecksumWord(sum: *u64, value: u16) void {
    sum.* += value;
}

fn foldChecksum(sum_value: u64) u16 {
    var sum = sum_value;
    while ((sum >> 16) != 0) sum = (sum & 0xffff) + (sum >> 16);
    return ~@as(u16, @truncate(sum));
}

fn checksumRangeWithOverrides(
    slot: *const PacketSlot,
    offset: usize,
    length: usize,
    zero_offset: ?usize,
    total_override_offset: ?usize,
    total_override: u16,
) ViewError!u64 {
    var sum: u64 = 0;
    var local: usize = 0;
    while (local < length) : (local += 2) {
        const absolute = offset + local;
        const high: u8 = if (zero_offset != null and absolute == zero_offset.?)
            0
        else if (total_override_offset != null and absolute == total_override_offset.?)
            @truncate(total_override >> 8)
        else
            try slotByte(slot, absolute);
        const low: u8 = if (local + 1 == length)
            0
        else if (zero_offset != null and absolute + 1 == zero_offset.? + 1)
            0
        else if (total_override_offset != null and absolute + 1 == total_override_offset.? + 1)
            @truncate(total_override)
        else
            try slotByte(slot, absolute + 1);
        addChecksumWord(&sum, (@as(u16, high) << 8) | low);
    }
    return sum;
}

fn transportChecksum(
    slot: *const PacketSlot,
    parsed: *const ParsedPacket,
    transport_offset: usize,
    transport_len: u16,
) ViewError!u16 {
    var sum: u64 = 0;
    const protocol: u8 = switch (parsed.transport_protocol) {
        .tcp => 6,
        .udp => 17,
        else => return error.Bounds,
    };
    switch (parsed.network_protocol) {
        .ipv4 => {
            sum += try checksumRangeWithOverrides(
                slot,
                parsed.ipv4.header_offset + 12,
                8,
                null,
                null,
                0,
            );
            addChecksumWord(&sum, protocol);
            addChecksumWord(&sum, transport_len);
        },
        .ipv6 => {
            sum += try checksumRangeWithOverrides(
                slot,
                parsed.ipv6.header_offset + 8,
                32,
                null,
                null,
                0,
            );
            addChecksumWord(&sum, 0);
            addChecksumWord(&sum, transport_len);
            addChecksumWord(&sum, 0);
            addChecksumWord(&sum, protocol);
        },
        .none => return error.Bounds,
    }
    const checksum_offset = transport_offset + @as(usize, if (parsed.transport_protocol == .udp) 6 else 16);
    const udp_length_offset = if (parsed.transport_protocol == .udp)
        transport_offset + 4
    else
        null;
    sum += try checksumRangeWithOverrides(
        slot,
        transport_offset,
        transport_len,
        checksum_offset,
        udp_length_offset,
        transport_len,
    );
    const result = foldChecksum(sum);
    return if (result == 0) 0xffff else result;
}

fn writeU16Unchecked(slot: *PacketSlot, offset: usize, value: u16) void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .big);
    writeSlotUnchecked(slot, offset, &bytes);
}

const PendingHeaderWrite = struct {
    offset: usize,
    before: u16,
    after: u16,
};

fn prepareHeaderWrite(
    context: EditorContext,
    writes: *[4]PendingHeaderWrite,
    write_count: *usize,
    offset: usize,
    value: u16,
) FinalizeError!void {
    if (write_count.* == writes.len) return error.InvalidPacket;
    try validateWritable(context.slot, .{ .offset = offset, .len = 2 });
    writes[write_count.*] = .{
        .offset = offset,
        .before = try slotU16(context.slot, offset),
        .after = value,
    };
    write_count.* += 1;
}

fn restoreHeaderWrites(slot: *PacketSlot, writes: []const PendingHeaderWrite) void {
    for (writes) |write| writeU16Unchecked(slot, write.offset, write.before);
}

fn finalizeContext(context: EditorContext) FinalizeError!void {
    if (context.journal.invalid or context.journal.edit_failed)
        return error.InvalidJournal;
    if (!context.journal.needsFinalize()) {
        context.journal.finalized = true;
        return;
    }
    if (context.journal.tail_length_delta != 0 and
        (!context.journal.has_pre_tail_resize or
            context.journal.tail_length_delta != context.journal.signed_length_delta))
    {
        markMutationFailure(context);
        return error.InvalidPacket;
    }
    const parsed = if (context.journal.tail_length_delta != 0)
        context.journal.pre_tail_resize_parsed
    else
        try currentParsed(context);
    const base_frame_len = if (context.journal.tail_length_delta != 0)
        context.journal.pre_tail_resize_frame_len
    else
        context.slot.total_len;
    if (context.journal.checksums.transport and parsed.incomplete_fragment) {
        markMutationFailure(context);
        return error.IncompleteFragment;
    }
    const declared_extents = declaredProtocolExtents(&parsed, base_frame_len) catch |extent_error| {
        markMutationFailure(context);
        return extent_error;
    };
    const extents = if (context.journal.tail_length_delta != 0)
        tailResizedProtocolExtents(
            declared_extents,
            base_frame_len,
            context.slot.total_len,
            context.journal.tail_length_delta,
            parsed.transport_protocol,
        ) catch |extent_error| {
            markMutationFailure(context);
            return extent_error;
        }
    else
        declared_extents;
    const network_offset = extents.network_offset;
    const network_len_u16 = std.math.cast(u16, extents.network_len) orelse {
        markMutationFailure(context);
        return error.PacketTooLarge;
    };
    const transport_offset = extents.transport_offset;
    var transport_len: u16 = 0;
    if (parsed.transport_status == .present and
        (parsed.transport_protocol == .tcp or parsed.transport_protocol == .udp))
    {
        transport_len = std.math.cast(u16, extents.transport_len) orelse {
            markMutationFailure(context);
            return error.PacketTooLarge;
        };
    } else if (context.journal.checksums.transport) {
        markMutationFailure(context);
        return error.InvalidPacket;
    }

    const network_length_changed = extents.network_len != declared_extents.network_len;
    const transport_length_changed = extents.transport_len != declared_extents.transport_len;
    const must_ipv4_checksum = parsed.network_protocol == .ipv4 and
        (context.journal.checksums.ipv4_header or network_length_changed);
    const must_transport_checksum = transport_len != 0 and
        (context.journal.checksums.transport or
            transport_length_changed or
            (parsed.network_protocol == .ipv6 and parsed.transport_protocol == .udp));

    var ipv4_checksum: u16 = 0;
    if (must_ipv4_checksum) {
        const ipv4_total = network_len_u16;
        const sum = checksumRangeWithOverrides(
            context.slot,
            network_offset,
            parsed.ipv4.header_len,
            network_offset + 10,
            network_offset + 2,
            ipv4_total,
        ) catch {
            markMutationFailure(context);
            return error.InvalidPacket;
        };
        ipv4_checksum = foldChecksum(sum);
    }
    var transport_checksum_value: u16 = 0;
    if (must_transport_checksum) {
        transport_checksum_value = transportChecksum(
            context.slot,
            &parsed,
            transport_offset,
            transport_len,
        ) catch {
            markMutationFailure(context);
            return error.InvalidPacket;
        };
    }

    var writes: [4]PendingHeaderWrite = undefined;
    var write_count: usize = 0;
    if (network_length_changed) switch (parsed.network_protocol) {
        .ipv4 => prepareHeaderWrite(
            context,
            &writes,
            &write_count,
            network_offset + 2,
            network_len_u16,
        ) catch |write_error| {
            markMutationFailure(context);
            return write_error;
        },
        .ipv6 => {
            if (network_len_u16 < 40) {
                markMutationFailure(context);
                return error.InvalidPacket;
            }
            prepareHeaderWrite(
                context,
                &writes,
                &write_count,
                network_offset + 4,
                network_len_u16 - 40,
            ) catch |write_error| {
                markMutationFailure(context);
                return write_error;
            };
        },
        .none => unreachable,
    };
    if (parsed.transport_protocol == .udp and transport_length_changed)
        prepareHeaderWrite(
            context,
            &writes,
            &write_count,
            transport_offset + 4,
            transport_len,
        ) catch |write_error| {
            markMutationFailure(context);
            return write_error;
        };
    if (must_ipv4_checksum)
        prepareHeaderWrite(
            context,
            &writes,
            &write_count,
            network_offset + 10,
            ipv4_checksum,
        ) catch |write_error| {
            markMutationFailure(context);
            return write_error;
        };
    if (must_transport_checksum) {
        const checksum_offset = transport_offset + @as(usize, if (parsed.transport_protocol == .udp) 6 else 16);
        prepareHeaderWrite(
            context,
            &writes,
            &write_count,
            checksum_offset,
            transport_checksum_value,
        ) catch |write_error| {
            markMutationFailure(context);
            return write_error;
        };
    }
    // Every extent, checksum, target, and rollback value is ready before writes.
    for (writes[0..write_count]) |write|
        writeU16Unchecked(context.slot, write.offset, write.after);
    context.owner.parse_cache[context.index] = .{};
    const reparsed = currentParsed(context) catch {
        restoreHeaderWrites(context.slot, writes[0..write_count]);
        context.owner.parse_cache[context.index] = .{};
        markMutationFailure(context);
        return error.InvalidPacket;
    };
    if (reparsed.ethernet_status != .present or reparsed.network_status != .present or
        (parsed.transport_status == .present and reparsed.transport_status != .present))
    {
        restoreHeaderWrites(context.slot, writes[0..write_count]);
        context.owner.parse_cache[context.index] = .{};
        markMutationFailure(context);
        return error.InvalidPacket;
    }
    if (reparsed.network_protocol == .ipv6 and reparsed.transport_protocol == .udp and
        reparsed.udp.checksum == 0)
    {
        restoreHeaderWrites(context.slot, writes[0..write_count]);
        context.owner.parse_cache[context.index] = .{};
        markMutationFailure(context);
        return error.InvalidIpv6UdpZero;
    }
    context.journal.finalized = true;
    context.journal.invalid = false;
}

/// Owner/generation-bound structured editor.
pub const PacketEditor = enum(HandleInt) {
    _,

    fn context(self: PacketEditor, owner: *PacketBatchOwner) ViewError!EditorContext {
        return editorContext(@intFromEnum(self), owner);
    }

    /// Rewrites Ethernet destination across mutable segments.
    pub fn setEthernetDestination(self: PacketEditor, owner: *PacketBatchOwner, value: [6]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try currentParsed(context_value);
        if (parsed.ethernet_status != .present) {
            markMutationFailure(context_value);
            return error.UnsupportedProtocol;
        }
        try checkedWrite(context_value, 0, &value, .{ .l2 = true }, .{});
    }

    /// Rewrites Ethernet source across mutable segments.
    pub fn setEthernetSource(self: PacketEditor, owner: *PacketBatchOwner, value: [6]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try currentParsed(context_value);
        if (parsed.ethernet_status != .present) {
            markMutationFailure(context_value);
            return error.UnsupportedProtocol;
        }
        try checkedWrite(context_value, 6, &value, .{ .l2 = true }, .{});
    }

    /// Rewrites IPv4 DSCP while preserving ECN bits.
    pub fn setIpv4Dscp(self: PacketEditor, owner: *PacketBatchOwner, value: u6) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv4(context_value);
        const offset = parsed.ipv4.header_offset + 1;
        const current = try slotByte(context_value.slot, offset);
        const byte = [_]u8{(@as(u8, value) << 2) | (current & 0x03)};
        try checkedWrite(context_value, offset, &byte, .{ .l3 = true }, .{ .ipv4_header = true });
    }

    /// Rewrites IPv4 TTL.
    pub fn setIpv4Ttl(self: PacketEditor, owner: *PacketBatchOwner, value: u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv4(context_value);
        try checkedWrite(context_value, parsed.ipv4.header_offset + 8, &.{value}, .{ .l3 = true }, .{ .ipv4_header = true });
    }

    /// Rewrites IPv4 source and records pseudo-header dependency.
    pub fn setIpv4Source(self: PacketEditor, owner: *PacketBatchOwner, value: [4]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv4(context_value);
        try checkedWrite(context_value, parsed.ipv4.header_offset + 12, &value, .{ .l3 = true }, .{
            .ipv4_header = true,
            .transport = true,
            .pseudo_header = true,
        });
    }

    /// Rewrites IPv4 destination and records pseudo-header dependency.
    pub fn setIpv4Destination(self: PacketEditor, owner: *PacketBatchOwner, value: [4]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv4(context_value);
        try checkedWrite(context_value, parsed.ipv4.header_offset + 16, &value, .{ .l3 = true }, .{
            .ipv4_header = true,
            .transport = true,
            .pseudo_header = true,
        });
    }

    /// Rewrites IPv6 traffic class while preserving version and flow label.
    pub fn setIpv6TrafficClass(self: PacketEditor, owner: *PacketBatchOwner, value: u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv6(context_value);
        const offset = parsed.ipv6.header_offset;
        const first = try slotByte(context_value.slot, offset);
        const second = try slotByte(context_value.slot, offset + 1);
        const bytes = [_]u8{ (first & 0xf0) | (value >> 4), (value << 4) | (second & 0x0f) };
        try checkedWrite(context_value, offset, &bytes, .{ .l3 = true }, .{});
    }

    /// Rewrites IPv6 hop limit.
    pub fn setIpv6HopLimit(self: PacketEditor, owner: *PacketBatchOwner, value: u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv6(context_value);
        try checkedWrite(context_value, parsed.ipv6.header_offset + 7, &.{value}, .{ .l3 = true }, .{});
    }

    /// Rewrites IPv6 source and records pseudo-header dependency.
    pub fn setIpv6Source(self: PacketEditor, owner: *PacketBatchOwner, value: [16]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv6(context_value);
        try checkedWrite(context_value, parsed.ipv6.header_offset + 8, &value, .{ .l3 = true }, .{
            .transport = true,
            .pseudo_header = true,
        });
    }

    /// Rewrites IPv6 destination and records pseudo-header dependency.
    pub fn setIpv6Destination(self: PacketEditor, owner: *PacketBatchOwner, value: [16]u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectIpv6(context_value);
        try checkedWrite(context_value, parsed.ipv6.header_offset + 24, &value, .{ .l3 = true }, .{
            .transport = true,
            .pseudo_header = true,
        });
    }

    /// Rewrites TCP flags on a complete transport header.
    pub fn setTcpFlags(self: PacketEditor, owner: *PacketBatchOwner, value: u8) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectTransport(context_value, .tcp);
        try checkedWrite(context_value, parsed.tcp.header_offset + 13, &.{value}, .{ .l4 = true }, .{ .transport = true });
    }

    /// Rewrites TCP source port.
    pub fn setTcpSourcePort(self: PacketEditor, owner: *PacketBatchOwner, value: u16) MutationError!void {
        return setTransportPort(self, owner, .tcp, true, value);
    }

    /// Rewrites TCP destination port.
    pub fn setTcpDestinationPort(self: PacketEditor, owner: *PacketBatchOwner, value: u16) MutationError!void {
        return setTransportPort(self, owner, .tcp, false, value);
    }

    /// Rewrites UDP source port.
    pub fn setUdpSourcePort(self: PacketEditor, owner: *PacketBatchOwner, value: u16) MutationError!void {
        return setTransportPort(self, owner, .udp, true, value);
    }

    /// Rewrites UDP destination port.
    pub fn setUdpDestinationPort(self: PacketEditor, owner: *PacketBatchOwner, value: u16) MutationError!void {
        return setTransportPort(self, owner, .udp, false, value);
    }

    fn setTransportPort(
        self: PacketEditor,
        owner: *PacketBatchOwner,
        protocol: TransportProtocol,
        source: bool,
        value: u16,
    ) MutationError!void {
        const context_value = try self.context(owner);
        const parsed = try expectTransport(context_value, protocol);
        const header_offset = if (protocol == .tcp) parsed.tcp.header_offset else parsed.udp.header_offset;
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .big);
        try checkedWrite(context_value, header_offset + @as(usize, if (source) 0 else 2), &bytes, .{ .l4 = true }, .{ .transport = true });
    }

    /// Prepends bytes only to mutable linear storage with sufficient headroom.
    pub fn prepend(self: PacketEditor, owner: *PacketBatchOwner, bytes: []const u8) MutationError!void {
        return resizeLinear(try self.context(owner), .prepend, bytes, 0);
    }

    /// Appends bytes only to mutable linear storage with sufficient tailroom.
    pub fn append(self: PacketEditor, owner: *PacketBatchOwner, bytes: []const u8) MutationError!void {
        return resizeLinear(try self.context(owner), .append, bytes, 0);
    }

    /// Trims bytes from the active head of mutable linear storage.
    pub fn trimHead(self: PacketEditor, owner: *PacketBatchOwner, length: usize) MutationError!void {
        return resizeLinear(try self.context(owner), .trim_head, &.{}, length);
    }

    /// Trims bytes from the active tail of mutable linear storage.
    pub fn trimTail(self: PacketEditor, owner: *PacketBatchOwner, length: usize) MutationError!void {
        return resizeLinear(try self.context(owner), .trim_tail, &.{}, length);
    }

    /// Finalizes required lengths and IPv4/TCP/UDP checksums in software.
    pub fn finalize(self: PacketEditor, owner: *PacketBatchOwner) FinalizeError!void {
        return finalizeContext(try self.context(owner));
    }
};

/// Explicitly unsafe owner/generation-bound raw editor.
pub const RawPacketEditor = enum(HandleInt) {
    _,

    /// Writes raw bytes only with explicit invalidation/validation declaration.
    pub fn write(
        self: RawPacketEditor,
        owner: *PacketBatchOwner,
        range: ByteRange,
        bytes: []const u8,
        declaration: RawWriteDeclaration,
    ) MutationError!void {
        const context_value = try rawEditorContext(@intFromEnum(self), owner);
        if (range.len != bytes.len) {
            markMutationFailure(context_value);
            return error.Bounds;
        }
        if (!declaration.invalidates.any() and !declaration.full_software_validation) {
            markMutationFailure(context_value);
            return error.MissingInvalidationDeclaration;
        }
        const dirty = if (declaration.full_software_validation)
            DirtyLayers{ .l2 = true, .l3 = true, .l4 = true }
        else
            declaration.invalidates;
        try checkedWrite(context_value, range.offset, bytes, dirty, .{
            .ipv4_header = dirty.l3,
            .transport = dirty.l3 or dirty.l4,
            .pseudo_header = dirty.l3,
        });
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
                markNonrevocableAccess(owner, viewIndex(self.view_handle));
                return segment.bytes[local_start..local_end];
            }
            segment_start = segment_end;
        }
        return null;
    }
};

const RetentionRecordState = enum { free, live, completed };

const RetentionRecord = struct {
    generation: u64 = 0,
    state: RetentionRecordState = .free,
    owner_identity: u64 = 0,
    batch_generation: u64 = 0,
    packet_index: u8 = 0,
    slot: PacketSlot = undefined,
};

var retention_pool_identity_counter = std.atomic.Value(u64).init(0);

fn retentionHandle(pool_identity: u64, generation: u64, index: usize) u128 {
    return (@as(u128, pool_identity) << 64) |
        (@as(u128, generation) << 8) |
        @as(u8, @intCast(index));
}

fn retentionPoolIdentity(lease: RetentionLease) u64 {
    return @truncate(@intFromEnum(lease) >> 64);
}

fn retentionGeneration(lease: RetentionLease) u64 {
    return @truncate((@intFromEnum(lease) >> 8) & ((@as(u128, 1) << 56) - 1));
}

fn retentionIndex(lease: RetentionLease) usize {
    return @as(u8, @truncate(@intFromEnum(lease)));
}

/// Opaque generation-bound retention ownership lease.
pub const RetentionLease = enum(u128) {
    _,

    /// Lease access and completion errors.
    pub const Error = error{
        WrongPool,
        StaleLease,
        AlreadyCompleted,
        Bounds,
        Overflow,
        DestinationTooSmall,
        TokenFailure,
    };

    /// Returns retained packet length after provenance/generation validation.
    pub fn length(self: RetentionLease, pool: *RetentionPool) Error!usize {
        return (try pool.liveRecord(self)).slot.length();
    }

    /// Performs a bounded segment-safe retained read.
    pub fn read(
        self: RetentionLease,
        pool: *RetentionPool,
        range: ByteRange,
        destination: []u8,
    ) Error!void {
        const record = try pool.liveRecord(self);
        const end = range.end() catch return error.Overflow;
        if (end > record.slot.total_len) return error.Bounds;
        if (destination.len < range.len) return error.DestinationTooSmall;
        var remaining = range.len;
        var source_offset = range.offset;
        var destination_offset: usize = 0;
        var segment_start: usize = 0;
        for (record.slot.segment_storage[0..record.slot.segment_count]) |segment| {
            const segment_end = std.math.add(usize, segment_start, segment.declared_len) catch
                return error.Overflow;
            if (source_offset < segment_end and remaining != 0) {
                const local = if (source_offset > segment_start) source_offset - segment_start else 0;
                const amount = @min(remaining, segment.declared_len - local);
                @memcpy(destination[destination_offset .. destination_offset + amount], segment.bytes[local .. local + amount]);
                remaining -= amount;
                source_offset += amount;
                destination_offset += amount;
            }
            segment_start = segment_end;
        }
        if (remaining != 0) return error.Bounds;
    }

    /// Completes the retained token exactly once.
    pub fn complete(self: RetentionLease, pool: *RetentionPool) Error!void {
        const record = try pool.recordForCompletion(self);
        record.slot.token.completeRetention() catch return error.TokenFailure;
        record.state = .completed;
    }
};

/// Setup-allocated bounded retention pool.
pub const RetentionPool = struct {
    allocator: std.mem.Allocator,
    records: []RetentionRecord,
    identity: u64,
    next_generation: u64 = 0,

    /// Retention acquisition and shutdown errors.
    pub const Error = error{
        OutOfMemory,
        CapacityTooLarge,
        Exhausted,
        WrongProvenance,
        OutstandingBorrow,
        GenerationExhausted,
        LeakedRetention,
        WrongPool,
        StaleLease,
        AlreadyCompleted,
    };

    /// Errors from binding a lease to one live batch packet.
    pub const AcquireError = Error || PacketBatch.Error;

    /// Allocates fixed lease records. Capacity is bounded by the lease encoding.
    pub fn init(allocator: std.mem.Allocator, capacity: usize) Error!RetentionPool {
        if (capacity > max_batch) return error.CapacityTooLarge;
        const identity = allocateOwnerIdentity(&retention_pool_identity_counter) catch
            return error.GenerationExhausted;
        const records = allocator.alloc(RetentionRecord, capacity) catch return error.OutOfMemory;
        @memset(records, .{});
        return .{ .allocator = allocator, .records = records, .identity = identity };
    }

    /// Releases setup storage after `verifyShutdown` succeeds.
    pub fn deinit(self: *RetentionPool) void {
        self.allocator.free(self.records);
        self.* = undefined;
    }

    /// Transfers one exact live batch packet after all bounded checks.
    fn acquireBound(
        self: *RetentionPool,
        batch: PacketBatch,
        owner_handle: *PacketBatchOwner,
        packet_index: usize,
    ) AcquireError!RetentionLease {
        const owner = try batch.ensureLive(owner_handle);
        try ensureSlotBatchAccess(owner, packet_index);
        if (owner.nonrevocable_access_issued[packet_index])
            return error.OutstandingBorrow;
        const slot = &owner.slots[packet_index];
        if ((slot.token.state() catch return error.WrongProvenance) != .worker_owned)
            return error.WrongProvenance;
        var free_index: ?usize = null;
        for (self.records, 0..) |record, index| {
            if (record.state != .live) {
                free_index = index;
                break;
            }
        }
        const index = free_index orelse return error.Exhausted;
        if (self.next_generation == (@as(u64, 1) << 56) - 1)
            return error.GenerationExhausted;
        const generation = self.next_generation + 1;

        // INVARIANT(INV-PKT-001): all bounded failure checks precede the sole
        // token transfer. The single-worker no-failure suffix publishes the
        // lease record and revokes every owner-side capability for this slot;
        // exhaustion therefore leaves both token and batch access unchanged.
        slot.token.retain() catch return error.WrongProvenance;
        self.next_generation = generation;
        self.records[index] = .{
            .generation = generation,
            .state = .live,
            .owner_identity = owner.owner_identity,
            .batch_generation = owner.live_generation,
            .packet_index = @intCast(packet_index),
            .slot = slot.*,
        };
        owner.slot_access[packet_index] = .retained;
        owner.raw_capability_authorities[packet_index] = .{};
        return @enumFromInt(retentionHandle(self.identity, generation, index));
    }

    fn checkedRecord(self: *RetentionPool, lease: RetentionLease) RetentionLease.Error!*RetentionRecord {
        if (retentionPoolIdentity(lease) != self.identity) return error.WrongPool;
        const index = retentionIndex(lease);
        if (index >= self.records.len) return error.StaleLease;
        const record = &self.records[index];
        if (record.generation != retentionGeneration(lease)) return error.StaleLease;
        return record;
    }

    fn liveRecord(self: *RetentionPool, lease: RetentionLease) RetentionLease.Error!*RetentionRecord {
        const record = try self.checkedRecord(lease);
        return switch (record.state) {
            .live => record,
            .completed => error.AlreadyCompleted,
            .free => error.StaleLease,
        };
    }

    fn recordForCompletion(self: *RetentionPool, lease: RetentionLease) RetentionLease.Error!*RetentionRecord {
        return self.liveRecord(lease);
    }

    /// Detects any live lease during deterministic shutdown.
    pub fn verifyShutdown(self: *const RetentionPool) Error!void {
        for (self.records) |record|
            if (record.state == .live) return error.LeakedRetention;
    }
};

/// One packet's processor-visible disposition.
pub const PacketDisposition = union(enum) {
    Continue,
    Accept: ?OutputId,
    Drop: ?DropReasonId,
    Redirect: struct { output: OutputId, metadata: ?AdapterMetadataId = null },
    Retain: RetentionLease,
    Complete: CompletionId,

    /// Returns whether the disposition removes the packet from active work.
    pub fn isTerminal(self: PacketDisposition) bool {
        return self != .Continue;
    }
};

/// Preallocated terminal-disposition recorder for one bounded batch.
const DispositionWriterState = struct {
    handle_generation: u64 = 0,
    batch_generation: u64 = 0,
    batch_len: usize = 0,
    active: PacketSelection = @enumFromInt(0),
    values: [max_batch]PacketDisposition = [_]PacketDisposition{.Continue} ** max_batch,
};

/// Opaque owner- and generation-bound handle to private disposition state.
pub const DispositionWriter = enum(HandleInt) {
    _,

    /// Disposition write errors.
    pub const Error = error{
        BatchTooLarge,
        OutOfRange,
        EmptySelection,
        StaleSelection,
        NotTerminal,
        AlreadyTerminal,
        AlreadyInitialized,
        BatchMismatch,
        GenerationExhausted,
        RetentionRequiresBinding,
        StaleWriter,
    };

    /// Starts every live batch packet active with `Continue` without allocation.
    pub fn init(
        batch: PacketBatch,
        owner_handle: *PacketBatchOwner,
    ) (Error || PacketBatch.Error)!DispositionWriter {
        const owner = try batch.ensureLive(owner_handle);
        if (owner.disposition.handle_generation != 0)
            return error.AlreadyInitialized;
        if (owner.next_disposition_generation == std.math.maxInt(u64))
            return error.GenerationExhausted;
        owner.next_disposition_generation += 1;
        owner.disposition = .{
            .handle_generation = owner.next_disposition_generation,
            .batch_generation = owner.live_generation,
            .batch_len = owner.slot_count,
            .active = PacketSelection.all(owner.slot_count) catch return error.BatchTooLarge,
        };
        return @enumFromInt(encodeHandle(
            owner.owner_identity,
            owner.disposition.handle_generation,
        ));
    }

    fn checkedState(
        self: DispositionWriter,
        owner_handle: *PacketBatchOwner,
    ) Error!*DispositionWriterState {
        const owner = ownerImpl(owner_handle);
        const identity = handleOwnerIdentity(@intFromEnum(self));
        const generation = handleLocalTag(@intFromEnum(self));
        const state = &owner.disposition;
        if (identity == 0 or owner.owner_identity != identity)
            return error.StaleWriter;
        if (generation == 0 or state.handle_generation != generation)
            return error.StaleWriter;
        if (owner.live_generation == 0 or state.batch_generation != owner.live_generation)
            return error.StaleWriter;
        return state;
    }

    /// Returns the current active selection by value.
    pub fn activeSelection(
        self: DispositionWriter,
        owner: *PacketBatchOwner,
    ) Error!PacketSelection {
        return (try self.checkedState(owner)).active;
    }

    /// Returns one checked disposition.
    pub fn get(
        self: DispositionWriter,
        owner: *PacketBatchOwner,
        index: usize,
    ) Error!PacketDisposition {
        const state = try self.checkedState(owner);
        _ = PacketIndex.init(index, state.batch_len) catch return error.OutOfRange;
        return state.values[index];
    }

    /// Records one terminal disposition and clears that packet from active.
    pub fn set(
        self: DispositionWriter,
        owner: *PacketBatchOwner,
        index: usize,
        disposition: PacketDisposition,
    ) Error!void {
        const state = try self.checkedState(owner);
        const checked = PacketIndex.init(index, state.batch_len) catch return error.OutOfRange;
        if (state.values[checked.raw()].isTerminal()) return error.AlreadyTerminal;
        return self.setSelection(
            owner,
            try PacketSelection.one(checked.raw(), state.batch_len),
            disposition,
        );
    }

    /// Applies one terminal disposition atomically to a checked active subset.
    pub fn setSelection(
        self: DispositionWriter,
        owner: *PacketBatchOwner,
        selection: PacketSelection,
        disposition: PacketDisposition,
    ) Error!void {
        const state = try self.checkedState(owner);
        if (!disposition.isTerminal()) return error.NotTerminal;
        switch (disposition) {
            .Retain => return error.RetentionRequiresBinding,
            else => {},
        }
        const valid = (PacketSelection.all(state.batch_len) catch return error.BatchTooLarge).bits();
        const selected = selection.bits();
        if (selected == 0) return error.EmptySelection;
        if ((selected & ~valid) != 0) return error.OutOfRange;
        if ((selected & ~state.active.bits()) != 0) return error.StaleSelection;

        var iterator = selection.iterator();
        while (iterator.next()) |index|
            state.values[index.raw()] = disposition;
        state.active = @enumFromInt(state.active.bits() & ~selected);
    }

    /// Atomically binds one new lease to one exact live packet disposition.
    pub fn retain(
        self: DispositionWriter,
        batch: PacketBatch,
        owner: *PacketBatchOwner,
        pool: *RetentionPool,
        index: usize,
    ) (Error || RetentionPool.AcquireError)!RetentionLease {
        const state = try self.checkedState(owner);
        const live_len = try batch.len(owner);
        if (live_len != state.batch_len or batchGeneration(batch) != state.batch_generation)
            return error.BatchMismatch;
        const checked = PacketIndex.init(index, state.batch_len) catch return error.OutOfRange;
        if (state.values[index].isTerminal()) return error.AlreadyTerminal;
        const next_active = try state.active.without(checked, state.batch_len);

        // No fallible operation follows the token transfer performed here.
        const lease = try pool.acquireBound(batch, owner, index);
        state.values[index] = .{ .Retain = lease };
        state.active = next_active;
        return lease;
    }
};

/// Explicit end-of-pipeline resolution for leftover `Continue` packets.
pub const ContinuePolicy = union(enum) {
    accept: ?OutputId,
    drop: ?DropReasonId,
    complete: CompletionId,
};

/// Bounded caller-owned output configuration.
pub const DispositionConfig = struct {
    outputs: []const OutputId,
    default_output: ?OutputId,
    continue_policy: ContinuePolicy,
};

/// One receive-ordered accepted or redirected output item.
pub const OutputItem = struct {
    index: PacketIndex,
    redirect_metadata: ?AdapterMetadataId,
};

/// One configured output's receive-ordered items.
pub const OutputGroup = struct {
    output: OutputId,
    items: [max_batch]OutputItem = undefined,
    count: usize = 0,
};

/// Fully separated, bounded resolution groups.
pub const DispositionGroups = struct {
    /// Maximum number of configured output groups in one resolved batch.
    pub const max_outputs = 16;

    outputs: [max_outputs]OutputGroup = undefined,
    output_count: usize = 0,
    drops: [max_batch]struct { index: PacketIndex, reason: ?DropReasonId } = undefined,
    drop_count: usize = 0,
    completions: [max_batch]struct { index: PacketIndex, id: CompletionId } = undefined,
    completion_count: usize = 0,
    retentions: [max_batch]struct { index: PacketIndex, lease: RetentionLease } = undefined,
    retention_count: usize = 0,

    /// Resolution errors.
    pub const Error = error{ TooManyOutputs, DuplicateOutput, UnknownOutput, MissingDefaultOutput };

    fn findOutput(self: *DispositionGroups, output: OutputId) ?*OutputGroup {
        for (self.outputs[0..self.output_count]) |*group|
            if (group.output.raw() == output.raw()) return group;
        return null;
    }

    fn appendOutput(
        self: *DispositionGroups,
        output: OutputId,
        index: PacketIndex,
        metadata: ?AdapterMetadataId,
    ) Error!void {
        const group = self.findOutput(output) orelse return error.UnknownOutput;
        group.items[group.count] = .{ .index = index, .redirect_metadata = metadata };
        group.count += 1;
    }

    /// Resolves all explicit and implicit dispositions without allocation.
    pub fn resolve(
        writer: DispositionWriter,
        owner: *PacketBatchOwner,
        config: DispositionConfig,
    ) (Error || DispositionWriter.Error)!DispositionGroups {
        const state = try writer.checkedState(owner);
        if (config.outputs.len > max_outputs) return error.TooManyOutputs;
        var result = DispositionGroups{};
        result.output_count = config.outputs.len;
        for (config.outputs, 0..) |output, index| {
            for (config.outputs[0..index]) |earlier|
                if (earlier.raw() == output.raw()) return error.DuplicateOutput;
            result.outputs[index] = .{ .output = output };
        }

        for (state.values[0..state.batch_len], 0..) |recorded, raw_index| {
            const index = PacketIndex.init(raw_index, state.batch_len) catch unreachable;
            const disposition: PacketDisposition = switch (recorded) {
                .Continue => switch (config.continue_policy) {
                    .accept => |output| .{ .Accept = output },
                    .drop => |reason| .{ .Drop = reason },
                    .complete => |id| .{ .Complete = id },
                },
                else => recorded,
            };
            switch (disposition) {
                .Continue => unreachable,
                .Accept => |maybe_output| {
                    const output = maybe_output orelse config.default_output orelse
                        return error.MissingDefaultOutput;
                    try result.appendOutput(output, index, null);
                },
                .Redirect => |redirect| try result.appendOutput(
                    redirect.output,
                    index,
                    redirect.metadata,
                ),
                .Drop => |reason| {
                    result.drops[result.drop_count] = .{ .index = index, .reason = reason };
                    result.drop_count += 1;
                },
                .Complete => |id| {
                    result.completions[result.completion_count] = .{ .index = index, .id = id };
                    result.completion_count += 1;
                },
                .Retain => |lease| {
                    result.retentions[result.retention_count] = .{ .index = index, .lease = lease };
                    result.retention_count += 1;
                },
            }
        }
        return result;
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

test "M2 selection membership rejects forged and cross-batch indices" {
    const selection = try PacketSelection.one(1, 2);
    try std.testing.expect(try selection.contains(try PacketIndex.init(1, 2), 2));
    try std.testing.expect(!(try selection.contains(try PacketIndex.init(0, 2), 2)));
    const removed = try selection.without(try PacketIndex.init(1, 2), 2);
    try std.testing.expect(removed.isEmpty());

    const forged_64: PacketIndex = @enumFromInt(64);
    const forged_255: PacketIndex = @enumFromInt(255);
    try std.testing.expectError(error.OutOfRange, selection.contains(forged_64, 2));
    try std.testing.expectError(error.OutOfRange, selection.without(forged_255, 2));

    const larger = try PacketSelection.one(3, 4);
    try std.testing.expectError(
        error.OutOfRange,
        larger.contains(try PacketIndex.init(0, 2), 2),
    );
    try std.testing.expectError(
        error.OutOfRange,
        larger.without(try PacketIndex.init(0, 2), 2),
    );
    try std.testing.expectError(error.BatchTooLarge, selection.contains(forged_64, 65));
}

test "M2 disposition writer exposes only an opaque checked handle" {
    try std.testing.expect(switch (@typeInfo(DispositionWriter)) {
        .@"enum" => true,
        else => false,
    });
    try std.testing.expect(!@hasField(DispositionWriter, "active"));
    try std.testing.expect(!@hasField(DispositionWriter, "values"));
}

test "FR-PKT-005 FR-PKT-010 FR-PKT-013 AC-002 INV-PKT-003 INV-PKT-004 terminal dispositions are atomic and group in receive order" {
    var tracker = try TokenTracker.init(std.testing.allocator, 6);
    defer tracker.deinit();
    const bytes = [_]u8{0};
    const descriptor = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    var slots: [6]PacketSlot = undefined;
    for (&slots, 0..) |*slot, index| {
        const token = try tracker.registerInput();
        try token.receive();
        slot.* = try PacketSlot.init(token, &descriptor, bytes.len, index, .{}, null);
    }
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const writer = try DispositionWriter.init(batch, owner);
    const first = try PacketSelection.one(1, 6);
    const second = try PacketSelection.one(4, 6);
    try writer.setSelection(owner, first.intersect(first), .{ .Drop = .init(9) });
    try writer.setSelection(owner, second, .{ .Redirect = .{
        .output = .init(2),
        .metadata = .init(22),
    } });
    const before = try writer.activeSelection(owner);
    try std.testing.expectError(
        error.StaleSelection,
        writer.setSelection(owner, first, .{ .Accept = .init(1) }),
    );
    try std.testing.expectEqual(before.bits(), (try writer.activeSelection(owner)).bits());
    try std.testing.expectError(
        error.OutOfRange,
        writer.setSelection(owner, @enumFromInt(@as(u64, 1) << 9), .{ .Drop = null }),
    );
    try std.testing.expectError(error.AlreadyTerminal, writer.set(owner, 1, .{ .Drop = null }));

    const groups = try DispositionGroups.resolve(writer, owner, .{
        .outputs = &.{ .init(1), .init(2) },
        .default_output = .init(1),
        .continue_policy = .{ .accept = null },
    });
    try std.testing.expectEqual(@as(usize, 1), groups.drop_count);
    try std.testing.expectEqual(@as(usize, 4), groups.outputs[0].count);
    try std.testing.expectEqual(@as(usize, 1), groups.outputs[1].count);
    try std.testing.expectEqual(@as(usize, 0), groups.outputs[0].items[0].index.raw());
    try std.testing.expectEqual(@as(usize, 5), groups.outputs[0].items[3].index.raw());
    try std.testing.expectEqual(@as(usize, 4), groups.outputs[1].items[0].index.raw());
    try std.testing.expectEqual(@as(u64, 22), groups.outputs[1].items[0].redirect_metadata.?.raw());

    try std.testing.expectError(
        error.UnknownOutput,
        DispositionGroups.resolve(writer, owner, .{
            .outputs = &.{.init(1)},
            .default_output = .init(1),
            .continue_policy = .{ .accept = null },
        }),
    );
    try batch.invalidate(owner);
    for (&slots) |slot| try slot.adapterToken().returnToInput();
    try tracker.verifyReceivedCompleted();
}

fn retentionPoolAllocationCase(allocator: std.mem.Allocator) !void {
    var pool = try RetentionPool.init(allocator, 2);
    defer pool.deinit();
}

test "FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 retention capacity provenance completion and leaks are exact" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        retentionPoolAllocationCase,
        .{},
    );
    var tracker = try TokenTracker.init(std.testing.allocator, 3);
    defer tracker.deinit();
    const bytes = [_]u8{ 1, 2, 3 };
    const descriptors = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    const token_a = try tracker.registerInput();
    const token_b = try tracker.registerInput();
    const token_never_received = try tracker.registerInput();
    try token_a.receive();
    try token_b.receive();
    var slots = [_]PacketSlot{
        try PacketSlot.init(token_a, &descriptors, bytes.len, 0, .{}, null),
        try PacketSlot.init(token_b, &descriptors, bytes.len, 1, .{}, null),
        try PacketSlot.init(token_never_received, &descriptors, bytes.len, 2, .{}, null),
    };
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    const writer = try DispositionWriter.init(batch, owner);
    try std.testing.expectError(error.AlreadyInitialized, DispositionWriter.init(batch, owner));

    const other_owner = try PacketBatchOwner.init(std.testing.allocator);
    defer other_owner.deinit();
    try std.testing.expectError(error.StaleWriter, writer.activeSelection(other_owner));
    const forged_writer: DispositionWriter = @enumFromInt(
        @intFromEnum(writer) ^ (@as(HandleInt, 1) << handle_component_bits),
    );
    try std.testing.expectError(error.StaleWriter, forged_writer.activeSelection(owner));

    var pool = try RetentionPool.init(std.testing.allocator, 1);
    defer pool.deinit();
    const lease = try writer.retain(batch, owner, &pool, 0);
    try std.testing.expectEqual(TokenState.retained, try token_a.state());
    const record = try pool.liveRecord(lease);
    try std.testing.expectEqual(batchOwnerIdentity(batch), record.owner_identity);
    try std.testing.expectEqual(batchGeneration(batch), record.batch_generation);
    try std.testing.expectEqual(@as(u8, 0), record.packet_index);

    try std.testing.expectError(
        error.AlreadyTerminal,
        writer.retain(batch, owner, &pool, 0),
    );
    try std.testing.expectError(error.Exhausted, writer.retain(batch, owner, &pool, 1));
    try std.testing.expectEqual(TokenState.worker_owned, try token_b.state());
    try std.testing.expectError(
        error.WrongProvenance,
        writer.retain(batch, owner, &pool, 2),
    );
    try std.testing.expectError(
        error.RetentionRequiresBinding,
        writer.setSelection(owner, try PacketSelection.one(1, slots.len), .{ .Retain = lease }),
    );
    try std.testing.expectEqual(TokenState.worker_owned, try token_b.state());
    try std.testing.expectError(error.LeakedRetention, pool.verifyShutdown());
    var actual: [3]u8 = undefined;
    try lease.read(&pool, .{ .offset = 0, .len = 3 }, &actual);
    try std.testing.expectEqualSlices(u8, &bytes, &actual);

    var other_pool = try RetentionPool.init(std.testing.allocator, 1);
    defer other_pool.deinit();
    try std.testing.expectError(error.WrongPool, lease.length(&other_pool));
    const forged: RetentionLease = @enumFromInt(@intFromEnum(lease) ^ (@as(u128, 1) << 8));
    try std.testing.expectError(error.StaleLease, forged.length(&pool));
    try lease.complete(&pool);
    try std.testing.expectError(error.AlreadyCompleted, lease.complete(&pool));
    try pool.verifyShutdown();
    try batch.invalidate(owner);
    try std.testing.expectError(error.StaleWriter, writer.activeSelection(owner));
    const next_batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        slots[1..2],
    );
    const next_writer = try DispositionWriter.init(next_batch, owner);
    try std.testing.expectError(error.StaleWriter, writer.activeSelection(owner));
    try std.testing.expectEqual(@as(usize, 1), (try next_writer.activeSelection(owner)).count());
    try next_batch.invalidate(owner);
    try token_b.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 retention revokes all batch aliases through completion and generation reuse" {
    var retained_bytes = ethernetIpv4UdpFixture();
    var recycled_bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const retained_token = try tracker.registerInput();
    const recycled_token = try tracker.registerInput();
    try retained_token.receive();
    try recycled_token.receive();
    const retained_mutable = [_]MutableSegmentDescriptor{
        try .init(&retained_bytes, 0, retained_bytes.len, .{}),
    };
    const recycled_mutable = [_]MutableSegmentDescriptor{
        try .init(&recycled_bytes, 0, recycled_bytes.len, .{}),
    };
    var retained_slots = [_]PacketSlot{try PacketSlot.initMutable(
        retained_token,
        &retained_mutable,
        retained_bytes.len,
        0,
        .{},
        null,
    )};
    var recycled_slots = [_]PacketSlot{try PacketSlot.initMutable(
        recycled_token,
        &recycled_mutable,
        recycled_bytes.len,
        1,
        .{},
        null,
    )};

    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &retained_slots,
    );
    const view = try batch.view(owner, 0);
    const editor = try batch.editor(owner, 0);
    const raw = try batch.unsafeRawEditorForTesting(owner, 0);
    const output_packet = try batch.outputPacket(owner, 0);
    var iterator = try view.segments(owner, .{ .offset = 0, .len = retained_bytes.len });
    const writer = try DispositionWriter.init(batch, owner);
    var pool = try RetentionPool.init(std.testing.allocator, 1);
    defer pool.deinit();

    const lease = try writer.retain(batch, owner, &pool, 0);
    try std.testing.expectEqual(TokenState.retained, try retained_token.state());
    const retained_snapshot = retained_bytes;
    var lease_bytes: [retained_bytes.len]u8 = undefined;
    try lease.read(&pool, .{ .offset = 0, .len = retained_bytes.len }, &lease_bytes);
    try std.testing.expectEqualSlices(u8, &retained_snapshot, &lease_bytes);

    try std.testing.expectError(error.AccessRevoked, view.length(owner));
    try std.testing.expectError(error.AccessRevoked, editor.setIpv4Ttl(owner, 31));
    try std.testing.expectError(
        error.InvalidRawCapability,
        raw.write(
            owner,
            .{ .offset = 22, .len = 1 },
            &.{31},
            .{ .full_software_validation = true },
        ),
    );
    try std.testing.expectError(error.AccessRevoked, iterator.next(owner));
    try std.testing.expectError(error.AccessRevoked, batch.view(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.editor(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.unsafeRawEditorForTesting(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.outputPacket(owner, 0));
    try std.testing.expectError(error.AccessRevoked, output_packet.length(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.segmentCount(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.adapterToken(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.adapterSegment(owner, 0));
    try std.testing.expectError(error.AccessRevoked, output_packet.recordSubmit(owner));
    try std.testing.expectError(error.AccessRevoked, batch.mutationJournal(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.validateForOutput(owner, 0));
    try std.testing.expectEqualSlices(u8, &retained_snapshot, &retained_bytes);

    try lease.complete(&pool);
    try std.testing.expectEqual(TokenState.completed, try retained_token.state());
    try std.testing.expectError(error.AlreadyCompleted, lease.length(&pool));
    try std.testing.expectError(error.AccessRevoked, view.length(owner));
    try std.testing.expectError(error.AccessRevoked, editor.setIpv4Ttl(owner, 30));
    try std.testing.expectError(
        error.InvalidRawCapability,
        raw.write(
            owner,
            .{ .offset = 22, .len = 1 },
            &.{30},
            .{ .full_software_validation = true },
        ),
    );
    try std.testing.expectError(error.AccessRevoked, batch.view(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.editor(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.unsafeRawEditorForTesting(owner, 0));
    try std.testing.expectError(error.AccessRevoked, batch.outputPacket(owner, 0));
    try std.testing.expectError(error.AccessRevoked, output_packet.length(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.segmentCount(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.adapterToken(owner));
    try std.testing.expectError(error.AccessRevoked, output_packet.adapterSegment(owner, 0));
    try std.testing.expectError(error.AccessRevoked, output_packet.recordSubmit(owner));
    try std.testing.expectError(error.AccessRevoked, batch.validateForOutput(owner, 0));
    try std.testing.expectEqualSlices(u8, &retained_snapshot, &retained_bytes);
    try pool.verifyShutdown();

    try batch.invalidate(owner);
    try std.testing.expectError(error.StaleView, output_packet.length(owner));
    try std.testing.expectError(error.StaleView, output_packet.segmentCount(owner));
    try std.testing.expectError(error.StaleView, output_packet.adapterToken(owner));
    try std.testing.expectError(error.StaleView, output_packet.adapterSegment(owner, 0));
    try std.testing.expectError(error.StaleView, output_packet.recordSubmit(owner));
    const next_batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &recycled_slots,
    );
    try std.testing.expectError(error.StaleView, view.length(owner));
    try std.testing.expectError(error.StaleView, output_packet.length(owner));
    try std.testing.expectError(error.StaleView, output_packet.segmentCount(owner));
    try std.testing.expectError(error.StaleView, output_packet.adapterToken(owner));
    try std.testing.expectError(error.StaleView, output_packet.adapterSegment(owner, 0));
    try std.testing.expectError(error.StaleView, output_packet.recordSubmit(owner));
    try std.testing.expectError(error.StaleView, editor.setIpv4Ttl(owner, 29));
    try std.testing.expectError(
        error.InvalidRawCapability,
        raw.write(
            owner,
            .{ .offset = 22, .len = 1 },
            &.{29},
            .{ .full_software_validation = true },
        ),
    );
    const next_view = try next_batch.view(owner, 0);
    const next_editor = try next_batch.editor(owner, 0);
    const next_raw = try next_batch.unsafeRawEditorForTesting(owner, 0);
    const next_output_packet = try next_batch.outputPacket(owner, 0);
    try std.testing.expectEqual(recycled_bytes.len, try next_view.length(owner));
    try std.testing.expectEqual(recycled_bytes.len, try next_output_packet.length(owner));
    try std.testing.expectEqual(@as(usize, 1), try next_output_packet.segmentCount(owner));
    try std.testing.expectEqual(recycled_token, try next_output_packet.adapterToken(owner));
    try std.testing.expectEqualSlices(
        u8,
        &recycled_bytes,
        try next_output_packet.adapterSegment(owner, 0),
    );
    try next_output_packet.recordSubmit(owner);
    try next_editor.setIpv4Ttl(owner, 28);
    try next_raw.write(
        owner,
        .{ .offset = 22, .len = 1 },
        &.{27},
        .{ .full_software_validation = true },
    );
    try next_editor.finalize(owner);
    try next_batch.validateForOutput(owner, 0);
    try next_batch.invalidate(owner);
    try recycled_token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-011 FR-PKT-012 AC-010 INV-PKT-001 raw slice and token escapes reject retention atomically" {
    const contiguous_bytes = [_]u8{ 1, 2, 3 };
    const iterator_bytes = [_]u8{ 4, 5, 6 };
    const output_token_bytes = [_]u8{ 7, 8, 9 };
    const output_segment_bytes = [_]u8{ 10, 11, 12 };
    const copied_bytes = [_]u8{ 13, 14, 15 };
    const contiguous_descriptors = [_]SegmentDescriptor{
        SegmentDescriptor.fromBytes(&contiguous_bytes),
    };
    const iterator_descriptors = [_]SegmentDescriptor{
        SegmentDescriptor.fromBytes(&iterator_bytes),
    };
    const output_token_descriptors = [_]SegmentDescriptor{
        SegmentDescriptor.fromBytes(&output_token_bytes),
    };
    const output_segment_descriptors = [_]SegmentDescriptor{
        SegmentDescriptor.fromBytes(&output_segment_bytes),
    };
    const copied_descriptors = [_]SegmentDescriptor{
        SegmentDescriptor.fromBytes(&copied_bytes),
    };

    var tracker = try TokenTracker.init(std.testing.allocator, 5);
    defer tracker.deinit();
    const contiguous_token = try tracker.registerInput();
    const iterator_token = try tracker.registerInput();
    const output_token = try tracker.registerInput();
    const output_segment_token = try tracker.registerInput();
    const copied_token = try tracker.registerInput();
    try contiguous_token.receive();
    try iterator_token.receive();
    try output_token.receive();
    try output_segment_token.receive();
    try copied_token.receive();
    var slots = [_]PacketSlot{
        try PacketSlot.init(
            contiguous_token,
            &contiguous_descriptors,
            contiguous_bytes.len,
            0,
            .{},
            null,
        ),
        try PacketSlot.init(
            iterator_token,
            &iterator_descriptors,
            iterator_bytes.len,
            1,
            .{},
            null,
        ),
        try PacketSlot.init(
            output_token,
            &output_token_descriptors,
            output_token_bytes.len,
            2,
            .{},
            null,
        ),
        try PacketSlot.init(
            output_segment_token,
            &output_segment_descriptors,
            output_segment_bytes.len,
            3,
            .{},
            null,
        ),
        try PacketSlot.init(
            copied_token,
            &copied_descriptors,
            copied_bytes.len,
            4,
            .{},
            null,
        ),
    };

    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    const writer = try DispositionWriter.init(batch, owner);
    var pool = try RetentionPool.init(std.testing.allocator, 1);
    defer pool.deinit();

    const contiguous_view = try batch.view(owner, 0);
    const contiguous_slice = (try contiguous_view.contiguous(
        owner,
        .{ .offset = 0, .len = contiguous_bytes.len },
    )).?;
    const iterator_view = try batch.view(owner, 1);
    var iterator = try iterator_view.segments(
        owner,
        .{ .offset = 0, .len = iterator_bytes.len },
    );
    const iterator_slice = (try iterator.next(owner)).?;
    const token_output_packet = try batch.outputPacket(owner, 2);
    try std.testing.expectEqual(output_token, try token_output_packet.adapterToken(owner));
    const segment_output_packet = try batch.outputPacket(owner, 3);
    const output_slice = try segment_output_packet.adapterSegment(owner, 0);
    const copied_view = try batch.view(owner, 4);
    var copied: [copied_bytes.len]u8 = undefined;
    try copied_view.read(
        owner,
        .{ .offset = 0, .len = copied_bytes.len },
        &copied,
    );

    try std.testing.expectError(
        error.OutstandingBorrow,
        writer.retain(batch, owner, &pool, 0),
    );
    try std.testing.expectError(
        error.OutstandingBorrow,
        writer.retain(batch, owner, &pool, 1),
    );
    try std.testing.expectError(
        error.OutstandingBorrow,
        writer.retain(batch, owner, &pool, 2),
    );
    try std.testing.expectError(
        error.OutstandingBorrow,
        writer.retain(batch, owner, &pool, 3),
    );
    try std.testing.expectEqual(TokenState.worker_owned, try contiguous_token.state());
    try std.testing.expectEqual(TokenState.worker_owned, try iterator_token.state());
    try std.testing.expectEqual(TokenState.worker_owned, try output_token.state());
    try std.testing.expectEqual(TokenState.worker_owned, try output_segment_token.state());
    try std.testing.expectEqual(@as(usize, 5), (try writer.activeSelection(owner)).count());
    try std.testing.expectEqualSlices(u8, &contiguous_bytes, contiguous_slice);
    try std.testing.expectEqualSlices(u8, &iterator_bytes, iterator_slice);
    try std.testing.expectEqualSlices(u8, &output_segment_bytes, output_slice);
    try std.testing.expectEqualSlices(u8, &copied_bytes, &copied);
    try std.testing.expectEqual(contiguous_bytes.len, try contiguous_view.length(owner));
    try std.testing.expectEqual(iterator_bytes.len, try iterator_view.length(owner));
    try std.testing.expectEqual(output_token_bytes.len, try token_output_packet.length(owner));
    try std.testing.expectEqual(
        output_segment_bytes.len,
        try segment_output_packet.length(owner),
    );

    const lease = try writer.retain(batch, owner, &pool, 4);
    try std.testing.expectEqual(TokenState.retained, try copied_token.state());
    try std.testing.expectEqual(@as(usize, 4), (try writer.activeSelection(owner)).count());
    var retained_copy: [copied_bytes.len]u8 = undefined;
    try lease.read(
        &pool,
        .{ .offset = 0, .len = copied_bytes.len },
        &retained_copy,
    );
    try std.testing.expectEqualSlices(u8, &copied_bytes, &retained_copy);
    try lease.complete(&pool);
    try pool.verifyShutdown();

    try batch.invalidate(owner);
    try contiguous_token.returnToInput();
    try iterator_token.returnToInput();
    try output_token.returnToInput();
    try output_segment_token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-011 FR-PKT-012 AC-010 retention exhaustion preserves every batch capability atomically" {
    var bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{try .init(&bytes, 0, bytes.len, .{})};
    var slots = [_]PacketSlot{try PacketSlot.initMutable(
        token,
        &mutable,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    const view = try batch.view(owner, 0);
    const editor = try batch.editor(owner, 0);
    const raw = try batch.unsafeRawEditorForTesting(owner, 0);
    const writer = try DispositionWriter.init(batch, owner);
    var pool = try RetentionPool.init(std.testing.allocator, 0);
    defer pool.deinit();

    try std.testing.expectError(error.Exhausted, writer.retain(batch, owner, &pool, 0));
    try std.testing.expectEqual(TokenState.worker_owned, try token.state());
    try std.testing.expectEqual(@as(usize, 1), (try writer.activeSelection(owner)).count());
    switch (try writer.get(owner, 0)) {
        .Continue => {},
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqual(bytes.len, try view.length(owner));
    try editor.setIpv4Ttl(owner, 63);
    try raw.write(
        owner,
        .{ .offset = 22, .len = 1 },
        &.{62},
        .{ .full_software_validation = true },
    );
    try editor.finalize(owner);

    const next_view = try batch.view(owner, 0);
    const next_editor = try batch.editor(owner, 0);
    const next_raw = try batch.unsafeRawEditorForTesting(owner, 0);
    try std.testing.expectEqual(bytes.len, try next_view.length(owner));
    try next_editor.setIpv4Ttl(owner, 61);
    try next_raw.write(
        owner,
        .{ .offset = 22, .len = 1 },
        &.{60},
        .{ .full_software_validation = true },
    );
    try next_editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    try std.testing.expectEqual(
        bytes.len,
        try (try batch.outputPacket(owner, 0)).length(owner),
    );
    try std.testing.expectEqual(@as(u8, 60), bytes[22]);
    try std.testing.expectEqual(TokenState.worker_owned, try token.state());
    try pool.verifyShutdown();
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

fn parsedFixture(
    bytes: []const u8,
    splits: []const usize,
    config: ParserConfig,
) !ParsedPacket {
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    var descriptors: [max_segments]SegmentDescriptor = undefined;
    var start: usize = 0;
    for (splits, 0..) |end, index| {
        descriptors[index] = SegmentDescriptor.fromBytes(bytes[start..end]);
        start = end;
    }
    descriptors[splits.len] = SegmentDescriptor.fromBytes(bytes[start..]);
    var slots = [_]PacketSlot{try PacketSlot.init(
        token,
        descriptors[0 .. splits.len + 1],
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const parsed = try (try batch.view(owner, 0)).parse(owner, config);
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
    return parsed;
}

fn ethernetIpv4UdpFixture() [46]u8 {
    var bytes = [_]u8{0} ** 46;
    bytes[0..6].* = .{ 0, 1, 2, 3, 4, 5 };
    bytes[6..12].* = .{ 6, 7, 8, 9, 10, 11 };
    bytes[12..14].* = .{ 0x08, 0x00 };
    bytes[14] = 0x45;
    bytes[15] = 0xb8;
    bytes[16..18].* = .{ 0, 32 };
    bytes[22] = 64;
    bytes[23] = 17;
    bytes[26..30].* = .{ 192, 0, 2, 1 };
    bytes[30..34].* = .{ 198, 51, 100, 2 };
    bytes[34..36].* = .{ 0x12, 0x34 };
    bytes[36..38].* = .{ 0x56, 0x78 };
    bytes[38..40].* = .{ 0, 12 };
    bytes[42..46].* = .{ 1, 2, 3, 4 };
    return bytes;
}

fn ethernetIpv4InitialUdpFragmentFixture() [42]u8 {
    const complete = ethernetIpv4UdpFixture();
    var bytes: [42]u8 = complete[0..42].*;
    bytes[16..18].* = .{ 0, 28 };
    bytes[20..22].* = .{ 0x20, 0 };
    return bytes;
}

fn ethernetIpv4TcpFixture() [54]u8 {
    var bytes = [_]u8{0} ** 54;
    const udp = ethernetIpv4UdpFixture();
    @memcpy(bytes[0..34], udp[0..34]);
    bytes[16..18].* = .{ 0, 40 };
    bytes[23] = 6;
    bytes[34..36].* = .{ 0x12, 0x34 };
    bytes[36..38].* = .{ 0x56, 0x78 };
    bytes[46] = 0x50;
    bytes[47] = 0x10;
    return bytes;
}

fn ethernetIpv4TcpOddPayloadFixture() [59]u8 {
    var bytes = [_]u8{0} ** 59;
    const header = ethernetIpv4TcpFixture();
    @memcpy(bytes[0..header.len], &header);
    bytes[16..18].* = .{ 0, 45 };
    bytes[54..59].* = .{ 1, 2, 3, 4, 5 };
    return bytes;
}

fn ethernetIpv4IcmpFixture() [38]u8 {
    var bytes = [_]u8{0} ** 38;
    const udp = ethernetIpv4UdpFixture();
    @memcpy(bytes[0..34], udp[0..34]);
    bytes[16..18].* = .{ 0, 24 };
    bytes[23] = 1;
    bytes[34..38].* = .{ 8, 0, 0, 0 };
    return bytes;
}

fn ethernetIpv4OptionsUdpFixture() [46]u8 {
    var bytes = ethernetIpv4UdpFixture();
    bytes[14] = 0x46;
    bytes[34..38].* = .{ 1, 1, 1, 1 };
    bytes[38..46].* = .{ 0x12, 0x34, 0x56, 0x78, 0, 8, 0, 0 };
    return bytes;
}

fn ethernetTwoVlanIpv4UdpFixture() [54]u8 {
    var bytes = [_]u8{0} ** 54;
    const udp = ethernetIpv4UdpFixture();
    @memcpy(bytes[0..12], udp[0..12]);
    bytes[12..22].* = .{
        0x81, 0x00, 0, 1,
        0x88, 0xa8, 0, 2,
        0x08, 0x00,
    };
    @memcpy(bytes[22..], udp[14..]);
    return bytes;
}

fn expectEveryPrefixTruncated(bytes: []const u8) !void {
    for (0..bytes.len) |length| {
        const parsed = try parsedFixture(bytes[0..length], &.{}, .{});
        try std.testing.expect(
            parsed.ethernet_status == .truncated or
                parsed.network_status == .truncated or
                parsed.transport_status == .truncated,
        );
    }
    const complete = try parsedFixture(bytes, &.{}, .{});
    try std.testing.expectEqual(ParseStatus.present, complete.ethernet_status);
    try std.testing.expectEqual(ParseStatus.present, complete.network_status);
    try std.testing.expectEqual(ParseStatus.present, complete.transport_status);
}

test "M2 lazy parser is segment-safe at every Ethernet IPv4 UDP split" {
    const bytes = ethernetIpv4UdpFixture();
    for (0..bytes.len + 1) |split| {
        const parsed = try parsedFixture(&bytes, &.{split}, .{});
        try std.testing.expectEqual(ParseStatus.present, parsed.ethernet_status);
        try std.testing.expectEqual(ParseStatus.present, parsed.network_status);
        try std.testing.expectEqual(ParseStatus.present, parsed.transport_status);
        try std.testing.expectEqual(NetworkProtocol.ipv4, parsed.network_protocol);
        try std.testing.expectEqual(TransportProtocol.udp, parsed.transport_protocol);
        try std.testing.expectEqual(@as(u8, 46), parsed.ipv4.dscp);
        try std.testing.expectEqual(@as(u16, 0x1234), parsed.udp.source_port);
        try std.testing.expectEqual(@as(u16, 0x5678), parsed.udp.destination_port);
    }
}

test "M2 parsed snapshots do not expose cache storage across generations" {
    const ParseReturn = @typeInfo(@TypeOf(PacketView.parse)).@"fn".return_type.?;
    const ParsePayload = @typeInfo(ParseReturn).error_union.payload;
    try std.testing.expect(ParsePayload == ParsedPacket);

    const bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const first_token = try tracker.registerInput();
    const second_token = try tracker.registerInput();
    try first_token.receive();
    const descriptors = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&bytes)};
    var first_slots = [_]PacketSlot{try PacketSlot.init(
        first_token,
        &descriptors,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const first_batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &first_slots,
    );
    const first_view = try first_batch.view(owner, 0);
    const first_config = ParserConfig{};
    const snapshot = try first_view.parse(owner, first_config);
    try std.testing.expect(snapshot.config.eql(first_config));
    try first_batch.invalidate(owner);
    try std.testing.expectError(error.StaleView, first_view.parse(owner, first_config));
    try first_token.returnToInput();

    try second_token.receive();
    var second_bytes = bytes;
    second_bytes[22] = 31;
    const second_descriptors = [_]SegmentDescriptor{SegmentDescriptor.fromBytes(&second_bytes)};
    var second_slots = [_]PacketSlot{try PacketSlot.init(
        second_token,
        &second_descriptors,
        second_bytes.len,
        1,
        .{},
        null,
    )};
    const second_batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &second_slots,
    );
    const second_view = try second_batch.view(owner, 0);
    const second_config = ParserConfig{ .max_ipv6_extension_headers = 1 };
    const replacement = try second_view.parse(owner, second_config);
    try std.testing.expect(replacement.config.eql(second_config));
    try std.testing.expectEqual(@as(u8, 31), replacement.ipv4.ttl);
    try std.testing.expectEqual(@as(u8, 64), snapshot.ipv4.ttl);
    try std.testing.expect(snapshot.config.eql(first_config));
    try second_batch.invalidate(owner);
    try second_token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 parser distinguishes truncation VLAN bounds and IPv4 fragments" {
    const bytes = ethernetIpv4UdpFixture();
    try expectEveryPrefixTruncated(&bytes);
    const tcp = ethernetIpv4TcpFixture();
    try expectEveryPrefixTruncated(&tcp);
    const icmp = ethernetIpv4IcmpFixture();
    try expectEveryPrefixTruncated(&icmp);
    const options = ethernetIpv4OptionsUdpFixture();
    try expectEveryPrefixTruncated(&options);
    const parsed_options = try parsedFixture(&options, &.{ 13, 25, 37 }, .{});
    try std.testing.expectEqual(@as(usize, 24), parsed_options.ipv4.header_len);
    try std.testing.expectEqual(@as(u16, 0x1234), parsed_options.udp.source_port);

    const two_vlan = ethernetTwoVlanIpv4UdpFixture();
    try expectEveryPrefixTruncated(&two_vlan);
    const parsed_vlan = try parsedFixture(&two_vlan, &.{ 13, 17, 21, 37 }, .{});
    try std.testing.expectEqual(@as(u8, 2), parsed_vlan.ethernet.vlan_count);

    var fragment = bytes;
    fragment[20..22].* = .{ 0, 1 };
    const fragmented = try parsedFixture(&fragment, &.{ 13, 21, 34 }, .{});
    try std.testing.expect(fragmented.non_initial_fragment);
    try std.testing.expectEqual(ParseStatus.absent, fragmented.transport_status);

    var vlan = [_]u8{0} ** 58;
    @memcpy(vlan[0..12], bytes[0..12]);
    vlan[12..26].* = .{
        0x81, 0x00, 0, 1,
        0x88, 0xa8, 0, 2,
        0x81, 0x00, 0, 3,
        0x08, 0x00,
    };
    @memcpy(vlan[26..], bytes[14..]);
    const too_many_vlan = try parsedFixture(&vlan, &.{}, .{});
    try std.testing.expectEqual(ParseStatus.unsupported, too_many_vlan.ethernet_status);
}

test "M2 IPv4 UDP fragment parsing preserves complete initial headers only" {
    const initial = ethernetIpv4InitialUdpFragmentFixture();
    for (0..initial.len + 1) |split| {
        const parsed = try parsedFixture(&initial, &.{split}, .{});
        try std.testing.expect(!parsed.non_initial_fragment);
        try std.testing.expect(parsed.incomplete_fragment);
        try std.testing.expectEqual(ParseStatus.present, parsed.transport_status);
        try std.testing.expectEqual(TransportProtocol.udp, parsed.transport_protocol);
        try std.testing.expectEqual(@as(u16, 0x1234), parsed.udp.source_port);
        try std.testing.expectEqual(@as(u16, 0x5678), parsed.udp.destination_port);
        try std.testing.expectEqual(@as(u16, 12), parsed.udp.length);
    }

    var non_initial = initial;
    non_initial[20..22].* = .{ 0x20, 1 };
    const hidden = try parsedFixture(&non_initial, &.{ 13, 21, 34 }, .{});
    try std.testing.expect(hidden.non_initial_fragment);
    try std.testing.expectEqual(ParseStatus.absent, hidden.transport_status);

    var atomic = initial;
    atomic[20..22].* = .{ 0, 0 };
    const atomic_parsed = try parsedFixture(&atomic, &.{}, .{});
    try std.testing.expect(!atomic_parsed.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.malformed, atomic_parsed.transport_status);

    var partial = initial;
    partial[16..18].* = .{ 0, 27 };
    const truncated = try parsedFixture(partial[0 .. partial.len - 1], &.{ 34, 39 }, .{});
    try std.testing.expect(truncated.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.truncated, truncated.transport_status);

    var malformed = initial;
    malformed[38..40].* = .{ 0, 7 };
    const malformed_parsed = try parsedFixture(&malformed, &.{ 35, 39 }, .{});
    try std.testing.expect(malformed_parsed.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.malformed, malformed_parsed.transport_status);
}

fn ethernetIpv6ExtensionUdpFixture() [78]u8 {
    var bytes = [_]u8{0} ** 78;
    bytes[12..14].* = .{ 0x86, 0xdd };
    bytes[14] = 0x6a;
    bytes[15] = 0xb0;
    bytes[18..20].* = .{ 0, 24 };
    bytes[20] = 0;
    bytes[21] = 32;
    bytes[22..38].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 12;
    bytes[38..54].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 11 ++ .{1};
    bytes[54] = 60;
    bytes[55] = 0;
    bytes[62] = 17;
    bytes[63] = 0;
    bytes[70..72].* = .{ 0x11, 0x11 };
    bytes[72..74].* = .{ 0x22, 0x22 };
    bytes[74..76].* = .{ 0, 8 };
    bytes[76..78].* = .{ 0, 1 };
    return bytes;
}

fn ethernetIpv6UdpOddPayloadFixture() [67]u8 {
    var bytes = [_]u8{0} ** 67;
    bytes[12..14].* = .{ 0x86, 0xdd };
    bytes[14] = 0x60;
    bytes[18..20].* = .{ 0, 13 };
    bytes[20] = 17;
    bytes[21] = 64;
    bytes[22..38].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 12;
    bytes[38..54].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 11 ++ .{1};
    bytes[54..56].* = .{ 0x12, 0x34 };
    bytes[56..58].* = .{ 0x56, 0x78 };
    bytes[58..60].* = .{ 0, 13 };
    bytes[62..67].* = .{ 1, 2, 3, 4, 5 };
    return bytes;
}

fn ethernetIpv6InitialUdpFragmentFixture() [70]u8 {
    var bytes = [_]u8{0} ** 70;
    bytes[0..6].* = .{ 0, 1, 2, 3, 4, 5 };
    bytes[6..12].* = .{ 6, 7, 8, 9, 10, 11 };
    bytes[12..14].* = .{ 0x86, 0xdd };
    bytes[14] = 0x60;
    bytes[18..20].* = .{ 0, 16 };
    bytes[20] = 44;
    bytes[21] = 64;
    bytes[22..38].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 12;
    bytes[38..54].* = .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 11 ++ .{1};
    bytes[54] = 17;
    bytes[56..58].* = .{ 0, 1 };
    bytes[58..62].* = .{ 0, 0, 0, 1 };
    bytes[62..64].* = .{ 0x12, 0x34 };
    bytes[64..66].* = .{ 0x56, 0x78 };
    bytes[66..68].* = .{ 0, 12 };
    return bytes;
}

fn ethernetIpv6TcpOddPayloadFixture() [79]u8 {
    var bytes = [_]u8{0} ** 79;
    const udp = ethernetIpv6UdpOddPayloadFixture();
    @memcpy(bytes[0..54], udp[0..54]);
    bytes[18..20].* = .{ 0, 25 };
    bytes[20] = 6;
    bytes[54..56].* = .{ 0x12, 0x34 };
    bytes[56..58].* = .{ 0x56, 0x78 };
    bytes[66] = 0x50;
    bytes[67] = 0x10;
    bytes[74..79].* = .{ 1, 2, 3, 4, 5 };
    return bytes;
}

test "M2 IPv6 extension traversal is bounded and fragments hide L4" {
    const bytes = ethernetIpv6ExtensionUdpFixture();
    try expectEveryPrefixTruncated(&bytes);
    const parsed = try parsedFixture(&bytes, &.{ 14, 53, 55, 63, 71 }, .{});
    try std.testing.expectEqual(ParseStatus.present, parsed.network_status);
    try std.testing.expectEqual(ParseStatus.present, parsed.transport_status);
    try std.testing.expectEqual(@as(u8, 2), parsed.ipv6.extension_headers);
    try std.testing.expectEqual(@as(u16, 16), parsed.ipv6.extension_bytes);
    try std.testing.expectEqual(@as(u16, 0x1111), parsed.udp.source_port);

    const bounded = try parsedFixture(&bytes, &.{}, .{
        .max_ipv6_extension_headers = 1,
        .max_ipv6_extension_bytes = 256,
    });
    try std.testing.expectEqual(ParseStatus.unsupported, bounded.transport_status);
    try std.testing.expectError(
        error.InvalidParserLimit,
        (ParserConfig{ .max_ipv6_extension_headers = 17 }).validate(),
    );

    var fragment = bytes;
    fragment[20] = 44;
    fragment[54] = 17;
    fragment[56..58].* = .{ 0, 8 };
    const fragmented = try parsedFixture(&fragment, &.{}, .{});
    try std.testing.expect(fragmented.non_initial_fragment);
    try std.testing.expectEqual(ParseStatus.absent, fragmented.transport_status);
}

test "M2 IPv6 UDP fragment parsing preserves complete initial headers only" {
    const initial = ethernetIpv6InitialUdpFragmentFixture();
    for (0..initial.len + 1) |split| {
        const parsed = try parsedFixture(&initial, &.{split}, .{});
        try std.testing.expect(!parsed.non_initial_fragment);
        try std.testing.expect(parsed.incomplete_fragment);
        try std.testing.expectEqual(ParseStatus.present, parsed.transport_status);
        try std.testing.expectEqual(TransportProtocol.udp, parsed.transport_protocol);
        try std.testing.expectEqual(@as(u16, 0x1234), parsed.udp.source_port);
        try std.testing.expectEqual(@as(u16, 0x5678), parsed.udp.destination_port);
        try std.testing.expectEqual(@as(u16, 12), parsed.udp.length);
    }

    var non_initial = initial;
    non_initial[56..58].* = .{ 0, 9 };
    const hidden = try parsedFixture(&non_initial, &.{ 53, 57, 63 }, .{});
    try std.testing.expect(hidden.non_initial_fragment);
    try std.testing.expectEqual(ParseStatus.absent, hidden.transport_status);

    var atomic = initial;
    atomic[56..58].* = .{ 0, 0 };
    const atomic_parsed = try parsedFixture(&atomic, &.{}, .{});
    try std.testing.expect(!atomic_parsed.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.malformed, atomic_parsed.transport_status);

    var partial = initial;
    partial[18..20].* = .{ 0, 15 };
    const truncated = try parsedFixture(partial[0 .. partial.len - 1], &.{ 53, 61, 67 }, .{});
    try std.testing.expect(truncated.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.truncated, truncated.transport_status);

    var malformed = initial;
    malformed[66..68].* = .{ 0, 7 };
    const malformed_parsed = try parsedFixture(&malformed, &.{ 55, 63, 67 }, .{});
    try std.testing.expect(malformed_parsed.incomplete_fragment);
    try std.testing.expectEqual(ParseStatus.malformed, malformed_parsed.transport_status);
}

fn expectIncompleteFragmentTransportEditsRejected(
    structured_bytes: []u8,
    raw_bytes: []u8,
) !void {
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const structured_token = try tracker.registerInput();
    const raw_token = try tracker.registerInput();
    try structured_token.receive();
    try raw_token.receive();
    const structured_mutable = [_]MutableSegmentDescriptor{
        try .init(structured_bytes, 0, structured_bytes.len, .{}),
    };
    const raw_mutable = [_]MutableSegmentDescriptor{
        try .init(raw_bytes, 0, raw_bytes.len, .{}),
    };
    var slots = [_]PacketSlot{
        try PacketSlot.initMutable(
            structured_token,
            &structured_mutable,
            structured_bytes.len,
            0,
            .{},
            null,
        ),
        try PacketSlot.initMutable(raw_token, &raw_mutable, raw_bytes.len, 1, .{}, null),
    };
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);

    const structured = try batch.editor(owner, 0);
    try std.testing.expectError(
        error.IncompleteFragment,
        structured.setUdpDestinationPort(owner, 53),
    );
    try std.testing.expectError(error.InvalidJournal, structured.finalize(owner));
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));

    const parsed = try (try batch.view(owner, 1)).parse(owner, .{});
    const raw = try batch.unsafeRawEditorForTesting(owner, 1);
    try raw.write(
        owner,
        .{ .offset = parsed.udp.header_offset, .len = 2 },
        &.{ 0x12, 0x34 },
        .{ .invalidates = .{ .l4 = true } },
    );
    const raw_editor = try batch.editor(owner, 1);
    try std.testing.expectError(error.IncompleteFragment, raw_editor.finalize(owner));
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 1));

    try batch.invalidate(owner);
    try structured_token.returnToInput();
    try raw_token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 incomplete IPv4 and IPv6 fragments reject transport mutation and finalization" {
    var ipv4_structured = ethernetIpv4InitialUdpFragmentFixture();
    var ipv4_raw = ethernetIpv4InitialUdpFragmentFixture();
    try expectIncompleteFragmentTransportEditsRejected(&ipv4_structured, &ipv4_raw);

    var ipv6_structured = ethernetIpv6InitialUdpFragmentFixture();
    var ipv6_raw = ethernetIpv6InitialUdpFragmentFixture();
    try expectIncompleteFragmentTransportEditsRejected(&ipv6_structured, &ipv6_raw);
}

fn checksumIsValid(bytes: []const u8) bool {
    var sum: u64 = 0;
    var index: usize = 0;
    while (index < bytes.len) : (index += 2) {
        const high = bytes[index];
        const low = if (index + 1 < bytes.len) bytes[index + 1] else 0;
        sum += (@as(u16, high) << 8) | low;
    }
    return foldChecksum(sum) == 0;
}

fn finalizeSplitUdpPort(bytes: []u8, split: usize) !void {
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{
        try .init(bytes[0..split], 0, split, .{}),
        try .init(bytes[split..], 0, bytes.len - split, .{}),
    };
    var slots = [_]PacketSlot{try PacketSlot.initMutable(
        token,
        &mutable,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try editor.setUdpDestinationPort(owner, 53);
    try editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

fn trimOddPayloadAndFinalize(
    bytes: []const u8,
    trim_len: usize,
    expected_network: NetworkProtocol,
    expected_transport: TransportProtocol,
) !void {
    var storage = [_]u8{0} ** 128;
    @memcpy(storage[0..bytes.len], bytes);
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{
        try .init(&storage, 0, bytes.len, .{ .resize = true }),
    };
    var slots = [_]PacketSlot{try PacketSlot.initMutable(
        token,
        &mutable,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try editor.trimTail(owner, trim_len);
    try std.testing.expectError(error.UnfinalizedMutation, batch.validateForOutput(owner, 0));
    try editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    const current = try batch.outputPacket(owner, 0);
    try std.testing.expectEqual(bytes.len - trim_len, try current.length(owner));
    const parsed = try (try batch.view(owner, 0)).parse(owner, .{});
    try std.testing.expectEqual(expected_network, parsed.network_protocol);
    try std.testing.expectEqual(expected_transport, parsed.transport_protocol);
    try std.testing.expectEqual(ParseStatus.present, parsed.transport_status);
    const network_offset = if (expected_network == .ipv4)
        parsed.ipv4.header_offset
    else
        parsed.ipv6.header_offset;
    const expected_network_len = try current.length(owner) - network_offset;
    if (expected_network == .ipv4) {
        try std.testing.expectEqual(
            @as(u16, @intCast(expected_network_len)),
            parsed.ipv4.total_len,
        );
        try std.testing.expect(checksumIsValid(storage[parsed.ipv4.header_offset .. parsed.ipv4.header_offset + parsed.ipv4.header_len]));
    } else {
        try std.testing.expectEqual(
            @as(u16, @intCast(expected_network_len - 40)),
            parsed.ipv6.payload_len,
        );
    }
    const transport_offset = if (expected_transport == .udp)
        parsed.udp.header_offset
    else
        parsed.tcp.header_offset;
    const expected_transport_len = try current.length(owner) - transport_offset;
    if (expected_transport == .udp)
        try std.testing.expectEqual(@as(u16, @intCast(expected_transport_len)), parsed.udp.length);
    const checksum_offset = transport_offset + @as(usize, if (expected_transport == .udp) 6 else 16);
    const checksum_bytes: *const [2]u8 = @ptrCast(&storage[checksum_offset]);
    try std.testing.expect(std.mem.readInt(u16, checksum_bytes, .big) != 0);
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-007 FR-PKT-008 FR-TEST-003 INV-PKT-005 structured mutation crosses segments and finalizes checksums" {
    var bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const split: usize = 37;
    const mutable = [_]MutableSegmentDescriptor{
        try .init(bytes[0..split], 0, split, .{}),
        try .init(bytes[split..], 0, bytes.len - split, .{}),
    };
    var slots = [_]PacketSlot{try PacketSlot.initMutable(
        token,
        &mutable,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try editor.setEthernetSource(owner, .{ 10, 11, 12, 13, 14, 15 });
    try editor.setIpv4Dscp(owner, 7);
    try editor.setIpv4Ttl(owner, 31);
    try editor.setIpv4Source(owner, .{ 203, 0, 113, 9 });
    try editor.setUdpSourcePort(owner, 9999);
    try editor.setUdpDestinationPort(owner, 53);
    try std.testing.expectError(error.UnfinalizedMutation, batch.validateForOutput(owner, 0));
    const before_finalize = try batch.mutationJournal(owner, 0);
    try std.testing.expect(before_finalize.cache_invalidated);
    try std.testing.expect(before_finalize.checksums.ipv4_header);
    try std.testing.expect(before_finalize.checksums.transport);
    try editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    try std.testing.expectEqualSlices(u8, &.{ 10, 11, 12, 13, 14, 15 }, bytes[6..12]);
    try std.testing.expectEqual(@as(u8, 7), bytes[15] >> 2);
    try std.testing.expectEqual(@as(u8, 31), bytes[22]);
    try std.testing.expectEqualSlices(u8, &.{ 203, 0, 113, 9 }, bytes[26..30]);
    try std.testing.expectEqual(@as(u16, 9999), std.mem.readInt(u16, bytes[34..36], .big));
    try std.testing.expectEqual(@as(u16, 53), std.mem.readInt(u16, bytes[36..38], .big));
    try std.testing.expect(checksumIsValid(bytes[14..34]));
    try std.testing.expect(std.mem.readInt(u16, bytes[40..42], .big) != 0);

    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 finalizer excludes Ethernet padding across segment splits" {
    var unpadded = ethernetIpv4UdpFixture();
    var padded = [_]u8{0} ** 50;
    @memcpy(padded[0..unpadded.len], &unpadded);
    padded[46..50].* = .{ 0xde, 0xad, 0xbe, 0xef };
    const padding = padded[46..50].*;

    try finalizeSplitUdpPort(&unpadded, 37);
    try finalizeSplitUdpPort(&padded, 41);
    try std.testing.expectEqualSlices(u8, &unpadded, padded[0..unpadded.len]);
    try std.testing.expectEqualSlices(u8, &padding, padded[46..50]);
}

test "M2 tail trim transactionally finalizes odd IPv4 and IPv6 TCP UDP payloads" {
    const ipv4_udp = ethernetIpv4UdpFixture();
    try trimOddPayloadAndFinalize(&ipv4_udp, 1, .ipv4, .udp);
    const ipv4_tcp = ethernetIpv4TcpOddPayloadFixture();
    try trimOddPayloadAndFinalize(&ipv4_tcp, 2, .ipv4, .tcp);
    const ipv6_udp = ethernetIpv6UdpOddPayloadFixture();
    try trimOddPayloadAndFinalize(&ipv6_udp, 2, .ipv6, .udp);
    const ipv6_tcp = ethernetIpv6TcpOddPayloadFixture();
    try trimOddPayloadAndFinalize(&ipv6_tcp, 2, .ipv6, .tcp);
}

test "M2 finalizer preserves legal IPv4 UDP zero and repairs IPv6 UDP zero" {
    var ipv4 = ethernetIpv4UdpFixture();
    var ipv6 = ethernetIpv6UdpOddPayloadFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const token_v4 = try tracker.registerInput();
    const token_v6 = try tracker.registerInput();
    try token_v4.receive();
    try token_v6.receive();
    const mutable_v4 = [_]MutableSegmentDescriptor{try .init(&ipv4, 0, ipv4.len, .{})};
    const mutable_v6 = [_]MutableSegmentDescriptor{try .init(&ipv6, 0, ipv6.len, .{})};
    var slots = [_]PacketSlot{
        try PacketSlot.initMutable(token_v4, &mutable_v4, ipv4.len, 0, .{}, null),
        try PacketSlot.initMutable(token_v6, &mutable_v6, ipv6.len, 1, .{}, null),
    };
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);

    const editor_v4 = try batch.editor(owner, 0);
    try editor_v4.setIpv4Ttl(owner, 31);
    try editor_v4.finalize(owner);
    try batch.validateForOutput(owner, 0);
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, ipv4[40..42], .big));

    try std.testing.expectError(error.InvalidIpv6UdpZero, batch.validateForOutput(owner, 1));
    const editor_v6 = try batch.editor(owner, 1);
    try editor_v6.setIpv6HopLimit(owner, 31);
    try editor_v6.finalize(owner);
    try batch.validateForOutput(owner, 1);
    try std.testing.expect(std.mem.readInt(u16, ipv6[60..62], .big) != 0);

    try batch.invalidate(owner);
    try token_v4.returnToInput();
    try token_v6.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 inconsistent declared extents fail before finalizer header writes" {
    var bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{try .init(&bytes, 0, bytes.len, .{})};
    var slots = [_]PacketSlot{try PacketSlot.initMutable(token, &mutable, bytes.len, 0, .{}, null)};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try editor.setIpv4Ttl(owner, 31);
    const raw = try batch.unsafeRawEditorForTesting(owner, 0);
    try raw.write(
        owner,
        .{ .offset = 16, .len = 2 },
        &.{ 0xff, 0xff },
        .{ .full_software_validation = true },
    );
    const before_finalize = bytes;
    try std.testing.expectError(error.InvalidPacket, editor.finalize(owner));
    try std.testing.expectEqualSlices(u8, &before_finalize, &bytes);
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 mutation failure injection and segmented resize fail closed unchanged" {
    var bytes = ethernetIpv4UdpFixture();
    const original = bytes;
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{
        try .init(bytes[0..20], 0, 20, .{}),
        try .init(bytes[20..], 0, bytes.len - 20, .{}),
    };
    var slots = [_]PacketSlot{try PacketSlot.initMutable(token, &mutable, bytes.len, 0, .{}, null)};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    owner.injectMutationFailure(0);
    try std.testing.expectError(error.InjectedFailure, editor.setIpv4Ttl(owner, 1));
    try std.testing.expectEqualSlices(u8, &original, &bytes);
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));
    try std.testing.expectError(error.InvalidJournal, editor.finalize(owner));
    try std.testing.expectError(error.ResizeRequiresLinear, editor.append(owner, &.{1}));
    try std.testing.expectEqualSlices(u8, &original, &bytes);
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 linear append and balanced prepend trim update active range atomically" {
    const packet_bytes = ethernetIpv4UdpFixture();
    var storage = [_]u8{0} ** 64;
    @memcpy(storage[4 .. 4 + packet_bytes.len], &packet_bytes);
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{
        try .init(&storage, 4, packet_bytes.len, .{ .resize = true }),
    };
    var slots = [_]PacketSlot{try PacketSlot.initMutable(token, &mutable, packet_bytes.len, 0, .{}, null)};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try editor.prepend(owner, &.{ 0xaa, 0xbb });
    try editor.trimHead(owner, 2);
    try editor.append(owner, &.{ 5, 6 });
    try editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    const current = try batch.outputPacket(owner, 0);
    try std.testing.expectEqual(packet_bytes.len + 2, try current.length(owner));
    try std.testing.expectEqual(@as(u16, 34), std.mem.readInt(u16, storage[4 + 16 .. 4 + 18], .big));
    try std.testing.expectEqual(@as(u16, 14), std.mem.readInt(u16, storage[4 + 38 .. 4 + 40], .big));
    const before_failure = storage;
    const too_large = [_]u8{0} ** 20;
    try std.testing.expectError(error.InsufficientTailroom, editor.append(owner, &too_large));
    try std.testing.expectEqualSlices(u8, &before_failure, &storage);
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 insufficient headroom preserves bytes length and descriptor then fails closed" {
    var storage = ethernetIpv4UdpFixture();
    const original = storage;
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{
        try .init(&storage, 0, storage.len, .{ .resize = true }),
    };
    var slots = [_]PacketSlot{
        try PacketSlot.initMutable(token, &mutable, storage.len, 0, .{}, null),
    };
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    try batch.validateForOutput(owner, 0);

    const before_packet = try batch.outputPacket(owner, 0);
    const before_length = try before_packet.length(owner);
    const before_descriptor = ownerImpl(owner).slots[0].mutable_storage[0].?;
    const before_journal = try batch.mutationJournal(owner, 0);
    try std.testing.expectError(error.InsufficientHeadroom, editor.prepend(owner, &.{0xaa}));

    const after_packet = try batch.outputPacket(owner, 0);
    const after_descriptor = ownerImpl(owner).slots[0].mutable_storage[0].?;
    const after_journal = try batch.mutationJournal(owner, 0);
    try std.testing.expectEqualSlices(u8, &original, &storage);
    try std.testing.expectEqual(before_length, try after_packet.length(owner));
    try std.testing.expectEqual(before_descriptor.active_offset, after_descriptor.active_offset);
    try std.testing.expectEqual(before_descriptor.active_len, after_descriptor.active_len);
    try std.testing.expectEqual(before_descriptor.headroom, after_descriptor.headroom);
    try std.testing.expectEqual(before_descriptor.tailroom, after_descriptor.tailroom);
    try std.testing.expectEqual(before_descriptor.storage.ptr, after_descriptor.storage.ptr);
    try std.testing.expectEqual(before_descriptor.storage.len, after_descriptor.storage.len);
    try std.testing.expectEqualDeep(before_descriptor.capabilities, after_descriptor.capabilities);
    try std.testing.expectEqualDeep(before_journal.dirty, after_journal.dirty);
    try std.testing.expectEqual(before_journal.signed_length_delta, after_journal.signed_length_delta);
    try std.testing.expectEqual(before_journal.tail_length_delta, after_journal.tail_length_delta);
    try std.testing.expectEqualDeep(before_journal.checksums, after_journal.checksums);
    try std.testing.expect(!before_journal.invalid);
    try std.testing.expect(after_journal.invalid);
    try std.testing.expect(after_journal.edit_failed);
    try std.testing.expect(!after_journal.finalized);
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));

    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "FR-PKT-009 M2 raw mutation requires an explicit unsafe invalidation declaration" {
    var bytes = ethernetIpv4UdpFixture();
    var tracker = try TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]MutableSegmentDescriptor{try .init(&bytes, 0, bytes.len, .{})};
    var slots = [_]PacketSlot{try PacketSlot.initMutable(token, &mutable, bytes.len, 0, .{}, null)};
    const owner = try PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const raw = try batch.unsafeRawEditorForTesting(owner, 0);
    const original = bytes;
    try std.testing.expectError(
        error.MissingInvalidationDeclaration,
        raw.write(owner, .{ .offset = 22, .len = 1 }, &.{1}, .{}),
    );
    try std.testing.expectEqualSlices(u8, &original, &bytes);
    try std.testing.expectError(error.InvalidMutation, batch.validateForOutput(owner, 0));
    try batch.invalidate(owner);
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "M2 raw mutation capability rejects converted forged cross-owner and stale handles" {
    var bytes_a = ethernetIpv4UdpFixture();
    var bytes_b = ethernetIpv4UdpFixture();
    const original_a = bytes_a;
    const original_b = bytes_b;
    var tracker = try TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const token_a = try tracker.registerInput();
    const token_b = try tracker.registerInput();
    try token_a.receive();
    try token_b.receive();
    const mutable_a = [_]MutableSegmentDescriptor{try .init(&bytes_a, 0, bytes_a.len, .{})};
    const mutable_b = [_]MutableSegmentDescriptor{try .init(&bytes_b, 0, bytes_b.len, .{})};
    var slots_a = [_]PacketSlot{try PacketSlot.initMutable(token_a, &mutable_a, bytes_a.len, 0, .{}, null)};
    var slots_b = [_]PacketSlot{try PacketSlot.initMutable(token_b, &mutable_b, bytes_b.len, 0, .{}, null)};
    const owner_a = try PacketBatchOwner.init(std.testing.allocator);
    defer owner_a.deinit();
    const owner_b = try PacketBatchOwner.init(std.testing.allocator);
    defer owner_b.deinit();
    const batch_a = try owner_a.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots_a);
    const batch_b = try owner_b.begin(.{ .input_id = .init(2), .queue_id = .init(2) }, &slots_b);

    const view = try batch_a.view(owner_a, 0);
    const editor = try batch_a.editor(owner_a, 0);
    const converted_view: RawPacketEditor = @enumFromInt(@intFromEnum(view));
    const converted_editor: RawPacketEditor = @enumFromInt(@intFromEnum(editor));
    const declaration = RawWriteDeclaration{ .invalidates = .{ .l3 = true } };
    try std.testing.expectError(
        error.InvalidRawCapability,
        converted_view.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );
    try std.testing.expectError(
        error.InvalidRawCapability,
        converted_editor.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );

    const arbitrary: RawPacketEditor = @enumFromInt(encodeHandle(
        ownerImpl(owner_a).owner_identity,
        (@as(u64, 19) << view_index_bits) | raw_capability_domain,
    ));
    try std.testing.expectError(
        error.InvalidRawCapability,
        arbitrary.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );

    const superseded = try batch_a.unsafeRawEditorForTesting(owner_a, 0);
    const raw = try batch_a.unsafeRawEditorForTesting(owner_a, 0);
    const direct_domain_forge: RawPacketEditor = @enumFromInt(
        @intFromEnum(editor) | raw_capability_domain,
    );
    try std.testing.expectError(
        error.InvalidRawCapability,
        direct_domain_forge.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );
    for (1..raw_capability_derivation_attempts + 1) |enumerated_nonce| {
        const enumerated: RawPacketEditor = @enumFromInt(encodeHandle(
            ownerImpl(owner_a).owner_identity,
            (@as(u64, @intCast(enumerated_nonce)) << view_index_bits) |
                raw_capability_domain,
        ));
        try std.testing.expectError(
            error.InvalidRawCapability,
            enumerated.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
        );
    }
    try std.testing.expectError(
        error.InvalidRawCapability,
        superseded.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );
    try std.testing.expectError(
        error.InvalidRawCapability,
        raw.write(owner_b, .{ .offset = 22, .len = 1 }, &.{63}, declaration),
    );
    try std.testing.expectEqualSlices(u8, &original_b, &bytes_b);

    try raw.write(owner_a, .{ .offset = 22, .len = 1 }, &.{63}, declaration);
    try editor.finalize(owner_a);
    try batch_a.validateForOutput(owner_a, 0);
    try std.testing.expectEqual(@as(u8, 63), bytes_a[22]);
    try batch_a.invalidate(owner_a);

    const next_batch = try owner_a.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots_a);
    try std.testing.expectError(
        error.InvalidRawCapability,
        raw.write(owner_a, .{ .offset = 22, .len = 1 }, &.{62}, declaration),
    );
    try std.testing.expectEqual(@as(u8, 63), bytes_a[22]);
    try next_batch.invalidate(owner_a);
    try batch_b.invalidate(owner_b);
    try token_a.returnToInput();
    try token_b.returnToInput();
    try tracker.verifyReceivedCompleted();
    try std.testing.expect(!std.mem.eql(u8, &original_a, &bytes_a));
}
