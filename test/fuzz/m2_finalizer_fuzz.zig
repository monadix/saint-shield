// SPDX-License-Identifier: Apache-2.0
const std = @import("std");
const saint_shield = @import("saint_shield");

fn snapshotCurrent(
    batch: saint_shield.packet.PacketBatch,
    owner: *saint_shield.packet.PacketBatchOwner,
    destination: []u8,
) !usize {
    const output_packet = try batch.outputPacket(owner, 0);
    if (try output_packet.length(owner) > destination.len) return error.Bounds;
    var offset: usize = 0;
    for (0..try output_packet.segmentCount(owner)) |index| {
        const segment = try output_packet.adapterSegment(owner, index);
        @memcpy(destination[offset .. offset + segment.len], segment);
        offset += segment.len;
    }
    return offset;
}

fn currentEquals(
    batch: saint_shield.packet.PacketBatch,
    owner: *saint_shield.packet.PacketBatchOwner,
    expected: []const u8,
) bool {
    const output_packet = batch.outputPacket(owner, 0) catch return false;
    if ((output_packet.length(owner) catch return false) != expected.len) return false;
    var offset: usize = 0;
    for (0..output_packet.segmentCount(owner) catch return false) |index| {
        const segment = output_packet.adapterSegment(owner, index) catch return false;
        if (!std.mem.eql(u8, segment, expected[offset .. offset + segment.len]))
            return false;
        offset += segment.len;
    }
    return offset == expected.len;
}

fn readU16(bytes: []const u8, offset: usize) ?u16 {
    if (offset > bytes.len or bytes.len - offset < 2) return null;
    return (@as(u16, bytes[offset]) << 8) | bytes[offset + 1];
}

fn addChecksumBytes(initial: u32, bytes: []const u8) u32 {
    var sum = initial;
    var index: usize = 0;
    while (index + 1 < bytes.len) : (index += 2)
        sum += (@as(u32, bytes[index]) << 8) | bytes[index + 1];
    if (index < bytes.len) sum += @as(u32, bytes[index]) << 8;
    return sum;
}

fn checksumIsValid(sum_initial: u32) bool {
    var sum = sum_initial;
    while (sum >> 16 != 0) sum = (sum & 0xffff) + (sum >> 16);
    return @as(u16, @truncate(sum)) == 0xffff;
}

fn finalizedSemanticsAreValid(
    bytes: []const u8,
    parsed: *const saint_shield.packet.ParsedPacket,
) bool {
    if (parsed.ethernet_status != .present or parsed.network_status != .present)
        return false;
    const network_offset: usize = switch (parsed.network_protocol) {
        .ipv4 => parsed.ipv4.header_offset,
        .ipv6 => parsed.ipv6.header_offset,
        .none => return false,
    };
    const network_len: usize = switch (parsed.network_protocol) {
        .ipv4 => blk: {
            const total_len = readU16(bytes, network_offset + 2) orelse return false;
            if (total_len != parsed.ipv4.total_len or
                parsed.ipv4.header_len < 20 or
                parsed.ipv4.header_len > total_len) return false;
            const header_end = std.math.add(
                usize,
                network_offset,
                parsed.ipv4.header_len,
            ) catch return false;
            if (header_end > bytes.len or
                !checksumIsValid(addChecksumBytes(0, bytes[network_offset..header_end])))
                return false;
            break :blk total_len;
        },
        .ipv6 => blk: {
            const payload_len = readU16(bytes, network_offset + 4) orelse return false;
            if (payload_len != parsed.ipv6.payload_len) return false;
            break :blk std.math.add(usize, 40, payload_len) catch return false;
        },
        .none => return false,
    };
    const network_end = std.math.add(usize, network_offset, network_len) catch return false;
    if (network_end > bytes.len) return false;
    if (parsed.transport_status != .present or
        (parsed.transport_protocol != .udp and parsed.transport_protocol != .tcp))
        return true;

    const transport_offset: usize = if (parsed.transport_protocol == .udp)
        parsed.udp.header_offset
    else
        parsed.tcp.header_offset;
    if (transport_offset > network_end) return false;
    const transport_len = network_end - transport_offset;
    if (parsed.transport_protocol == .udp) {
        const udp_len = readU16(bytes, transport_offset + 4) orelse return false;
        if (udp_len != parsed.udp.length or udp_len != transport_len or udp_len < 8)
            return false;
    } else if (transport_len < parsed.tcp.header_len) {
        return false;
    }
    if (parsed.incomplete_fragment) return true;

    const checksum_offset = transport_offset + @as(
        usize,
        if (parsed.transport_protocol == .udp) 6 else 16,
    );
    const recorded_checksum = readU16(bytes, checksum_offset) orelse return false;
    if (parsed.network_protocol == .ipv4 and
        parsed.transport_protocol == .udp and recorded_checksum == 0) return true;
    if (parsed.network_protocol == .ipv6 and
        parsed.transport_protocol == .udp and recorded_checksum == 0) return false;

    var sum: u32 = 0;
    switch (parsed.network_protocol) {
        .ipv4 => {
            if (network_offset > bytes.len or bytes.len - network_offset < 20)
                return false;
            sum = addChecksumBytes(sum, bytes[network_offset + 12 .. network_offset + 20]);
            sum += if (parsed.transport_protocol == .udp) 17 else 6;
            sum += @intCast(transport_len);
        },
        .ipv6 => {
            if (network_offset > bytes.len or bytes.len - network_offset < 40)
                return false;
            sum = addChecksumBytes(sum, bytes[network_offset + 8 .. network_offset + 40]);
            sum += @intCast(transport_len >> 16);
            sum += @intCast(transport_len & 0xffff);
            sum += if (parsed.transport_protocol == .udp) 17 else 6;
        },
        .none => return false,
    }
    sum = addChecksumBytes(sum, bytes[transport_offset..network_end]);
    return checksumIsValid(sum);
}

fn run(data: [*]const u8, length: usize, inject_semantic_fault: bool) c_int {
    if (length == 0 or length > 4096) return 4;
    const packet = saint_shield.packet;
    var storage: [4096 + 32]u8 = undefined;
    const packet_len = length - 1;
    @memcpy(storage[16 .. 16 + packet_len], data[1..length]);
    var tracker = packet.TokenTracker.init(std.heap.page_allocator, 1) catch return 5;
    defer tracker.deinit();
    const token = tracker.registerInput() catch return 5;
    token.receive() catch return 5;
    const mutable = [_]packet.MutableSegmentDescriptor{
        packet.MutableSegmentDescriptor.init(
            storage[0 .. packet_len + 32],
            16,
            packet_len,
            .{ .resize = true },
        ) catch return 5,
    };
    var slots = [_]packet.PacketSlot{packet.PacketSlot.initMutable(
        token,
        &mutable,
        packet_len,
        0,
        .{},
        null,
    ) catch return 5};
    const owner = packet.PacketBatchOwner.init(std.heap.page_allocator) catch return 5;
    defer owner.deinit();
    const batch = owner.begin(.{ .input_id = .init(1), .queue_id = .init(1) }, &slots) catch return 5;
    const editor = batch.editor(owner, 0) catch return 5;
    const operation = data[0];
    if ((operation & 0x20) != 0) owner.injectMutationFailure(0);
    const parsed = (batch.view(owner, 0) catch return 5).parse(owner, .{}) catch return 5;
    var before: [4096 + 32]u8 = undefined;
    var saw_failure = false;
    if ((operation & 0x01) != 0 and parsed.network_protocol == .ipv4) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        editor.setIpv4Ttl(owner, operation) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x02) != 0 and parsed.network_protocol == .ipv6) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        editor.setIpv6HopLimit(owner, operation) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x04) != 0 and parsed.transport_protocol == .udp) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        editor.setUdpDestinationPort(owner, @as(u16, operation) * 257) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x08) != 0 and parsed.transport_protocol == .tcp) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        editor.setTcpFlags(owner, operation) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x10) != 0) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        editor.append(owner, &.{operation}) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x40) != 0 and packet_len != 0) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        const raw = batch.unsafeRawEditorForTesting(owner, 0) catch return 5;
        raw.write(
            owner,
            .{ .offset = operation % packet_len, .len = 1 },
            &.{operation},
            .{ .full_software_validation = true },
        ) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    if ((operation & 0x80) != 0 and packet_len != 0) {
        const before_len = snapshotCurrent(batch, owner, &before) catch return 6;
        const raw = batch.unsafeRawEditorForTesting(owner, 0) catch return 5;
        raw.write(
            owner,
            .{ .offset = operation % packet_len, .len = 1 },
            &.{operation},
            .{},
        ) catch {
            saw_failure = true;
            if (!currentEquals(batch, owner, before[0..before_len])) return 6;
        };
    }
    const before_finalize_len = snapshotCurrent(batch, owner, &before) catch return 6;
    const finalized = if (editor.finalize(owner)) |_| true else |_| false;
    if (!finalized and !currentEquals(batch, owner, before[0..before_finalize_len])) return 6;

    if (inject_semantic_fault and finalized) {
        const fault_parsed = (batch.view(owner, 0) catch return 6).parse(owner, .{}) catch return 6;
        if (fault_parsed.network_status == .present and
            fault_parsed.network_protocol == .ipv4 and
            fault_parsed.ipv4.header_offset + 10 < packet_len)
        {
            storage[16 + fault_parsed.ipv4.header_offset + 10] ^= 1;
        }
    }
    const output_ready = if (batch.validateForOutput(owner, 0)) |_| true else |_| false;
    const journal = batch.mutationJournal(owner, 0) catch return 6;
    const needs_finalize = journal.dirty.l2 or journal.dirty.l3 or journal.dirty.l4 or
        journal.signed_length_delta != 0;
    if (output_ready and (!finalized or journal.invalid or journal.edit_failed or
        (needs_finalize and !journal.finalized))) return 6;
    if (!finalized and output_ready) return 6;
    if (saw_failure and output_ready) return 6;
    if (finalized and output_ready and needs_finalize) {
        const reparsed = (batch.view(owner, 0) catch return 6).parse(owner, .{}) catch return 6;
        const finalized_len = snapshotCurrent(batch, owner, &before) catch return 6;
        if (!finalizedSemanticsAreValid(before[0..finalized_len], &reparsed))
            return 6;
    }
    const current = batch.outputPacket(owner, 0) catch return 5;
    var digest: u64 = current.length(owner) catch return 5;
    for (0..current.segmentCount(owner) catch return 5) |index| {
        const segment = current.adapterSegment(owner, index) catch return 5;
        for (segment) |byte| digest +%= byte;
    }
    std.mem.doNotOptimizeAway(digest);
    batch.invalidate(owner) catch return 5;
    token.returnToInput() catch return 5;
    tracker.verifyReceivedCompleted() catch return 5;
    return 0;
}

/// Bounded structured/raw mutation and finalizer target.
export fn saint_m2_finalizer_fuzz(data: [*]const u8, length: usize) c_int {
    return run(data, length, false);
}

/// Corrupts a finalized header so the Zig semantic oracle must reject it.
export fn saint_m2_finalizer_fuzz_negative_control(data: [*]const u8, length: usize) c_int {
    return run(data, length, true);
}
