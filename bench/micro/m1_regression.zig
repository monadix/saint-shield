// SPDX-License-Identifier: Apache-2.0
//! Deterministic M1 traversal regression; never a production capacity result.

const std = @import("std");
const saint_shield = @import("saint_shield");
const expected_artifact_json = @embedFile("benchmark_m1_json");

const ExpectedArtifact = struct {
    application: struct {
        batch_max: usize,
        resources: struct {
            configured_max_packet_bytes: usize,
        },
    },
    result: struct {
        perf: struct {
            traversed_packets: usize,
            traversed_payload_bytes: usize,
            receive_calls: usize,
            submit_calls: usize,
            borrowed_segment_operations: usize,
            pre_receive_identity_matches: usize,
            abstraction_payload_copy_bytes: usize,
            allocation_guard_negative_control: bool,
            copy_guard_negative_control: bool,
        },
        memory_bytes: struct {
            packet_path_general_allocations: usize,
        },
    },
};

/// Traverses linear and segmented fixtures for every configured size.
pub fn main() !void {
    const packet = saint_shield.packet;
    const synthetic = saint_shield.io.synthetic;
    const configured_max: usize = 256;
    const traversal_count = (configured_max + 1) * 2;
    const max_fixture_segments = 6;

    var counting_allocator = synthetic.CountingAllocator.init(std.heap.page_allocator);
    const observed_allocator = counting_allocator.allocator();
    var input = try synthetic.InputQueue.init(observed_allocator, .{
        .capacity = traversal_count,
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

    var pre_receive_identities: [traversal_count][max_fixture_segments]synthetic.SegmentIdentity = undefined;
    var pre_receive_segment_counts: [traversal_count]usize = undefined;
    for (0..traversal_count) |record_index| {
        const segment_count = try input.queuedSegmentCount(record_index);
        pre_receive_segment_counts[record_index] = segment_count;
        for (0..segment_count) |segment_index|
            pre_receive_identities[record_index][segment_index] =
                try input.queuedSegmentIdentity(record_index, segment_index);
    }

    var output = try synthetic.OutputQueue.init(observed_allocator, traversal_count);
    defer output.deinit();
    const allocator_before = counting_allocator.snapshot();
    const packet_path_before = input.packetPathSnapshot();
    var slots: [packet.max_batch]packet.PacketSlot = undefined;
    var accepted: usize = 0;
    var identity_matches: usize = 0;
    while (accepted < traversal_count) {
        const count = try input.receive(&slots, packet.max_batch);
        if (count == 0) return error.UnexpectedIdle;
        for (slots[0..count]) |*slot| {
            try output.submit(slot);
            const size = accepted / 2;
            if (!try output.matches(accepted, expected[0..size]))
                return error.PayloadMismatch;
            if (pre_receive_segment_counts[accepted] != slot.segmentCount())
                return error.BorrowedIdentityMismatch;
            for (0..pre_receive_segment_counts[accepted]) |segment_index| {
                if (!std.meta.eql(
                    pre_receive_identities[accepted][segment_index],
                    try output.borrowedSegmentIdentity(accepted, segment_index),
                ))
                    return error.BorrowedIdentityMismatch;
                identity_matches += 1;
            }
            accepted += 1;
        }
    }
    try input.verifyCompleted();

    const packet_path_after = input.packetPathSnapshot();
    const allocator_after = counting_allocator.snapshot();
    try synthetic.verifyPacketPathGuard(
        packet_path_before,
        packet_path_after,
        allocator_before,
        allocator_after,
    );
    const counters = input.copyCounters();
    if (counters.packet_path_bytes != 0 or
        counters.explicit_read_bytes != 0)
    {
        return error.PerfCore004Violation;
    }
    if (counters.segment_borrows != 1799) return error.InstrumentationMismatch;
    if (counters.receive_calls != 9 or counters.submit_calls != traversal_count)
        return error.InstrumentationMismatch;

    const unexpected = try observed_allocator.alloc(u8, 1);
    defer observed_allocator.free(unexpected);
    var allocation_guard_negative_control = false;
    synthetic.verifyPacketPathGuard(
        packet_path_after,
        input.packetPathSnapshot(),
        allocator_after,
        counting_allocator.snapshot(),
    ) catch |guard_error| {
        if (guard_error != error.GeneralAllocationObserved)
            return guard_error;
        allocation_guard_negative_control = true;
    };
    if (!allocation_guard_negative_control or
        counting_allocator.snapshot().allocationActivity() ==
            allocator_after.allocationActivity())
    {
        return error.AllocationNegativeControlFailed;
    }

    const allocation_after_negative = counting_allocator.snapshot();
    var copied: [1]u8 = undefined;
    try input.copyPayloadForNegativeControl(&copied, &.{0xa5});
    var copy_guard_negative_control = false;
    synthetic.verifyPacketPathGuard(
        packet_path_after,
        input.packetPathSnapshot(),
        allocation_after_negative,
        counting_allocator.snapshot(),
    ) catch |guard_error| {
        if (guard_error != error.PayloadCopyObserved)
            return guard_error;
        copy_guard_negative_control = true;
    };
    if (!copy_guard_negative_control or
        input.packetPathSnapshot().abstraction_payload_copy_bytes ==
            packet_path_after.abstraction_payload_copy_bytes)
    {
        return error.CopyNegativeControlFailed;
    }

    const parsed = try std.json.parseFromSlice(
        ExpectedArtifact,
        std.heap.page_allocator,
        expected_artifact_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    const expected_evidence = parsed.value;
    const traversed_payload_bytes = configured_max * (configured_max + 1);
    const packet_path_general_allocations =
        allocator_after.allocationActivity() - allocator_before.allocationActivity();
    if (expected_evidence.application.batch_max != packet.max_batch or
        expected_evidence.application.resources.configured_max_packet_bytes != configured_max or
        expected_evidence.result.perf.traversed_packets != accepted or
        expected_evidence.result.perf.traversed_payload_bytes != traversed_payload_bytes or
        expected_evidence.result.perf.receive_calls != counters.receive_calls or
        expected_evidence.result.perf.submit_calls != counters.submit_calls or
        expected_evidence.result.perf.borrowed_segment_operations != counters.segment_borrows or
        expected_evidence.result.perf.pre_receive_identity_matches != identity_matches or
        expected_evidence.result.perf.abstraction_payload_copy_bytes != counters.packet_path_bytes or
        expected_evidence.result.perf.allocation_guard_negative_control !=
            allocation_guard_negative_control or
        expected_evidence.result.perf.copy_guard_negative_control !=
            copy_guard_negative_control or
        expected_evidence.result.memory_bytes.packet_path_general_allocations !=
            packet_path_general_allocations)
    {
        return error.BenchmarkArtifactMismatch;
    }

    std.debug.print(
        "M1 synthetic traversal regression (not a capacity claim)\n" ++
            "sizes=0..{d} variants=linear,segmented packets={d} payload_bytes={d} " ++
            "receive_calls={d} submit_calls={d} segment_borrows={d} identity_matches={d} " ++
            "abstraction_copy_bytes={d} general_allocations={d} artifact=matched\n",
        .{
            configured_max,
            accepted,
            traversed_payload_bytes,
            counters.receive_calls,
            counters.submit_calls,
            counters.segment_borrows,
            identity_matches,
            counters.packet_path_bytes,
            packet_path_general_allocations,
        },
    );
}
