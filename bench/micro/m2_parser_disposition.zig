// SPDX-License-Identifier: Apache-2.0
//! Host-local ReleaseFast M2 parser/disposition cycle regression evidence.

const std = @import("std");
const saint_shield = @import("saint_shield");

extern fn saint_cycle_begin() u64;
extern fn saint_cycle_end() u64;

const batch_sizes = [_]usize{ 1, 4, 8, 16, 32, 64 };
const iterations: usize = 2_000;
const warmup_iterations: usize = 200;
const repetitions: usize = 5;

fn fixture() [46]u8 {
    var bytes = [_]u8{0} ** 46;
    bytes[12..14].* = .{ 0x08, 0x00 };
    bytes[14] = 0x45;
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

const Measurement = struct {
    parser_cycles_per_packet: f64,
    noop_disposition_cycles_per_packet: f64,
};

fn measure(
    owner: *saint_shield.packet.PacketBatchOwner,
    slots: []saint_shield.packet.PacketSlot,
    batch_size: usize,
    measured_iterations: usize,
) !Measurement {
    const packet = saint_shield.packet;
    const parser_start = saint_cycle_begin();
    var digest: u64 = 0;
    for (0..measured_iterations) |_| {
        const batch = try owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            slots[0..batch_size],
        );
        for (0..batch_size) |index| {
            const parsed = try (try batch.view(owner, index)).parse(owner, .{});
            digest +%= parsed.udp.destination_port;
        }
        try batch.invalidate(owner);
    }
    const parser_cycles = saint_cycle_end() - parser_start;

    const disposition_start = saint_cycle_begin();
    for (0..measured_iterations) |_| {
        const batch = try owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            slots[0..batch_size],
        );
        const writer = try packet.DispositionWriter.init(batch, owner);
        const groups = try packet.DispositionGroups.resolve(writer, owner, .{
            .outputs = &.{.init(1)},
            .default_output = .init(1),
            .continue_policy = .{ .accept = null },
        });
        digest +%= groups.outputs[0].count;
        try batch.invalidate(owner);
    }
    const disposition_cycles = saint_cycle_end() - disposition_start;
    std.mem.doNotOptimizeAway(digest);
    const packets = @as(f64, @floatFromInt(measured_iterations * batch_size));
    return .{
        .parser_cycles_per_packet = @as(f64, @floatFromInt(parser_cycles)) / packets,
        .noop_disposition_cycles_per_packet = @as(f64, @floatFromInt(disposition_cycles)) / packets,
    };
}

/// Runs the host-local M2 cycle regression benchmark.
pub fn main() !void {
    const packet = saint_shield.packet;
    const bytes = fixture();
    var tracker = try packet.TokenTracker.init(std.heap.page_allocator, packet.max_batch);
    defer tracker.deinit();
    const descriptor = [_]packet.SegmentDescriptor{packet.SegmentDescriptor.fromBytes(&bytes)};
    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    for (&slots, 0..) |*slot, index| {
        const token = try tracker.registerInput();
        try token.receive();
        slot.* = try packet.PacketSlot.init(token, &descriptor, bytes.len, index, .{}, null);
    }
    const owner = try packet.PacketBatchOwner.init(std.heap.page_allocator);
    defer owner.deinit();

    std.debug.print(
        "settings iterations={d} warmup_iterations={d} repetitions={d} claim=synthetic-regression-not-capacity\n",
        .{ iterations, warmup_iterations, repetitions },
    );
    for (batch_sizes) |batch_size| {
        _ = try measure(owner, &slots, batch_size, warmup_iterations);
        for (0..repetitions) |run| {
            const result = try measure(owner, &slots, batch_size, iterations);
            std.debug.print(
                "batch={d} run={d} parser_cycles_per_packet={d:.6} noop_disposition_cycles_per_packet={d:.6}\n",
                .{
                    batch_size,
                    run + 1,
                    result.parser_cycles_per_packet,
                    result.noop_disposition_cycles_per_packet,
                },
            );
        }
    }

    for (&slots) |slot| try slot.adapterToken().returnToInput();
    try tracker.verifyReceivedCompleted();
}
