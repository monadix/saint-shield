// SPDX-License-Identifier: Apache-2.0
//! Native processor declarations, bounded lifecycle contracts, resource
//! accounting, typed stage metadata, and opaque call-scoped packet access.
//!
//! Processor contexts deliberately contain no owner pointer, adapter token,
//! raw slot, packet slice, or unrestricted batch state. The pipeline installs
//! one thread-local invocation for the duration of a direct `processBatch`
//! call; every context method validates the opaque invocation cookie.

const std = @import("std");
const foundation = @import("../foundation/root.zig");
const internal_invocation = @import("../internal/processor_invocation.zig");
const packet = @import("../packet/root.zig");

const ProcessorTag = enum { processor };
const ArtifactTypeTag = enum { artifact_type };
const MetricTag = enum { metric };
const EventTag = enum { event };

/// Stable processor identity. Zero is invalid at contract validation.
pub const ProcessorId = foundation.StableId(ProcessorTag);
/// Stable configuration-artifact content type.
pub const ArtifactContentTypeId = foundation.StableId(ArtifactTypeTag);
/// Stable metric schema identity. Runtime metric handles remain deferred.
pub const MetricId = foundation.StableId(MetricTag);
/// Stable event schema identity. Runtime event handles remain deferred.
pub const EventId = foundation.StableId(EventTag);

/// Exact processor source API implemented by the M3 contract.
pub const api_version: u32 = 3;

/// Packet authority visible during one `processBatch` call.
pub const PacketAccess = enum(u8) {
    metadata_only,
    read,
    structured_edit,
    trusted_raw_edit,
};

/// Terminal operations a processor may request.
pub const DispositionCapabilities = packed struct(u8) {
    accept: bool = false,
    drop: bool = false,
    redirect: bool = false,
    complete: bool = false,
    retain: bool = false,
    _reserved: u3 = 0,
};

/// Packet-path services represented in M3 declarations. Reusable state is a
/// schema/capability record only until its milestone.
pub const ServiceCapabilities = packed struct(u8) {
    monotonic_time: bool = false,
    worker_state: bool = false,
    reusable_state: bool = false,
    _reserved: u5 = 0,
};

/// State interpretation modes declared for future generation updates. M3
/// records and validates the schema; it never performs a live update.
pub const StateUpdateModes = packed struct(u8) {
    flush: bool = false,
    retain_compatible: bool = false,
    lazy_reevaluate: bool = false,
    eager_reevaluate: bool = false,
    processor_migration: bool = false,
    _reserved: u3 = 0,

    /// Returns whether at least one explicit mode is supported.
    pub fn any(self: StateUpdateModes) bool {
        return self.flush or self.retain_compatible or self.lazy_reevaluate or
            self.eager_reevaluate or self.processor_migration;
    }
};

/// Default mode chosen by a stateful descriptor. Stateless processors use
/// `none` and must not declare an update mode.
pub const DefaultStateUpdateMode = enum(u8) {
    none,
    flush,
    retain_compatible,
    lazy_reevaluate,
    eager_reevaluate,
    processor_migration,
};

/// Checked upper bounds for one direct stage call.
pub const WorkBounds = struct {
    fixed_per_batch: usize = 0,
    per_active_packet: usize = 1,
    maximum_total: usize = packet.max_batch,
};

/// Resource categories known before candidate construction.
pub const ResourceCategories = packed struct(u8) {
    prepared_memory: bool = false,
    worker_memory: bool = false,
    metadata_scratch: bool = false,
    bounded_pool: bool = false,
    _reserved: u4 = 0,
};

/// Processor-estimated memory and bounded work. All values are inclusive hard
/// maxima, not advisory observations.
pub const ResourceEstimate = struct {
    prepared_bytes: usize = 0,
    worker_bytes: usize = 0,
    bounded_pool_bytes_per_worker: usize = 0,
    maximum_batch_work: usize = 0,
};

/// Application resource ceiling checked before processor preparation.
pub const ResourceLimits = struct {
    prepared_bytes: usize,
    worker_bytes_each: usize,
    worker_bytes_total: usize,
    metadata_scratch_bytes_each: usize,
    metadata_scratch_bytes_total: usize,
    bounded_pool_bytes_each: usize = 0,
    bounded_pool_bytes_total: usize = 0,
    maximum_batch_work: usize,
    worker_count: usize,
};

/// One deterministic worker identity used during construction.
pub const WorkerDescriptor = struct {
    id: u32,
    numa_node: ?u16 = null,
};

/// Versioned, provenance-preserving configuration input.
pub const ConfigurationArtifact = struct {
    revision: u64,
    content_type: ArtifactContentTypeId,
    payload: []const u8,
    source_id: ?u64 = null,
    provenance_digest: ?[32]u8 = null,
};

/// Bounded lifecycle error categories. Processors may return only these sets.
pub const EstimateError = error{ InvalidArtifact, Overflow };
/// Bounded preparation failures exposed by the native lifecycle.
pub const PreparationError = error{
    InvalidArtifact,
    UnsupportedContentType,
    ResourceUnderestimated,
    ServiceUnavailable,
};
/// Bounded worker-instantiation failures exposed by the native lifecycle.
pub const InstantiationError = error{
    InvalidWorker,
    ResourceUnderestimated,
    ServiceUnavailable,
};
/// Exact packet-processing failures that an error policy may resolve.
pub const ProcessError = error{ InvalidPacket, CapacityExhausted, StateUnavailable };

/// Successful direct stage result. Packet effects are written only through the
/// opaque context; no authority is returned.
pub const ProcessResult = struct {
    visited_packets: u16 = 0,
    work_units: u32 = 0,
};

/// Whether the lifecycle function is statically infallible or returns the one
/// bounded `ProcessError` set.
pub const ProcessErrorMode = enum(u8) { infallible, bounded };

/// Explicit non-retaining terminal disposition used by error policies.
pub const TerminalDisposition = union(enum) {
    accept: ?packet.OutputId,
    drop: ?packet.DropReasonId,
    redirect: struct { output: packet.OutputId, metadata: ?packet.AdapterMetadataId = null },
    complete: packet.CompletionId,
};

/// Per-stage error behavior. No pipeline infers fail-open, fail-closed,
/// default disposition, or runtime-stop behavior.
pub const ErrorPolicy = union(enum) {
    infallible,
    continue_active,
    terminal_active: TerminalDisposition,
    terminal_active_and_stop: TerminalDisposition,
};

/// Declares a fixed typed metadata key set. Each key type defines `id: u32`,
/// `Value: type`, and may define `exclusive: bool` (default true).
pub fn MetadataKeys(comptime keys: anytype) type {
    return struct {
        /// Compile-time ordered metadata key types.
        pub const list = keys;
    };
}

/// Declares concrete bounded metric schema types. Each type defines
/// `id: MetricId`, `Value: type`, and `maximum_series: u16` greater than zero.
pub fn MetricDeclarations(comptime declarations: anytype) type {
    return struct {
        /// Compile-time ordered metric declaration types.
        pub const list = declarations;
    };
}

/// Declares concrete bounded event schema types. Each type defines
/// `id: EventId`, `Payload: type`, and `maximum_records_per_batch: u16` greater
/// than zero.
pub fn EventDeclarations(comptime declarations: anytype) type {
    return struct {
        /// Compile-time ordered event declaration types.
        pub const list = declarations;
    };
}

/// Public processor descriptor. Type-valued metadata sets are comptime-only;
/// no runtime map or string lookup is created.
pub const ProcessorDescriptor = struct {
    id: ProcessorId,
    api: u32 = api_version,
    packet_access: PacketAccess = .metadata_only,
    dispositions: DispositionCapabilities = .{},
    outputs: []const packet.OutputId = &.{},
    requires_artifact: bool = false,
    artifact_content_type: ?ArtifactContentTypeId = null,
    metadata_inputs: type = MetadataKeys(.{}),
    metadata_outputs: type = MetadataKeys(.{}),
    metrics: type = MetricDeclarations(.{}),
    events: type = EventDeclarations(.{}),
    services: ServiceCapabilities = .{},
    work: WorkBounds = .{},
    process_error_mode: ProcessErrorMode = .infallible,
    error_policy: ErrorPolicy = .infallible,
    update_modes: StateUpdateModes = .{},
    default_update_mode: DefaultStateUpdateMode = .none,
    resource_categories: ResourceCategories = .{},
};

/// Assembly capabilities supplied by the application.
pub const ApplicationCapabilities = struct {
    packet_access: PacketAccess = .metadata_only,
    trusted_raw_edit_opt_in: bool = false,
    available_outputs: []const packet.OutputId = &.{},
    dispositions: DispositionCapabilities = .{
        .accept = true,
        .drop = true,
        .redirect = true,
        .complete = true,
    },
    monotonic_time: bool = false,
    available_metrics: []const MetricId = &.{},
    available_events: []const EventId = &.{},
    reusable_state: bool = false,
    /// Retention is reserved for a later milestone. Any M3 descriptor that
    /// requests it is rejected regardless of this application declaration.
    retention: bool = false,
};

/// Address-stable allocator wrapper enforcing a hard live-byte maximum and
/// retaining exact peak/allocation observations.
pub const BudgetAllocator = struct {
    /// Construction allocators have one monotonic authority phase.
    pub const Phase = enum { construction, sealed, cleanup };

    child: std.mem.Allocator,
    limit: usize,
    current: usize = 0,
    peak: usize = 0,
    allocations: usize = 0,
    frees: usize = 0,
    denied: usize = 0,
    phase: Phase = .construction,

    /// Creates an allocation-free accounting wrapper.
    pub fn init(child: std.mem.Allocator, limit: usize) BudgetAllocator {
        return .{ .child = child, .limit = limit };
    }

    /// Returns the stable wrapper allocator. The wrapper must not move while
    /// any allocation obtained through it remains live.
    pub fn allocator(self: *BudgetAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{
            .alloc = allocate,
            .resize = resize,
            .remap = remap,
            .free = free,
        } };
    }

    /// Irrevocably removes allocation/reallocation authority after a
    /// successful construction callback.
    pub fn seal(self: *BudgetAllocator) void {
        std.debug.assert(self.phase == .construction);
        self.phase = .sealed;
    }

    /// Opens only the owner-mediated cleanup phase. New allocation remains
    /// denied and frees are accepted solely while cleanup is active.
    pub fn beginCleanup(self: *BudgetAllocator) void {
        std.debug.assert(self.phase == .sealed or self.phase == .construction);
        self.phase = .cleanup;
    }

    /// Closes cleanup authority after the lifecycle destructor returns.
    pub fn endCleanup(self: *BudgetAllocator) void {
        std.debug.assert(self.phase == .cleanup);
        self.phase = .sealed;
    }

    fn context(raw: *anyopaque) *BudgetAllocator {
        return @ptrCast(@alignCast(raw));
    }

    fn canGrow(self: *BudgetAllocator, amount: usize) bool {
        if (self.phase != .construction) {
            self.denied += 1;
            return false;
        }
        const next = std.math.add(usize, self.current, amount) catch {
            self.denied += 1;
            return false;
        };
        if (next > self.limit) {
            self.denied += 1;
            return false;
        }
        return true;
    }

    fn allocate(raw: *anyopaque, len: usize, alignment: std.mem.Alignment, ra: usize) ?[*]u8 {
        const self = context(raw);
        if (!self.canGrow(len)) return null;
        const result = self.child.rawAlloc(len, alignment, ra) orelse return null;
        self.current += len;
        self.peak = @max(self.peak, self.current);
        self.allocations += 1;
        return result;
    }

    fn resize(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) bool {
        const self = context(raw);
        if (self.phase != .construction) {
            self.denied += 1;
            return false;
        }
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) return false;
        if (!self.child.rawResize(memory, alignment, new_len, ra)) return false;
        if (new_len >= memory.len) self.current += new_len - memory.len else self.current -= memory.len - new_len;
        self.peak = @max(self.peak, self.current);
        return true;
    }

    fn remap(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self = context(raw);
        if (self.phase != .construction) {
            self.denied += 1;
            return null;
        }
        if (new_len > memory.len and !self.canGrow(new_len - memory.len)) return null;
        const result = self.child.rawRemap(memory, alignment, new_len, ra) orelse return null;
        if (new_len >= memory.len) self.current += new_len - memory.len else self.current -= memory.len - new_len;
        self.peak = @max(self.peak, self.current);
        return result;
    }

    fn free(raw: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ra: usize) void {
        const self = context(raw);
        if (self.phase == .sealed) {
            self.denied += 1;
            return;
        }
        self.child.rawFree(memory, alignment, ra);
        std.debug.assert(memory.len <= self.current);
        self.current -= memory.len;
        self.frees += 1;
    }
};

/// Fixed typed per-batch metadata storage. Values are copied into bounded
/// inline slots; validity is one selection bitset per key.
pub const MetadataStore = struct {
    /// Maximum typed keys retained in one fixed metadata store.
    pub const max_keys = 16;
    /// Maximum inline byte size of one metadata value.
    pub const max_value_size = 32;

    const Slot = struct {
        id: u32 = 0,
        type_fingerprint: u64 = 0,
        value_size: u8 = 0,
        validity: packet.PacketSelection = @enumFromInt(0),
        values: [packet.max_batch][max_value_size]u8 align(16) = undefined,
    };

    slots: [max_keys]Slot = [_]Slot{.{}} ** max_keys,
    count: usize = 0,
    batch_len: usize = 0,

    /// Metadata access errors remain bounded and allocation-free.
    pub const Error = error{ TooManyKeys, ValueTooLarge, UnknownKey, TypeConflict, OutOfRange };

    /// Clears all validity and installs one compile-time key layout.
    pub fn reset(self: *MetadataStore, comptime KeyTypes: anytype, batch_len: usize) Error!void {
        if (batch_len > packet.max_batch) return error.OutOfRange;
        if (KeyTypes.len > max_keys) return error.TooManyKeys;
        self.count = KeyTypes.len;
        self.batch_len = batch_len;
        inline for (KeyTypes, 0..) |Key, index| {
            validateKeyType(Key);
            if (@sizeOf(Key.Value) > max_value_size) return error.ValueTooLarge;
            self.slots[index].id = Key.id;
            self.slots[index].type_fingerprint = typeFingerprint(Key.Value);
            self.slots[index].value_size = @intCast(@sizeOf(Key.Value));
            self.slots[index].validity = @enumFromInt(0);
        }
    }

    fn find(self: *MetadataStore, comptime Key: type) Error!*Slot {
        validateKeyType(Key);
        for (self.slots[0..self.count]) |*slot| {
            if (slot.id != Key.id) continue;
            if (slot.type_fingerprint != typeFingerprint(Key.Value)) return error.TypeConflict;
            return slot;
        }
        return error.UnknownKey;
    }

    /// Stores one typed value and marks exactly that packet valid.
    pub fn put(self: *MetadataStore, comptime Key: type, index: usize, value: Key.Value) Error!void {
        const checked = packet.PacketIndex.init(index, self.batch_len) catch return error.OutOfRange;
        const slot = try self.find(Key);
        const bytes = std.mem.asBytes(&value);
        @memcpy(slot.values[index][0..bytes.len], bytes);
        slot.validity = @enumFromInt(
            @intFromEnum(slot.validity) | (@as(u64, 1) << @intCast(checked.raw())),
        );
    }

    /// Returns a typed value only when the key and packet are valid.
    pub fn get(self: *MetadataStore, comptime Key: type, index: usize) Error!?Key.Value {
        const checked = packet.PacketIndex.init(index, self.batch_len) catch return error.OutOfRange;
        const slot = try self.find(Key);
        if (!(slot.validity.contains(checked, self.batch_len) catch return error.OutOfRange))
            return null;
        var value: Key.Value = undefined;
        @memcpy(std.mem.asBytes(&value), slot.values[index][0..@sizeOf(Key.Value)]);
        return value;
    }

    /// Returns the validity selection by value.
    pub fn validity(self: *MetadataStore, comptime Key: type) Error!packet.PacketSelection {
        return (try self.find(Key)).validity;
    }
};

fn validateKeyType(comptime Key: type) void {
    if (!@hasDecl(Key, "id")) @compileError("metadata key missing id");
    if (!@hasDecl(Key, "Value")) @compileError("metadata key missing Value");
    if (@TypeOf(Key.id) != u32) @compileError("metadata key id must be u32");
    validateInlineValueType(Key.Value, "metadata value");
}

/// Rejects every type that can copy or retain storage, callback, allocator, or
/// other lifetime-bearing authority through an inline declaration value.
pub fn validateInlineValueType(comptime T: type, comptime label: []const u8) void {
    switch (@typeInfo(T)) {
        .pointer, .@"fn", .frame, .@"anyframe" => @compileError(label ++ " must not contain pointer, slice, function, or frame authority"),
        .array => |info| validateInlineValueType(info.child, label),
        .vector => |info| validateInlineValueType(info.child, label),
        .optional => |info| validateInlineValueType(info.child, label),
        .@"struct" => |info| inline for (info.fields) |field|
            validateInlineValueType(field.type, label),
        .@"union" => |info| inline for (info.fields) |field|
            validateInlineValueType(field.type, label),
        .error_union => |info| {
            validateInlineValueType(info.error_set, label);
            validateInlineValueType(info.payload, label);
        },
        .type, .comptime_float, .comptime_int, .enum_literal, .undefined, .null, .noreturn, .@"opaque" => @compileError(label ++ " must be a runtime inline value"),
        else => {},
    }
}

fn typeFingerprint(comptime T: type) u64 {
    return std.hash.Wyhash.hash(0x4d33_5459_5045, @typeName(T));
}

/// Checked-arithmetic helpers used by the pipeline aggregation pass.
pub fn checkedAdd(left: usize, right: usize) error{Overflow}!usize {
    return std.math.add(usize, left, right) catch error.Overflow;
}

/// Checked-arithmetic helpers used by worker-count aggregation.
pub fn checkedMul(left: usize, right: usize) error{Overflow}!usize {
    return std.math.mul(usize, left, right) catch error.Overflow;
}

/// Computes the exact fixed metadata-store footprint. The key layout is still
/// validated even though M3 uses one fixed-capacity store per worker.
pub fn metadataScratchBytes(comptime KeyTypes: anytype) error{Overflow}!usize {
    inline for (KeyTypes) |Key| {
        validateKeyType(Key);
        if (@sizeOf(Key.Value) > MetadataStore.max_value_size)
            @compileError("metadata value exceeds fixed M3 slot size");
    }
    return @sizeOf(MetadataStore);
}

fn invocation(
    cookie: u64,
    comptime Context: type,
) internal_invocation.Error!*internal_invocation.State {
    return internal_invocation.authenticate(Context, cookie);
}

fn metadataStore(state: *internal_invocation.State) *MetadataStore {
    return @ptrCast(@alignCast(state.metadata));
}

fn requireRuntimeAccess(
    state: *const internal_invocation.State,
    required: PacketAccess,
) internal_invocation.Error!void {
    if (state.capabilities.packet_access < @intFromEnum(required))
        return error.CapabilityViolation;
}

fn requireRuntimeDisposition(
    state: *const internal_invocation.State,
    comptime field: enum { accept, drop, redirect, complete },
) internal_invocation.Error!void {
    const allowed = switch (field) {
        .accept => (@as(DispositionCapabilities, @bitCast(state.capabilities.dispositions))).accept,
        .drop => (@as(DispositionCapabilities, @bitCast(state.capabilities.dispositions))).drop,
        .redirect => (@as(DispositionCapabilities, @bitCast(state.capabilities.dispositions))).redirect,
        .complete => (@as(DispositionCapabilities, @bitCast(state.capabilities.dispositions))).complete,
    };
    if (!allowed) return error.CapabilityViolation;
}

fn requireRuntimeMetadata(
    state: *const internal_invocation.State,
    comptime Key: type,
    comptime direction: enum { input, output },
) internal_invocation.Error!void {
    const identity = internal_invocation.metadataIdentity(Key);
    const allowed = switch (direction) {
        .input => state.capabilities.metadata_inputs[0..state.capabilities.metadata_input_count],
        .output => state.capabilities.metadata_outputs[0..state.capabilities.metadata_output_count],
    };
    for (allowed) |candidate| if (candidate == identity) return;
    return error.CapabilityViolation;
}

fn runtimeInstalledOutput(
    capabilities: *const internal_invocation.EffectiveCapabilities,
    output: packet.OutputId,
) bool {
    for (capabilities.outputs[0..capabilities.output_count]) |candidate|
        if (candidate.raw() == output.raw()) return true;
    return false;
}

/// Generates the exact processor-visible batch context from its declaration.
/// Its sole stored value is an opaque cookie; all packet authority is scoped
/// inside the pipeline-owned invocation record.
pub fn ProcessContext(comptime descriptor: ProcessorDescriptor) type {
    return enum(u64) {
        _,

        const Self = @This();

        /// Errors exposed by declared context operations.
        pub const Error = internal_invocation.Error || packet.PacketBatch.Error ||
            packet.DispositionWriter.Error || packet.ViewError || packet.MutationError ||
            packet.FinalizeError || MetadataStore.Error || error{UndeclaredOutput};

        /// Returns the active selection by value.
        pub fn active(self: Self) Error!packet.PacketSelection {
            const state = try invocation(@intFromEnum(self), Self);
            return state.dispositions.activeSelection(state.owner);
        }

        /// Returns the actual partial-batch size.
        pub fn len(self: Self) Error!usize {
            const state = try invocation(@intFromEnum(self), Self);
            return state.batch.len(state.owner);
        }

        /// Returns input origin by value.
        pub fn origin(self: Self) Error!packet.InputOrigin {
            const state = try invocation(@intFromEnum(self), Self);
            return state.batch.origin(state.owner);
        }

        /// Returns deterministic monotonic time only when declared.
        pub fn monotonicTimeNs(self: Self) Error!u64 {
            if (!descriptor.services.monotonic_time)
                @compileError("processor did not declare monotonic-time capability");
            const state = try invocation(@intFromEnum(self), Self);
            if (!state.capabilities.monotonic_time) return error.CapabilityViolation;
            return state.monotonic_time_ns;
        }

        /// Reads a fixed typed stage/input metadata value.
        pub fn metadata(self: Self, comptime Key: type, index: usize) Error!?Key.Value {
            comptime requireDeclaredKey(descriptor.metadata_inputs.list, Key, "metadata input");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeMetadata(state, Key, .input);
            return metadataStore(state).get(Key, index);
        }

        /// Produces one fixed typed metadata value for later stages.
        pub fn produceMetadata(self: Self, comptime Key: type, index: usize, value: Key.Value) Error!void {
            comptime requireDeclaredKey(descriptor.metadata_outputs.list, Key, "metadata output");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeMetadata(state, Key, .output);
            try metadataStore(state).put(Key, index, value);
        }

        /// Copies checked packet bytes; no raw slice can escape the call.
        pub fn read(self: Self, index: usize, range: packet.ByteRange, destination: []u8) Error!void {
            if (@intFromEnum(descriptor.packet_access) < @intFromEnum(PacketAccess.read))
                @compileError("processor did not declare packet read capability");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeAccess(state, .read);
            const view = try state.batch.view(state.owner, index);
            try view.read(state.owner, range, destination);
        }

        /// Returns packet length by value after checked view validation.
        pub fn packetLength(self: Self, index: usize) Error!usize {
            if (@intFromEnum(descriptor.packet_access) < @intFromEnum(PacketAccess.read))
                @compileError("processor did not declare packet read capability");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeAccess(state, .read);
            return (try state.batch.view(state.owner, index)).length(state.owner);
        }

        /// Performs one structured IPv4 TTL edit.
        pub fn setIpv4Ttl(self: Self, index: usize, value: u8) Error!void {
            if (@intFromEnum(descriptor.packet_access) < @intFromEnum(PacketAccess.structured_edit))
                @compileError("processor did not declare structured-edit capability");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeAccess(state, .structured_edit);
            try (try state.batch.editor(state.owner, index)).setIpv4Ttl(state.owner, value);
        }

        /// Finalizes structured or trusted raw edits before output.
        pub fn finalize(self: Self, index: usize) Error!void {
            if (@intFromEnum(descriptor.packet_access) < @intFromEnum(PacketAccess.structured_edit))
                @compileError("processor did not declare edit capability");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeAccess(state, .structured_edit);
            try (try state.batch.editor(state.owner, index)).finalize(state.owner);
        }

        /// Performs a trusted raw edit only when descriptor and application
        /// assembly both opted in. Returned authority is never exposed.
        pub fn trustedRawWrite(
            self: Self,
            index: usize,
            range: packet.ByteRange,
            bytes: []const u8,
            declaration: packet.RawWriteDeclaration,
        ) Error!void {
            if (descriptor.packet_access != .trusted_raw_edit)
                @compileError("processor did not declare trusted raw-edit capability");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeAccess(state, .trusted_raw_edit);
            if (!state.capabilities.trusted_raw_edit) return error.CapabilityViolation;
            const editor = try state.batch.unsafeRawEditorForTesting(state.owner, index);
            try editor.write(state.owner, range, bytes, declaration);
        }

        /// Applies a declared accept terminal disposition.
        pub fn accept(self: Self, selection: packet.PacketSelection, output: ?packet.OutputId) Error!void {
            if (!descriptor.dispositions.accept) @compileError("processor did not declare Accept");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeDisposition(state, .accept);
            if (output) |id| {
                if (!runtimeDeclaredOutput(descriptor.outputs, id) or
                    !runtimeInstalledOutput(&state.capabilities, id))
                    return error.UndeclaredOutput;
            }
            try state.dispositions.setSelection(state.owner, selection, .{ .Accept = output });
        }

        /// Applies a declared drop terminal disposition.
        pub fn drop(self: Self, selection: packet.PacketSelection, reason: ?packet.DropReasonId) Error!void {
            if (!descriptor.dispositions.drop) @compileError("processor did not declare Drop");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeDisposition(state, .drop);
            try state.dispositions.setSelection(state.owner, selection, .{ .Drop = reason });
        }

        /// Applies a declared redirect terminal disposition.
        pub fn redirect(
            self: Self,
            selection: packet.PacketSelection,
            output: packet.OutputId,
            metadata_id: ?packet.AdapterMetadataId,
        ) Error!void {
            if (!descriptor.dispositions.redirect) @compileError("processor did not declare Redirect");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeDisposition(state, .redirect);
            if (!runtimeDeclaredOutput(descriptor.outputs, output) or
                !runtimeInstalledOutput(&state.capabilities, output))
                return error.UndeclaredOutput;
            try state.dispositions.setSelection(state.owner, selection, .{ .Redirect = .{
                .output = output,
                .metadata = metadata_id,
            } });
        }

        /// Applies a declared custom completion terminal disposition.
        pub fn complete(self: Self, selection: packet.PacketSelection, id: packet.CompletionId) Error!void {
            if (!descriptor.dispositions.complete) @compileError("processor did not declare Complete");
            const state = try invocation(@intFromEnum(self), Self);
            try requireRuntimeDisposition(state, .complete);
            try state.dispositions.setSelection(state.owner, selection, .{ .Complete = id });
        }
    };
}

fn requireDeclaredKey(comptime keys: anytype, comptime Key: type, comptime label: []const u8) void {
    inline for (keys) |candidate| if (candidate == Key) return;
    @compileError("processor used undeclared " ++ label ++ " key " ++ @typeName(Key));
}

fn runtimeDeclaredOutput(outputs: []const packet.OutputId, output: packet.OutputId) bool {
    for (outputs) |candidate| if (candidate.raw() == output.raw()) return true;
    return false;
}

test "budget allocator enforces exact live-byte estimate and returns to zero" {
    var budget = BudgetAllocator.init(std.testing.allocator, 8);
    const allocator = budget.allocator();
    const bytes = try allocator.alloc(u8, 8);
    try std.testing.expectEqual(@as(usize, 8), budget.current);
    try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 1));
    try std.testing.expectEqual(@as(usize, 1), budget.denied);
    allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 0), budget.current);
}

test "sealed budget allocator rejects retained growth remap shrink and free until cleanup" {
    var budget = BudgetAllocator.init(std.testing.allocator, 16);
    const allocator = budget.allocator();
    const bytes = try allocator.alloc(u8, 8);
    budget.seal();
    try std.testing.expectError(error.OutOfMemory, allocator.alloc(u8, 1));
    try std.testing.expect(!allocator.resize(bytes, 4));
    try std.testing.expect(allocator.remap(bytes, 4) == null);
    allocator.free(bytes);
    try std.testing.expectEqual(@as(usize, 8), budget.current);
    try std.testing.expectEqual(@as(usize, 4), budget.denied);
    budget.beginCleanup();
    allocator.free(bytes);
    budget.endCleanup();
    try std.testing.expectEqual(@as(usize, 0), budget.current);
}

test "fixed metadata keeps per-packet validity and typed values" {
    const Key = struct {
        /// Stable test metadata identity.
        pub const id: u32 = 7;
        /// Test metadata value type.
        pub const Value = u16;
    };
    var store = MetadataStore{};
    try store.reset(.{Key}, 3);
    try store.put(Key, 1, 0xbeef);
    try std.testing.expectEqual(@as(?u16, null), try store.get(Key, 0));
    try std.testing.expectEqual(@as(?u16, 0xbeef), try store.get(Key, 1));
    try std.testing.expectEqual(@as(usize, 1), (try store.validity(Key)).count());
}
