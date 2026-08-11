// SPDX-License-Identifier: Apache-2.0
//! Narrow Scapy differential bridge for deterministic M2 fixtures.

const std = @import("std");
const saint_shield = @import("saint_shield");

/// Runs the deterministic parse or mutation oracle selected by argv.
pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    if (arguments.len != 3) return error.Usage;
    const mode = arguments[1];
    const hex = arguments[2];
    if (hex.len % 2 != 0 or hex.len / 2 > 4096) return error.InvalidHex;
    const bytes = try std.heap.page_allocator.alloc(u8, hex.len / 2);
    defer std.heap.page_allocator.free(bytes);
    _ = try std.fmt.hexToBytes(bytes, hex);

    if (std.mem.eql(u8, mode, "parse")) return parse(bytes);
    if (std.mem.eql(u8, mode, "mutate")) return mutate(bytes);
    return error.Usage;
}

fn setup(
    bytes: []u8,
    tracker: *saint_shield.packet.TokenTracker,
) !saint_shield.packet.PacketSlot {
    const packet = saint_shield.packet;
    const token = try tracker.registerInput();
    try token.receive();
    const mutable = [_]packet.MutableSegmentDescriptor{
        try .init(bytes, 0, bytes.len, .{}),
    };
    return packet.PacketSlot.initMutable(token, &mutable, bytes.len, 0, .{}, null);
}

fn parse(bytes: []u8) !void {
    const packet = saint_shield.packet;
    var tracker = try packet.TokenTracker.init(std.heap.page_allocator, 1);
    defer tracker.deinit();
    var slots = [_]packet.PacketSlot{try setup(bytes, &tracker)};
    const owner = try packet.PacketBatchOwner.init(std.heap.page_allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const parsed = try (try batch.view(owner, 0)).parse(owner, .{});
    std.debug.print(
        "{{\"length\":{d},\"ethernet\":\"{s}\",\"network\":\"{s}\",\"transport\":\"{s}\",\"network_protocol\":\"{s}\",\"transport_protocol\":\"{s}\",\"non_initial_fragment\":{},\"incomplete_fragment\":{},\"vlan_count\":{d},\"ipv4_ttl\":{d},\"ipv4_dscp\":{d},\"ipv6_hop_limit\":{d},\"ipv6_traffic_class\":{d},\"source_port\":{d},\"destination_port\":{d},\"udp_length\":{d}}}\n",
        .{
            bytes.len,
            @tagName(parsed.ethernet_status),
            @tagName(parsed.network_status),
            @tagName(parsed.transport_status),
            @tagName(parsed.network_protocol),
            @tagName(parsed.transport_protocol),
            parsed.non_initial_fragment,
            parsed.incomplete_fragment,
            parsed.ethernet.vlan_count,
            parsed.ipv4.ttl,
            parsed.ipv4.dscp,
            parsed.ipv6.hop_limit,
            parsed.ipv6.traffic_class,
            if (parsed.transport_protocol == .tcp) parsed.tcp.source_port else parsed.udp.source_port,
            if (parsed.transport_protocol == .tcp) parsed.tcp.destination_port else parsed.udp.destination_port,
            parsed.udp.length,
        },
    );
    try batch.invalidate(owner);
    try slots[0].adapterToken().returnToInput();
    try tracker.verifyReceivedCompleted();
}

fn mutate(bytes: []u8) !void {
    const packet = saint_shield.packet;
    var tracker = try packet.TokenTracker.init(std.heap.page_allocator, 1);
    defer tracker.deinit();
    var slots = [_]packet.PacketSlot{try setup(bytes, &tracker)};
    const owner = try packet.PacketBatchOwner.init(std.heap.page_allocator);
    defer owner.deinit();
    const batch = try owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots);
    const editor = try batch.editor(owner, 0);
    const parsed = try (try batch.view(owner, 0)).parse(owner, .{});
    switch (parsed.network_protocol) {
        .ipv4 => {
            try editor.setIpv4Dscp(owner, 7);
            try editor.setIpv4Ttl(owner, 31);
            try editor.setIpv4Source(owner, .{ 203, 0, 113, 9 });
            try editor.setIpv4Destination(owner, .{ 203, 0, 113, 10 });
        },
        .ipv6 => {
            try editor.setIpv6TrafficClass(owner, 0xab);
            try editor.setIpv6HopLimit(owner, 33);
            try editor.setIpv6Source(owner, .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 11 ++ .{9});
            try editor.setIpv6Destination(owner, .{ 0x20, 1, 0x0d, 0xb8 } ++ [_]u8{0} ** 11 ++ .{10});
        },
        .none => return error.UnsupportedProtocol,
    }
    switch (parsed.transport_protocol) {
        .udp => {
            try editor.setUdpSourcePort(owner, 9999);
            try editor.setUdpDestinationPort(owner, 53);
        },
        .tcp => {
            try editor.setTcpSourcePort(owner, 9999);
            try editor.setTcpDestinationPort(owner, 53);
            try editor.setTcpFlags(owner, 0x12);
        },
        else => return error.UnsupportedProtocol,
    }
    try editor.finalize(owner);
    try batch.validateForOutput(owner, 0);
    for (bytes) |byte| std.debug.print("{x:0>2}", .{byte});
    std.debug.print("\n", .{});
    try batch.invalidate(owner);
    try slots[0].adapterToken().returnToInput();
    try tracker.verifyReceivedCompleted();
}
