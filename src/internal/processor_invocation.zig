// SPDX-License-Identifier: Apache-2.0
//! Package-internal processor invocation authority. This module is imported
//! directly by processor and pipeline implementation files and is deliberately
//! absent from the public `src/root.zig` namespace.

const std = @import("std");
const packet = @import("../packet/root.zig");

/// Matches the fixed M3 metadata store capacity without importing processor.
pub const max_metadata_rights = 16;

/// Pointer-free effective authority installed only after pipeline assembly.
pub const EffectiveCapabilities = struct {
    packet_access: u8,
    dispositions: u8,
    trusted_raw_edit: bool,
    monotonic_time: bool,
    outputs: [packet.DispositionGroups.max_outputs]packet.OutputId,
    output_count: usize,
    metadata_inputs: [max_metadata_rights]usize,
    metadata_input_count: usize,
    metadata_outputs: [max_metadata_rights]usize,
    metadata_output_count: usize,
};

/// One private thread-local invocation. `metadata` is erased here to avoid a
/// processor-module import cycle and is restored only inside processor code.
pub const State = struct {
    owner: *packet.PacketBatchOwner,
    batch: packet.PacketBatch,
    dispositions: packet.DispositionWriter,
    metadata: *anyopaque,
    capabilities: EffectiveCapabilities,
    context_identity: usize,
    monotonic_time_ns: u64,
    cookie: u64,
};

/// Internal invocation authentication failures surfaced through context ops.
pub const Error = error{
    InvocationAlreadyActive,
    InvocationInactive,
    InvocationExhausted,
    DescriptorMismatch,
    CapabilityViolation,
};

threadlocal var active: ?State = null;
var invocation_identity_counter = std.atomic.Value(u64).init(0);

fn TypeIdentity(comptime T: type) type {
    return struct {
        const represented_type = T;
        var marker: u8 = 0;
    };
}

fn typeIdentity(comptime T: type) usize {
    return @intFromPtr(&TypeIdentity(T).marker);
}

/// Returns the process-lifetime exact type identity used for installed
/// metadata rights. This bridge is absent from the public package namespace.
pub fn metadataIdentity(comptime Key: type) usize {
    return typeIdentity(Key);
}

fn allocateInvocationIdentity(counter: *std.atomic.Value(u64)) Error!u64 {
    var current = counter.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64)) return error.InvocationExhausted;
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

/// Mints the one call-scoped cookie. This function is unreachable through the
/// public Saint Shield module namespace.
pub fn begin(
    comptime Context: type,
    owner: *packet.PacketBatchOwner,
    batch: packet.PacketBatch,
    dispositions: packet.DispositionWriter,
    metadata: *anyopaque,
    capabilities: EffectiveCapabilities,
    monotonic_time_ns: u64,
) Error!u64 {
    if (active != null) return error.InvocationAlreadyActive;
    const cookie = try allocateInvocationIdentity(&invocation_identity_counter);
    active = .{
        .owner = owner,
        .batch = batch,
        .dispositions = dispositions,
        .metadata = metadata,
        .capabilities = capabilities,
        .context_identity = typeIdentity(Context),
        .monotonic_time_ns = monotonic_time_ns,
        .cookie = cookie,
    };
    return cookie;
}

/// Revokes the exact active cookie before pipeline execution continues.
pub fn end(cookie: u64) Error!void {
    const state = active orelse return error.InvocationInactive;
    if (cookie == 0 or state.cookie != cookie) return error.InvocationInactive;
    active = null;
}

/// Authenticates the cookie and exact private generated context type before
/// any state is returned to processor implementation code.
pub fn authenticate(comptime Context: type, cookie: u64) Error!*State {
    const state = if (active) |*value| value else return error.InvocationInactive;
    if (cookie == 0 or state.cookie != cookie) return error.InvocationInactive;
    if (state.context_identity != typeIdentity(Context)) return error.DescriptorMismatch;
    return state;
}

test "process-wide invocation identity exhausts without wrapping or reuse" {
    var counter = std.atomic.Value(u64).init(std.math.maxInt(u64) - 1);
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        try allocateInvocationIdentity(&counter),
    );
    try std.testing.expectError(
        error.InvocationExhausted,
        allocateInvocationIdentity(&counter),
    );
    try std.testing.expectError(
        error.InvocationExhausted,
        allocateInvocationIdentity(&counter),
    );
    try std.testing.expectEqual(
        std.math.maxInt(u64),
        counter.load(.monotonic),
    );
}
