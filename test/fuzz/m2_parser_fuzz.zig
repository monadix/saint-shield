// SPDX-License-Identifier: Apache-2.0
const std = @import("std");
const saint_shield = @import("saint_shield");

fn parserOutcome(parsed: *const saint_shield.packet.ParsedPacket) c_int {
    if (parsed.ethernet_status != .present and
        (parsed.network_status == .present or parsed.transport_status == .present)) return 6;
    if (parsed.network_status != .present and parsed.transport_status == .present) return 6;
    return switch (parsed.ethernet_status) {
        .present => switch (parsed.network_status) {
            .present, .absent => switch (parsed.transport_status) {
                .present, .absent => 0,
                .truncated => 1,
                .malformed => 2,
                .unsupported => 3,
                .unparsed => 5,
            },
            .truncated => 1,
            .malformed => 2,
            .unsupported => 3,
            .unparsed => 5,
        },
        .truncated => 1,
        .malformed => 2,
        .unsupported => 3,
        .absent, .unparsed => 5,
    };
}

fn run(data: [*]const u8, length: usize, inject_semantic_fault: bool) c_int {
    if (length > 4096) return 5;
    const packet = saint_shield.packet;
    var tracker = packet.TokenTracker.init(std.heap.page_allocator, 1) catch return 5;
    defer tracker.deinit();
    const token = tracker.registerInput() catch return 5;
    token.receive() catch return 5;
    const descriptor = [_]packet.SegmentDescriptor{
        packet.SegmentDescriptor.fromBytes(data[0..length]),
    };
    var slots = [_]packet.PacketSlot{packet.PacketSlot.init(
        token,
        &descriptor,
        length,
        0,
        .{},
        null,
    ) catch return 5};
    const owner = packet.PacketBatchOwner.init(std.heap.page_allocator) catch return 5;
    defer owner.deinit();
    const batch = owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots) catch return 5;
    var parsed = (batch.view(owner, 0) catch return 5).parse(owner, .{}) catch return 5;
    var digest: u64 = parsed.ethernet.vlan_count;
    digest +%= parsed.ipv4.total_len;
    digest +%= parsed.ipv6.payload_len;
    digest +%= parsed.tcp.destination_port;
    digest +%= parsed.udp.destination_port;
    std.mem.doNotOptimizeAway(digest);
    batch.invalidate(owner) catch return 5;
    token.returnToInput() catch return 5;
    tracker.verifyReceivedCompleted() catch return 5;
    if (inject_semantic_fault) {
        parsed.ethernet_status = .truncated;
        parsed.network_status = .present;
        parsed.transport_status = .present;
    }
    return parserOutcome(&parsed);
}

/// Bounded parser target. Every input status is an expected non-crashing code.
export fn saint_m2_parser_fuzz(data: [*]const u8, length: usize) c_int {
    return run(data, length, false);
}

/// Deliberately violates the Zig parser-status postcondition for harness audit.
export fn saint_m2_parser_fuzz_negative_control(data: [*]const u8, length: usize) c_int {
    return run(data, length, true);
}
