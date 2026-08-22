// SPDX-License-Identifier: Apache-2.0
const std = @import("std");
const saint = @import("saint_shield");

const processor = saint.processor;
const pipeline = saint.pipeline;
const packet = saint.packet;
const testing = saint.testing;

const output_id = packet.OutputId.init(1);
var lifecycle_log: [32]u8 = undefined;
var lifecycle_log_len: usize = 0;
var call_log: [64]u8 = undefined;
var call_log_len: usize = 0;

fn recordLifecycle(value: u8) void {
    lifecycle_log[lifecycle_log_len] = value;
    lifecycle_log_len += 1;
}

fn recordCall(value: u8) void {
    call_log[call_log_len] = value;
    call_log_len += 1;
}

fn expectReverseLifecyclePrefixes() !void {
    var previous_worker: ?u8 = null;
    var previous_prepared: ?u8 = null;
    for (lifecycle_log[0..lifecycle_log_len]) |entry| {
        if (entry >= 100) {
            if (previous_worker) |previous| try std.testing.expect(entry < previous);
            previous_worker = entry;
        } else {
            if (previous_prepared) |previous| try std.testing.expect(entry < previous);
            previous_prepared = entry;
        }
    }
}

fn LifecycleStage(
    comptime stage_id: u64,
    comptime prepared_bytes: usize,
    comptime worker_bytes: usize,
    comptime estimate_prepared: usize,
    comptime estimate_worker: usize,
    comptime fail_prepare: bool,
    comptime fail_worker: bool,
) type {
    return struct {
        /// Allocated prepared bytes retained by the lifecycle fixture.
        pub const Prepared = struct { memory: []u8 };
        /// Allocated worker bytes retained by the lifecycle fixture.
        pub const Worker = struct { memory: []u8 };
        /// Configurable lifecycle fixture declaration.
        pub const descriptor: processor.ProcessorDescriptor = .{
            .id = .init(stage_id),
            .services = .{ .worker_state = true },
            .work = .{ .maximum_total = packet.max_batch },
            .update_modes = .{ .flush = true },
            .default_update_mode = .flush,
            .resource_categories = .{
                .prepared_memory = estimate_prepared != 0,
                .worker_memory = estimate_worker != 0,
            },
        };

        /// Reports the configured resource estimate.
        pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
            return .{
                .prepared_bytes = estimate_prepared,
                .worker_bytes = estimate_worker,
                .maximum_batch_work = packet.max_batch,
            };
        }

        /// Allocates prepared bytes or injects the configured failure.
        pub fn prepare(allocator: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {
            if (fail_prepare) return error.InvalidArtifact;
            const memory = allocator.alloc(u8, prepared_bytes) catch
                return error.ResourceUnderestimated;
            return .{ .memory = memory };
        }

        /// Allocates worker bytes or injects the configured failure.
        pub fn instantiate(
            allocator: std.mem.Allocator,
            _: *const Prepared,
            _: processor.WorkerDescriptor,
        ) processor.InstantiationError!Worker {
            if (fail_worker) return error.InvalidWorker;
            const memory = allocator.alloc(u8, worker_bytes) catch
                return error.ResourceUnderestimated;
            return .{ .memory = memory };
        }

        /// Observes the active selection without changing dispositions.
        pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
            const active = context.active() catch unreachable;
            return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
        }

        /// Frees worker bytes and records cleanup order.
        pub fn deinitWorker(worker: *Worker, allocator: std.mem.Allocator) void {
            allocator.free(worker.memory);
            recordLifecycle(@intCast(stage_id + 100));
        }

        /// Frees prepared bytes and records cleanup order.
        pub fn deinitPrepared(prepared: *Prepared, allocator: std.mem.Allocator) void {
            allocator.free(prepared.memory);
            recordLifecycle(@intCast(stage_id));
        }
    };
}

fn limits(
    comptime PipelineType: type,
    prepared: usize,
    worker_each: usize,
    worker_count: usize,
    work: usize,
) processor.ResourceLimits {
    const admitted_prepared = std.math.add(usize, PipelineType.frameworkPreparedBytes(worker_count) catch std.math.maxInt(usize), prepared) catch
        std.math.maxInt(usize);
    const admitted_worker = std.math.add(usize, PipelineType.frameworkWorkerBytesEach(), worker_each) catch
        std.math.maxInt(usize);
    const metadata_each = PipelineType.InputMetadata.scratchBytes();
    return .{
        .prepared_bytes = admitted_prepared,
        .worker_bytes_each = admitted_worker,
        .worker_bytes_total = std.math.mul(usize, admitted_worker, worker_count) catch std.math.maxInt(usize),
        .metadata_scratch_bytes_each = metadata_each,
        .metadata_scratch_bytes_total = std.math.mul(usize, metadata_each, worker_count) catch std.math.maxInt(usize),
        .maximum_batch_work = work,
        .worker_count = worker_count,
    };
}

test "AC-012 exact limits pass and one-byte excess, overflow, multiplication, and underestimate reject" {
    const Exact = LifecycleStage(1, 8, 4, 8, 4, false, false);
    const ExactPipeline = pipeline.Pipeline(.{Exact});
    const prepared = try ExactPipeline.prepare(
        std.testing.allocator,
        .{null},
        .{},
        limits(ExactPipeline, 8, 4, 2, packet.max_batch),
    );
    defer prepared.deinit() catch unreachable;
    try std.testing.expectEqual(try ExactPipeline.frameworkPreparedBytes(2) + 8, prepared.aggregate.prepared_bytes);
    try std.testing.expectEqual((ExactPipeline.frameworkWorkerBytesEach() + 4) * 2, prepared.aggregate.worker_bytes_total);
    var worker = try ExactPipeline.instantiate(prepared, .{ .id = 1 });
    try prepared.deinitWorker(&worker);

    try std.testing.expectError(
        error.ResourceLimitExceeded,
        ExactPipeline.prepare(
            std.testing.allocator,
            .{null},
            .{},
            limits(ExactPipeline, 7, 4, 2, packet.max_batch),
        ),
    );
    var multiplied_too_small = limits(ExactPipeline, 8, 4, 2, packet.max_batch);
    multiplied_too_small.worker_bytes_total -= 1;
    try std.testing.expectError(
        error.ResourceLimitExceeded,
        ExactPipeline.prepare(std.testing.allocator, .{null}, .{}, multiplied_too_small),
    );

    const OverflowStage = LifecycleStage(2, 0, 0, 0, std.math.maxInt(usize), false, false);
    const OverflowPipeline = pipeline.Pipeline(.{OverflowStage});
    try std.testing.expectError(
        error.ResourceOverflow,
        OverflowPipeline.prepare(
            std.testing.allocator,
            .{null},
            .{},
            limits(OverflowPipeline, 0, std.math.maxInt(usize), 2, packet.max_batch),
        ),
    );

    const Underestimated = LifecycleStage(3, 2, 0, 1, 0, false, false);
    const UnderPipeline = pipeline.Pipeline(.{Underestimated});
    try std.testing.expectError(
        error.ResourceUnderestimated,
        UnderPipeline.prepare(
            std.testing.allocator,
            .{null},
            .{},
            limits(UnderPipeline, 1, 0, 1, packet.max_batch),
        ),
    );
}

test "assembly rejects unavailable read, trusted raw, output, and retention capabilities before prepare" {
    const ReadStage = struct {
        /// Capability fixture has no prepared state.
        pub const Prepared = void;
        /// Capability fixture has no worker state.
        pub const Worker = void;
        /// Requests capabilities selectively withheld by the test.
        pub const descriptor: processor.ProcessorDescriptor = .{
            .id = .init(40),
            .packet_access = .read,
            .dispositions = .{ .accept = true, .retain = true },
            .outputs = &.{output_id},
            .work = .{ .maximum_total = packet.max_batch },
        };
        /// Reports bounded work and no allocated resources.
        pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
            return .{ .maximum_batch_work = packet.max_batch };
        }
        /// Constructs the empty capability-fixture prepared state.
        pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
        /// Constructs the empty capability-fixture worker state.
        pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
        /// Observes the active selection if assembly is permitted.
        pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
            const active = context.active() catch unreachable;
            return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
        }
        /// Cleans the empty worker state.
        pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
        /// Cleans the empty prepared state.
        pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
    };
    const P = pipeline.Pipeline(.{ReadStage});
    try std.testing.expectError(
        error.CapabilityUnavailable,
        P.prepare(std.testing.allocator, .{null}, .{}, limits(P, 0, 0, 1, packet.max_batch)),
    );
    try std.testing.expectError(
        error.CapabilityUnavailable,
        P.prepare(
            std.testing.allocator,
            .{null},
            .{ .packet_access = .read, .available_outputs = &.{output_id}, .retention = true },
            limits(P, 0, 0, 1, packet.max_batch),
        ),
    );
}

test "preparation and worker partial failures clean exact reverse prefixes" {
    lifecycle_log_len = 0;
    const A = LifecycleStage(1, 1, 1, 1, 1, false, false);
    const B = LifecycleStage(2, 1, 1, 1, 1, false, false);
    const FailPrepare = LifecycleStage(3, 0, 0, 0, 0, true, false);
    const PreparePipeline = pipeline.Pipeline(.{ A, B, FailPrepare });
    try std.testing.expectError(
        error.PreparationFailed,
        PreparePipeline.prepare(
            std.testing.allocator,
            .{ null, null, null },
            .{},
            limits(PreparePipeline, 2, 2, 1, packet.max_batch * 3),
        ),
    );
    try std.testing.expectEqualSlices(u8, &.{ 2, 1 }, lifecycle_log[0..lifecycle_log_len]);

    lifecycle_log_len = 0;
    const FailWorker = LifecycleStage(3, 0, 0, 0, 0, false, true);
    const WorkerPipeline = pipeline.Pipeline(.{ A, B, FailWorker });
    const prepared = try WorkerPipeline.prepare(
        std.testing.allocator,
        .{ null, null, null },
        .{},
        limits(WorkerPipeline, 2, 2, 1, packet.max_batch * 3),
    );
    defer prepared.deinit() catch unreachable;
    lifecycle_log_len = 0;
    try std.testing.expectError(
        error.InstantiationFailed,
        WorkerPipeline.instantiate(prepared, .{ .id = 1 }),
    );
    try std.testing.expectEqualSlices(u8, &.{ 102, 101 }, lifecycle_log[0..lifecycle_log_len]);
}

test "prepared and worker construction failure sweep leaves zero allocator bytes" {
    const Stage = LifecycleStage(8, 3, 5, 3, 5, false, false);
    const P = pipeline.Pipeline(.{Stage});
    for (0..8) |fail_index| {
        lifecycle_log_len = 0;
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        const maybe_prepared = P.prepare(
            failing.allocator(),
            .{null},
            .{},
            limits(P, 3, 5, 1, packet.max_batch),
        );
        if (maybe_prepared) |prepared| {
            const maybe_worker = P.instantiate(prepared, .{ .id = 1 });
            if (maybe_worker) |value| {
                var worker = value;
                try prepared.deinitWorker(&worker);
            } else |_| {}
            try prepared.deinit();
        } else |_| {}
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

test "public harness allocation failure sweep cleans every reachable prefix" {
    const A = LifecycleStage(80, 2, 3, 2, 3, false, false);
    const B = LifecycleStage(81, 3, 4, 3, 4, false, false);
    const P = pipeline.Pipeline(.{ A, B });
    const Harness = testing.ProcessorTestHarness(P);
    var reached_nonfailing_index = false;
    for (0..128) |fail_index| {
        lifecycle_log_len = 0;
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        const maybe_harness = Harness.init(
            failing.allocator(),
            .{ null, null },
            .{ .available_outputs = &.{output_id} },
            limits(P, 5, 7, 1, packet.max_batch * 2),
            .{ .id = 1 },
        );
        if (maybe_harness) |value| {
            var harness = value;
            const maybe_result = harness.submit(
                &.{.{ .bytes = &.{1} }},
                .{ .input_id = .init(1), .queue_id = .init(1) },
                0,
                try P.InputMetadata.init(1),
                .{
                    .outputs = &.{output_id},
                    .default_output = null,
                    .continue_policy = .{ .accept = output_id },
                },
            );
            if (maybe_result) |value_result| {
                var result = value_result;
                result.deinit();
            } else |_| {}
            harness.deinit();
        } else |_| {}
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try expectReverseLifecyclePrefixes();
        if (!failing.has_induced_failure) {
            reached_nonfailing_index = true;
            break;
        }
    }
    try std.testing.expect(reached_nonfailing_index);

    var reached_zero_fixture_nonfailing_index = false;
    for (0..128) |fail_index| {
        lifecycle_log_len = 0;
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = fail_index });
        const maybe_harness = Harness.init(
            failing.allocator(),
            .{ null, null },
            .{ .available_outputs = &.{output_id} },
            limits(P, 5, 7, 1, packet.max_batch * 2),
            .{ .id = 1 },
        );
        if (maybe_harness) |value| {
            var harness = value;
            const maybe_result = harness.submit(
                &.{},
                .{ .input_id = .init(1), .queue_id = .init(1) },
                0,
                try P.InputMetadata.init(0),
                .{
                    .outputs = &.{output_id},
                    .default_output = null,
                    .continue_policy = .{ .accept = output_id },
                },
            );
            if (maybe_result) |value_result| {
                var result = value_result;
                result.deinit();
            } else |_| {}
            harness.deinit();
        } else |_| {}
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        try expectReverseLifecyclePrefixes();
        if (!failing.has_induced_failure) {
            reached_zero_fixture_nonfailing_index = true;
            break;
        }
    }
    try std.testing.expect(reached_zero_fixture_nonfailing_index);

    // Repeat complete public lifecycles so teardown remains stable after the
    // exhaustive induced-failure prefixes in every compiled build mode.
    for (0..3) |_| {
        lifecycle_log_len = 0;
        var harness = try Harness.init(
            std.testing.allocator,
            .{ null, null },
            .{ .available_outputs = &.{output_id} },
            limits(P, 5, 7, 1, packet.max_batch * 2),
            .{ .id = 1 },
        );
        var result = try harness.submit(
            &.{.{ .bytes = &.{1} }},
            .{ .input_id = .init(1), .queue_id = .init(1) },
            0,
            try P.InputMetadata.init(1),
            .{
                .outputs = &.{output_id},
                .default_output = null,
                .continue_policy = .{ .accept = output_id },
            },
        );
        result.deinit();
        harness.deinit();
        try expectReverseLifecyclePrefixes();
    }
}

test "prepared owner enforces capacity early-deinit stale recycle and repeated cleanup" {
    const P = pipeline.Pipeline(.{TestLifecycleNoop});
    const prepared = try P.prepare(
        std.testing.allocator,
        .{null},
        .{},
        limits(P, 0, 0, 2, packet.max_batch),
    );
    const wrong_prepared = try P.prepare(
        std.testing.allocator,
        .{null},
        .{},
        limits(P, 0, 0, 1, packet.max_batch),
    );
    defer wrong_prepared.deinit() catch unreachable;
    var first = try P.instantiate(prepared, .{ .id = 1 });
    var stale = first;
    var wrong_owner_copy = first;
    try std.testing.expectError(error.WrongWorkerOwner, wrong_prepared.deinitWorker(&wrong_owner_copy));
    try std.testing.expectEqual(first.generation, wrong_owner_copy.generation);
    var forged_identity = first;
    forged_identity.owner_identity +%= 1;
    if (forged_identity.owner_identity == 0) forged_identity.owner_identity = 1;
    try std.testing.expectError(error.WrongWorkerOwner, prepared.deinitWorker(&forged_identity));
    var forged_slot = first;
    forged_slot.slot = std.math.maxInt(usize);
    try std.testing.expectError(error.StaleWorker, prepared.deinitWorker(&forged_slot));
    var future = P.WorkerHandle{
        .owner_identity = first.owner_identity,
        .slot = first.slot,
        .generation = first.generation + 1,
    };
    try std.testing.expectError(error.StaleWorker, prepared.deinitWorker(&future));
    var second = try P.instantiate(prepared, .{ .id = 2 });
    try std.testing.expectError(error.WorkerCapacityExceeded, P.instantiate(prepared, .{ .id = 3 }));
    try std.testing.expectError(error.WorkersStillLive, prepared.deinit());
    try prepared.deinitWorker(&first);
    try std.testing.expectError(error.StaleWorker, prepared.deinitWorker(&first));
    try std.testing.expectError(error.StaleWorker, prepared.deinitWorker(&stale));
    var recycled = try P.instantiate(prepared, .{ .id = 3 });
    try std.testing.expect(recycled.generation != stale.generation);
    try std.testing.expectError(error.StaleWorker, prepared.deinitWorker(&stale));
    try prepared.deinitWorker(&second);
    try prepared.deinitWorker(&recycled);
    try prepared.deinit();

    // Only scalar identity/index/generation data survives owner destruction;
    // using the copied value still requires a separately live owner.
    try std.testing.expectEqual(@as(usize, @sizeOf(u64) * 2 + @sizeOf(usize)), @sizeOf(P.WorkerHandle));
    try std.testing.expect(stale.owner_identity != 0);
}

const TestLifecycleNoop = struct {
    /// No prepared state.
    pub const Prepared = void;
    /// No worker state.
    pub const Worker = void;
    /// Minimal lifecycle descriptor.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(70),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Reports exact bounded work.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Observes the active set.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

test "framework and metadata bytes are exact hard limits for multiple workers" {
    const P = pipeline.Pipeline(.{TestLifecycleNoop});
    const exact = limits(P, 0, 0, 3, packet.max_batch);
    const prepared = try P.prepare(std.testing.allocator, .{null}, .{}, exact);
    try std.testing.expectEqual(try P.frameworkPreparedBytes(3), prepared.aggregate.framework_prepared_bytes);
    try std.testing.expectEqual(try P.frameworkPreparedBytes(3), prepared.aggregate.prepared_bytes);
    try std.testing.expectEqual(P.frameworkWorkerBytesEach(), prepared.aggregate.framework_worker_bytes_each);
    try std.testing.expectEqual(P.frameworkWorkerBytesEach() * 3, prepared.aggregate.worker_bytes_total);
    try std.testing.expectEqual(@sizeOf(processor.MetadataStore), prepared.aggregate.metadata_scratch_bytes_each);
    try prepared.deinit();

    var under = exact;
    under.prepared_bytes -= 1;
    try std.testing.expectError(error.ResourceLimitExceeded, P.prepare(std.testing.allocator, .{null}, .{}, under));
    under = exact;
    under.worker_bytes_each -= 1;
    try std.testing.expectError(error.ResourceLimitExceeded, P.prepare(std.testing.allocator, .{null}, .{}, under));
    under = exact;
    under.metadata_scratch_bytes_each -= 1;
    try std.testing.expectError(error.ResourceLimitExceeded, P.prepare(std.testing.allocator, .{null}, .{}, under));
}

test "per-stage budgets reject slack laundering" {
    const Under = LifecycleStage(71, 2, 0, 1, 0, false, false);
    const Slack = LifecycleStage(72, 0, 0, 16, 0, false, false);
    const P = pipeline.Pipeline(.{ Under, Slack });
    try std.testing.expectError(
        error.ResourceUnderestimated,
        P.prepare(std.testing.allocator, .{ null, null }, .{}, limits(P, 17, 0, 1, packet.max_batch * 2)),
    );
}

const UnderestimatedWorkStage = struct {
    /// Work fixture has no prepared state.
    pub const Prepared = void;
    /// Work fixture has no worker state.
    pub const Worker = void;
    /// Formula requires the full batch bound.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(74),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Deliberately fails to cover the declared worst case.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch - 1 };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Would observe the active set if admission incorrectly succeeded.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const ExcessiveWorkStage = struct {
    /// Work fixture has no prepared state.
    pub const Prepared = void;
    /// Work fixture has no worker state.
    pub const Worker = void;
    /// Declares one work unit per active packet.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(75),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Covers the exact declared worst case.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Returns one more work unit than the accepted partial-batch formula.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        return .{
            .visited_packets = @intCast(active.count()),
            .work_units = @intCast(active.count() + 1),
        };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

var mutating_excessive_calls: usize = 0;

const MutatingExcessiveWorkStage = struct {
    /// Work-contract fixture has no prepared state.
    pub const Prepared = void;
    /// Work-contract fixture has no worker state.
    pub const Worker = void;
    /// Declares structured mutation and terminal disposition authority.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(76),
        .packet_access = .structured_edit,
        .dispositions = .{ .accept = true, .drop = true },
        .outputs = &.{output_id},
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Covers the exact declared worst case.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Mutates and terminates the batch before deliberately overreporting work.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        mutating_excessive_calls += 1;
        const active = context.active() catch unreachable;
        if (!active.isEmpty()) {
            context.setIpv4Ttl(0, 31) catch unreachable;
            context.drop(active, .init(76)) catch unreachable;
        }
        return .{
            .visited_packets = @intCast(active.count()),
            .work_units = @intCast(active.count() + 1),
        };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const RevokingPipeline = pipeline.Pipeline(.{MutatingExcessiveWorkStage});

fn mutableIpv4Fixture() [46]u8 {
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
    return bytes;
}

fn expectDispositionConfigRejectedBeforeCallback(
    prepared: *RevokingPipeline.PreparedPipeline,
    worker: RevokingPipeline.WorkerHandle,
    config: packet.DispositionConfig,
) !void {
    var bytes = mutableIpv4Fixture();
    var tracker = try packet.TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const descriptors = [_]packet.MutableSegmentDescriptor{
        try .init(&bytes, 0, bytes.len, .{}),
    };
    var slots = [_]packet.PacketSlot{try .initMutable(
        token,
        &descriptors,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    defer batch.invalidate(owner) catch {};
    mutating_excessive_calls = 0;
    try std.testing.expectError(
        error.DispositionFailure,
        prepared.processBatch(
            worker,
            owner,
            batch,
            try RevokingPipeline.InputMetadata.init(1),
            config,
            0,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), mutating_excessive_calls);
    try std.testing.expectEqual(@as(u8, 64), bytes[22]);
    try std.testing.expectEqual(@as(usize, 1), try batch.len(owner));
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "invalid disposition configurations reject before mutating processor callbacks" {
    const prepared = try RevokingPipeline.prepare(
        std.testing.allocator,
        .{null},
        .{ .packet_access = .structured_edit, .available_outputs = &.{output_id} },
        limits(RevokingPipeline, 0, 0, 1, packet.max_batch),
    );
    defer prepared.deinit() catch unreachable;
    var worker = try RevokingPipeline.instantiate(prepared, .{ .id = 1 });
    defer prepared.deinitWorker(&worker) catch unreachable;

    var too_many: [packet.DispositionGroups.max_outputs + 1]packet.OutputId = undefined;
    for (&too_many, 0..) |*output, index| output.* = .init(index + 1);
    try expectDispositionConfigRejectedBeforeCallback(prepared, worker, .{
        .outputs = &too_many,
        .default_output = output_id,
        .continue_policy = .{ .drop = .init(1) },
    });
    try expectDispositionConfigRejectedBeforeCallback(prepared, worker, .{
        .outputs = &.{ output_id, output_id },
        .default_output = output_id,
        .continue_policy = .{ .drop = .init(1) },
    });
    try expectDispositionConfigRejectedBeforeCallback(prepared, worker, .{
        .outputs = &.{ output_id, .init(2) },
        .default_output = output_id,
        .continue_policy = .{ .drop = .init(1) },
    });
    try expectDispositionConfigRejectedBeforeCallback(prepared, worker, .{
        .outputs = &.{output_id},
        .default_output = null,
        .continue_policy = .{ .drop = .init(1) },
    });
    try expectDispositionConfigRejectedBeforeCallback(prepared, worker, .{
        .outputs = &.{output_id},
        .default_output = .init(2),
        .continue_policy = .{ .drop = .init(1) },
    });
}

test "escaped raw batch authority rejects before processor callbacks" {
    const prepared = try RevokingPipeline.prepare(
        std.testing.allocator,
        .{null},
        .{ .packet_access = .structured_edit, .available_outputs = &.{output_id} },
        limits(RevokingPipeline, 0, 0, 1, packet.max_batch),
    );
    defer prepared.deinit() catch unreachable;
    var worker = try RevokingPipeline.instantiate(prepared, .{ .id = 1 });
    defer prepared.deinitWorker(&worker) catch unreachable;

    var bytes = mutableIpv4Fixture();
    var tracker = try packet.TokenTracker.init(std.testing.allocator, 1);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    try token.receive();
    const descriptors = [_]packet.MutableSegmentDescriptor{
        try .init(&bytes, 0, bytes.len, .{}),
    };
    var slots = [_]packet.PacketSlot{try .initMutable(
        token,
        &descriptors,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    defer batch.invalidate(owner) catch {};
    const raw = (try (try batch.view(owner, 0)).contiguous(
        owner,
        .{ .offset = 22, .len = 1 },
    )).?;
    mutating_excessive_calls = 0;
    try std.testing.expectError(
        error.BatchFailure,
        prepared.processBatch(
            worker,
            owner,
            batch,
            try RevokingPipeline.InputMetadata.init(1),
            .{
                .outputs = &.{output_id},
                .default_output = output_id,
                .continue_policy = .{ .drop = .init(1) },
            },
            0,
        ),
    );
    try std.testing.expectEqual(@as(usize, 0), mutating_excessive_calls);
    try std.testing.expectEqual(@as(u8, 64), raw[0]);
    try std.testing.expectEqual(@as(usize, 1), try batch.len(owner));
    try token.returnToInput();
    try tracker.verifyReceivedCompleted();
}

test "post-callback work breach revokes batch aliases and caller completes token once" {
    const prepared = try RevokingPipeline.prepare(
        std.testing.allocator,
        .{null},
        .{ .packet_access = .structured_edit, .available_outputs = &.{output_id} },
        limits(RevokingPipeline, 0, 0, 1, packet.max_batch),
    );
    defer prepared.deinit() catch unreachable;
    var worker = try RevokingPipeline.instantiate(prepared, .{ .id = 1 });
    defer prepared.deinitWorker(&worker) catch unreachable;

    var bytes = mutableIpv4Fixture();
    var tracker = try packet.TokenTracker.init(std.testing.allocator, 2);
    defer tracker.deinit();
    const token = try tracker.registerInput();
    const recycled_token = try tracker.registerInput();
    try token.receive();
    const descriptors = [_]packet.MutableSegmentDescriptor{
        try .init(&bytes, 0, bytes.len, .{}),
    };
    var slots = [_]packet.PacketSlot{try .initMutable(
        token,
        &descriptors,
        bytes.len,
        0,
        .{},
        null,
    )};
    const owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &slots,
    );
    const view = try batch.view(owner, 0);
    const editor = try batch.editor(owner, 0);
    const output = try batch.outputPacket(owner, 0);
    mutating_excessive_calls = 0;
    try std.testing.expectError(
        error.WorkContractViolation,
        prepared.processBatch(
            worker,
            owner,
            batch,
            try RevokingPipeline.InputMetadata.init(1),
            .{
                .outputs = &.{output_id},
                .default_output = output_id,
                .continue_policy = .{ .drop = .init(1) },
            },
            0,
        ),
    );
    try std.testing.expectEqual(@as(usize, 1), mutating_excessive_calls);
    try std.testing.expectEqual(@as(u8, 31), bytes[22]);
    try std.testing.expectError(error.BatchReleased, batch.len(owner));
    try std.testing.expectError(error.BatchReleased, batch.view(owner, 0));
    try std.testing.expectError(error.BatchReleased, batch.outputPacket(owner, 0));
    try std.testing.expectError(error.StaleView, view.length(owner));
    try std.testing.expectError(error.StaleView, output.length(owner));
    try std.testing.expectError(error.StaleView, editor.setIpv4Ttl(owner, 30));
    try std.testing.expectEqual(packet.TokenState.worker_owned, try token.state());
    try token.returnToInput();
    try std.testing.expectEqual(@as(usize, 1), tracker.receivedCount());
    try std.testing.expectEqual(@as(usize, 1), tracker.completionCount());

    var recycled_bytes = mutableIpv4Fixture();
    try recycled_token.receive();
    const recycled_descriptors = [_]packet.MutableSegmentDescriptor{
        try .init(&recycled_bytes, 0, recycled_bytes.len, .{}),
    };
    var recycled_slots = [_]packet.PacketSlot{try .initMutable(
        recycled_token,
        &recycled_descriptors,
        recycled_bytes.len,
        1,
        .{},
        null,
    )};
    const recycled_batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &recycled_slots,
    );
    try std.testing.expectError(error.BatchReleased, batch.len(owner));
    try std.testing.expectError(error.StaleView, view.length(owner));
    try std.testing.expectEqual(recycled_bytes.len, try (try recycled_batch.outputPacket(owner, 0)).length(owner));
    try recycled_batch.invalidate(owner);
    try recycled_token.returnToInput();
    try std.testing.expectEqual(@as(usize, 2), tracker.receivedCount());
    try std.testing.expectEqual(@as(usize, 2), tracker.completionCount());
    try tracker.verifyReceivedCompleted();
}

test "accepted work estimates cover worst case and runtime results stay within partial formula" {
    const Under = pipeline.Pipeline(.{UnderestimatedWorkStage});
    try std.testing.expectError(
        error.ResourceLimitExceeded,
        Under.prepare(
            std.testing.allocator,
            .{null},
            .{},
            limits(Under, 0, 0, 1, packet.max_batch),
        ),
    );

    const Excess = pipeline.Pipeline(.{ExcessiveWorkStage});
    const Harness = testing.ProcessorTestHarness(Excess);
    var harness = try Harness.init(
        std.testing.allocator,
        .{null},
        .{},
        limits(Excess, 0, 0, 1, packet.max_batch),
        .{ .id = 1 },
    );
    defer harness.deinit();
    try std.testing.expectError(
        error.WorkContractViolation,
        harness.submit(
            &.{.{ .bytes = &.{1} }},
            .{ .input_id = .init(1), .queue_id = .init(1) },
            0,
            try Excess.InputMetadata.init(1),
            .{ .outputs = &.{}, .default_output = null, .continue_policy = .{ .drop = .init(1) } },
        ),
    );
}

var retained_prepared_allocation_rejected = false;
var retained_worker_allocation_rejected = false;

const RetainedAllocatorStage = struct {
    /// Retains the construction allocator solely for adversarial testing.
    pub const Prepared = struct { allocator: std.mem.Allocator, memory: []u8 };
    /// Retains both construction allocators and one owned worker allocation.
    pub const Worker = struct {
        prepared_allocator: std.mem.Allocator,
        worker_allocator: std.mem.Allocator,
        memory: []u8,
    };
    /// Declares both counted construction categories.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(73),
        .services = .{ .worker_state = true },
        .work = .{ .maximum_total = packet.max_batch },
        .update_modes = .{ .flush = true },
        .default_update_mode = .flush,
        .resource_categories = .{ .prepared_memory = true, .worker_memory = true },
    };
    /// Reports the exact owned allocations.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .prepared_bytes = 1, .worker_bytes = 1, .maximum_batch_work = packet.max_batch };
    }
    /// Retains the phase-limited prepared allocator.
    pub fn prepare(allocator: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {
        return .{ .allocator = allocator, .memory = allocator.alloc(u8, 1) catch return error.ResourceUnderestimated };
    }
    /// Retains both allocator copies for packet-path denial checks.
    pub fn instantiate(allocator: std.mem.Allocator, prepared: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {
        return .{
            .prepared_allocator = prepared.allocator,
            .worker_allocator = allocator,
            .memory = allocator.alloc(u8, 1) catch return error.ResourceUnderestimated,
        };
    }
    /// Attempts new allocation through both retained construction allocators.
    pub fn processBatch(worker: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        retained_prepared_allocation_rejected = if (worker.prepared_allocator.alloc(u8, 1)) |bytes| blk: {
            worker.prepared_allocator.free(bytes);
            break :blk false;
        } else |_| true;
        retained_worker_allocation_rejected = if (worker.worker_allocator.alloc(u8, 1)) |bytes| blk: {
            worker.worker_allocator.free(bytes);
            break :blk false;
        } else |_| true;
        worker.worker_allocator.free(worker.memory);
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Owner-mediated cleanup reopens only free authority.
    pub fn deinitWorker(worker: *Worker, allocator: std.mem.Allocator) void {
        allocator.free(worker.memory);
    }
    /// Owner-mediated cleanup reopens only free authority.
    pub fn deinitPrepared(prepared: *Prepared, allocator: std.mem.Allocator) void {
        allocator.free(prepared.memory);
    }
};

test "retained construction allocators are sealed on the packet path and cleanup remains exact" {
    const P = pipeline.Pipeline(.{RetainedAllocatorStage});
    const Harness = testing.ProcessorTestHarness(P);
    var harness = try Harness.init(
        std.testing.allocator,
        .{null},
        .{},
        limits(P, 1, 1, 1, packet.max_batch),
        .{ .id = 1 },
    );
    defer harness.deinit();
    retained_prepared_allocation_rejected = false;
    retained_worker_allocation_rejected = false;
    var result = try harness.submit(
        &.{.{ .bytes = &.{1} }},
        .{ .input_id = .init(1), .queue_id = .init(1) },
        0,
        try P.InputMetadata.init(1),
        .{ .outputs = &.{}, .default_output = null, .continue_policy = .{ .drop = .init(1) } },
    );
    defer result.deinit();
    try std.testing.expect(retained_prepared_allocation_rejected);
    try std.testing.expect(retained_worker_allocation_rejected);
}

fn ActionStage(
    comptime stage_id: u64,
    comptime action: enum { none, drop_first, drop_all, fail },
    comptime policy: processor.ErrorPolicy,
) type {
    const fallible = action == .fail;
    return struct {
        /// Action fixture has no prepared state.
        pub const Prepared = void;
        /// Action fixture has no worker state.
        pub const Worker = void;
        /// Declares the configured terminal action and error policy.
        pub const descriptor: processor.ProcessorDescriptor = .{
            .id = .init(stage_id),
            .dispositions = .{ .accept = true, .drop = true },
            .outputs = &.{output_id},
            .work = .{ .maximum_total = packet.max_batch },
            .process_error_mode = if (fallible) .bounded else .infallible,
            .error_policy = policy,
        };
        /// Reports bounded work and no allocated resources.
        pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
            return .{ .maximum_batch_work = packet.max_batch };
        }
        /// Constructs the empty action-fixture prepared state.
        pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
        /// Constructs the empty action-fixture worker state.
        pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
        /// Applies the configured disposition or injected processing error.
        pub fn processBatch(
            _: *Worker,
            context: processor.ProcessContext(descriptor),
        ) if (fallible) processor.ProcessError!processor.ProcessResult else processor.ProcessResult {
            const active = context.active() catch unreachable;
            recordCall(@intCast(stage_id));
            if (fallible) return error.CapacityExhausted;
            if (action == .drop_all and !active.isEmpty()) context.drop(active, .init(stage_id)) catch unreachable;
            if (action == .drop_first and active.count() != 0) {
                var iterator = active.iterator();
                const first = iterator.next().?;
                const one = packet.PacketSelection.one(first.raw(), context.len() catch unreachable) catch unreachable;
                context.drop(one, .init(stage_id)) catch unreachable;
            }
            return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
        }
        /// Cleans the empty worker state.
        pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
        /// Cleans the empty prepared state.
        pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
    };
}

fn runFixtures(comptime P: type, fixtures: []const testing.PacketFixture) !testing.ProcessorTestHarness(P).TestResult {
    const Harness = testing.ProcessorTestHarness(P);
    var harness = try Harness.init(
        std.testing.allocator,
        [_]?processor.ConfigurationArtifact{null} ** P.processors.len,
        .{ .available_outputs = &.{output_id} },
        limits(P, 0, 0, 1, packet.max_batch * P.processors.len),
        .{ .id = 1 },
    );
    defer harness.deinit();
    return harness.submit(
        fixtures,
        .{ .input_id = .init(1), .queue_id = .init(1) },
        9,
        try P.InputMetadata.init(fixtures.len),
        .{
            .outputs = &.{output_id},
            .default_output = output_id,
            .continue_policy = .{ .accept = output_id },
        },
    );
}

test "AC-003 ordered mixed processing preserves prior terminals and short-circuits empty active" {
    const First = ActionStage(1, .drop_first, .infallible);
    const Second = ActionStage(2, .drop_all, .infallible);
    const Third = ActionStage(3, .none, .infallible);
    const Fourth = ActionStage(4, .none, .infallible);
    const P = pipeline.Pipeline(.{ First, Second, Third, Fourth });
    const fixtures = [_]testing.PacketFixture{ .{ .bytes = &.{1} }, .{ .bytes = &.{2} }, .{ .bytes = &.{3} } };
    call_log_len = 0;
    var result = try runFixtures(P, &fixtures);
    defer result.deinit();
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, call_log[0..call_log_len]);
    try std.testing.expectEqual(pipeline.StageStatus.skipped_empty, result.execution.stage_status[2]);
    try std.testing.expectEqual(pipeline.StageStatus.not_run, result.execution.stage_status[3]);
    try std.testing.expectEqual(@as(usize, 3), result.execution.dispositions.drop_count);
    try std.testing.expectEqual(@as(u64, 1), result.execution.final_dispositions[0].Drop.?.raw());
    try std.testing.expectEqual(@as(u64, 2), result.execution.final_dispositions[1].Drop.?.raw());
}

test "every explicit error policy preserves prior terminal packets and stop skips successors" {
    const Prior = ActionStage(1, .drop_first, .infallible);
    const ContinueFailure = ActionStage(2, .fail, .continue_active);
    const ContinuePipeline = pipeline.Pipeline(.{ Prior, ContinueFailure });
    const fixtures = [_]testing.PacketFixture{ .{ .bytes = &.{1} }, .{ .bytes = &.{2} } };
    var continued = try runFixtures(ContinuePipeline, &fixtures);
    defer continued.deinit();
    try std.testing.expectEqual(pipeline.StageStatus.failed_continue, continued.execution.stage_status[1]);
    try std.testing.expect(continued.execution.final_dispositions[0] == .Drop);
    try std.testing.expect(continued.execution.final_dispositions[1] == .Accept);

    const TerminalFailure = ActionStage(2, .fail, .{ .terminal_active = .{ .drop = .init(22) } });
    const TerminalPipeline = pipeline.Pipeline(.{ Prior, TerminalFailure });
    var terminal = try runFixtures(TerminalPipeline, &fixtures);
    defer terminal.deinit();
    try std.testing.expectEqual(@as(u64, 1), terminal.execution.final_dispositions[0].Drop.?.raw());
    try std.testing.expectEqual(@as(u64, 22), terminal.execution.final_dispositions[1].Drop.?.raw());

    const StopFailure = ActionStage(2, .fail, .{ .terminal_active_and_stop = .{ .drop = .init(33) } });
    const Successor = ActionStage(3, .none, .infallible);
    const StopPipeline = pipeline.Pipeline(.{ Prior, StopFailure, Successor });
    var stopped = try runFixtures(StopPipeline, &fixtures);
    defer stopped.deinit();
    try std.testing.expect(stopped.execution.request_stop);
    try std.testing.expectEqual(pipeline.StageStatus.not_run, stopped.execution.stage_status[2]);
}

const PartialKey = struct {
    /// Stable partial-validity metadata identity.
    pub const id: u32 = 11;
    /// Partial-validity metadata value type.
    pub const Value = u16;
};
var metadata_missing_observed = false;

const PartialProducer = struct {
    /// Partial producer has no prepared state.
    pub const Prepared = void;
    /// Partial producer has no worker state.
    pub const Worker = void;
    /// Produces one typed metadata key for part of a batch.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(10),
        .metadata_outputs = processor.MetadataKeys(.{PartialKey}),
        .work = .{ .maximum_total = packet.max_batch },
        .resource_categories = .{ .metadata_scratch = true },
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs the empty producer prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs the empty producer worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Produces metadata for only the first packet.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        context.produceMetadata(PartialKey, 0, 123) catch unreachable;
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans the empty producer worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans the empty producer prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const PartialConsumer = struct {
    /// Partial consumer has no prepared state.
    pub const Prepared = void;
    /// Partial consumer has no worker state.
    pub const Worker = void;
    /// Consumes the partial typed metadata key.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(11),
        .metadata_inputs = processor.MetadataKeys(.{PartialKey}),
        .work = .{ .maximum_total = packet.max_batch },
        .resource_categories = .{ .metadata_scratch = true },
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs the empty consumer prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs the empty consumer worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Verifies present and absent values without allocating.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        std.debug.assert((context.metadata(PartialKey, 0) catch unreachable).? == 123);
        metadata_missing_observed = (context.metadata(PartialKey, 1) catch unreachable) == null;
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans the empty consumer worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans the empty consumer prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

test "typed produced metadata records partial validity and fixed scratch accounting" {
    const P = pipeline.Pipeline(.{ PartialProducer, PartialConsumer });
    const fixtures = [_]testing.PacketFixture{ .{ .bytes = &.{1} }, .{ .bytes = &.{2} } };
    metadata_missing_observed = false;
    var result = try runFixtures(P, &fixtures);
    defer result.deinit();
    try std.testing.expect(metadata_missing_observed);
    try std.testing.expectEqual(P.InputMetadata.scratchBytes(), result.resources.metadata_scratch_bytes);
    try std.testing.expectEqual(@as(usize, 0), result.resources.hot_path_allocator_calls);
}

test "seeded tiny direct pipelines match a simple terminal-count reference" {
    const P = pipeline.Pipeline(.{ActionStage(1, .drop_first, .infallible)});
    const seed: u64 = 0x4d33_5245_4645_5245;
    var trace = testing.SeededTrace(1024).init(seed);
    const random = trace.random();
    for (0..32) |case_index| {
        const count = random.uintLessThan(usize, 9);
        var fixtures: [8]testing.PacketFixture = undefined;
        for (0..count) |index| fixtures[index] = .{ .bytes = &.{@intCast(index)} };
        var buffer: [32]u8 = undefined;
        trace.append(std.fmt.bufPrint(&buffer, "case({d},{d})", .{ case_index, count }) catch unreachable);
        var result = runFixtures(P, fixtures[0..count]) catch |err| {
            trace.reportFailure();
            return err;
        };
        defer result.deinit();
        const expected_drop: usize = if (count == 0) 0 else 1;
        const observed_accept = if (result.execution.dispositions.output_count == 0)
            0
        else
            result.execution.dispositions.outputs[0].count;
        if (result.execution.dispositions.drop_count != expected_drop or
            observed_accept != count - expected_drop)
        {
            trace.reportFailure();
            return error.ReferenceMismatch;
        }
    }
}

const collision_output_id = packet.OutputId.init(0x8064_0c6b_1973_6702);

const collision_forged_descriptor: processor.ProcessorDescriptor = .{
    .id = .init(90),
    .packet_access = .trusted_raw_edit,
    .dispositions = .{ .accept = true },
    .outputs = &.{collision_output_id},
    .work = .{ .maximum_total = packet.max_batch },
};

const ForgedMetadataInput = struct {
    /// Stable collision-test input identity.
    pub const id: u32 = 0x4649_4e01;
    /// Inline collision-test input value.
    pub const Value = u16;
};

const ForgedMetadataOutput = struct {
    /// Stable collision-test output identity.
    pub const id: u32 = 0x464f_5501;
    /// Inline collision-test output value.
    pub const Value = u16;
};

fn legacyBindingMix(seed: u64, value: anytype) u64 {
    return (seed ^ @as(u64, @intCast(value))) *% 0x9e37_79b1_85eb_ca87;
}

fn legacyBindingUnmix(result: u64, value: anytype) u64 {
    return (result *% 0x0887_4934_32ba_db37) ^ @as(u64, @intCast(value));
}

fn legacyTypeFingerprint(comptime T: type) u64 {
    return std.hash.Wyhash.hash(0x4d33_5459_5045, @typeName(T));
}

fn legacyAuthorityBinding(comptime descriptor: processor.ProcessorDescriptor) u64 {
    comptime {
        std.debug.assert(descriptor.metrics.list.len == 0);
        std.debug.assert(descriptor.events.list.len == 0);
    }
    var binding: u64 = 0x4d33_4155_5448;
    binding = legacyBindingMix(binding, descriptor.id.raw());
    binding = legacyBindingMix(binding, descriptor.api);
    binding = legacyBindingMix(binding, @intFromEnum(descriptor.packet_access));
    binding = legacyBindingMix(binding, @as(u8, @bitCast(descriptor.dispositions)));
    inline for (descriptor.outputs) |output| binding = legacyBindingMix(binding, output.raw());
    inline for (descriptor.metadata_inputs.list) |Key| {
        binding = legacyBindingMix(binding, Key.id);
        binding = legacyBindingMix(binding, legacyTypeFingerprint(Key.Value));
    }
    inline for (descriptor.metadata_outputs.list) |Key| {
        binding = legacyBindingMix(binding, Key.id);
        binding = legacyBindingMix(binding, legacyTypeFingerprint(Key.Value));
    }
    binding = legacyBindingMix(binding, @as(u8, @bitCast(descriptor.services)));
    return binding;
}

fn metadataCollisionOutputId() packet.OutputId {
    const target = 0x629b_8ddd_5171_2b5d;
    var required_after_output = legacyBindingUnmix(target, @as(u8, 0));
    required_after_output = legacyBindingUnmix(
        required_after_output,
        legacyTypeFingerprint(ForgedMetadataOutput.Value),
    );
    required_after_output = legacyBindingUnmix(required_after_output, ForgedMetadataOutput.id);
    required_after_output = legacyBindingUnmix(
        required_after_output,
        legacyTypeFingerprint(ForgedMetadataInput.Value),
    );
    required_after_output = legacyBindingUnmix(required_after_output, ForgedMetadataInput.id);

    var before_output: u64 = 0x4d33_4155_5448;
    before_output = legacyBindingMix(before_output, 90);
    before_output = legacyBindingMix(before_output, processor.api_version);
    before_output = legacyBindingMix(before_output, @intFromEnum(processor.PacketAccess.trusted_raw_edit));
    before_output = legacyBindingMix(before_output, @as(u8, @bitCast(processor.DispositionCapabilities{ .accept = true })));
    const raw = before_output ^ (required_after_output *% 0x0887_4934_32ba_db37);
    return packet.OutputId.init(raw);
}

const metadata_collision_output_id = metadataCollisionOutputId();

const metadata_collision_forged_descriptor: processor.ProcessorDescriptor = .{
    .id = .init(90),
    .packet_access = .trusted_raw_edit,
    .dispositions = .{ .accept = true },
    .outputs = &.{metadata_collision_output_id},
    .metadata_inputs = processor.MetadataKeys(.{ForgedMetadataInput}),
    .metadata_outputs = processor.MetadataKeys(.{ForgedMetadataOutput}),
    .work = .{ .maximum_total = packet.max_batch },
    .resource_categories = .{ .metadata_scratch = true },
};

var forged_read_rejected = false;
var forged_edit_rejected = false;
var forged_disposition_rejected = false;
var forged_output_rejected = false;
var forged_raw_rejected = false;
var forged_metadata_input_rejected = false;
var forged_metadata_output_rejected = false;
var forged_new_rejected = false;
var actual_narrow_succeeded = false;

const AuthorityStage = struct {
    /// Authority fixture has no prepared state.
    pub const Prepared = void;
    /// Authority fixture has no worker state.
    pub const Worker = void;
    /// Intentionally narrow descriptor sharing the forged descriptor identity.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(90),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Attempts exact-collision and typed-metadata authority substitution.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const cookie = @intFromEnum(context);
        const forged: processor.ProcessContext(collision_forged_descriptor) = @enumFromInt(cookie);
        var destination: [1]u8 = undefined;
        forged_read_rejected = if (forged.read(0, .{ .offset = 0, .len = 1 }, &destination))
            false
        else |err|
            err == error.DescriptorMismatch;
        forged_edit_rejected = if (forged.setIpv4Ttl(0, 1))
            false
        else |err|
            err == error.DescriptorMismatch;
        const active = context.active() catch unreachable;
        forged_disposition_rejected = if (forged.accept(active, null)) false else |err| err == error.DescriptorMismatch;
        forged_output_rejected = if (forged.accept(active, collision_output_id)) false else |err| err == error.DescriptorMismatch;
        forged_raw_rejected = if (forged.trustedRawWrite(
            0,
            .{ .offset = 0, .len = 0 },
            &.{},
            .{},
        )) false else |err| err == error.DescriptorMismatch;
        const metadata_forged: processor.ProcessContext(metadata_collision_forged_descriptor) = @enumFromInt(cookie);
        forged_metadata_input_rejected = if (metadata_forged.metadata(ForgedMetadataInput, 0)) |_| false else |err| err == error.DescriptorMismatch;
        forged_metadata_output_rejected = if (metadata_forged.produceMetadata(ForgedMetadataOutput, 0, 7))
            false
        else |err|
            err == error.DescriptorMismatch;
        const minted: processor.ProcessContext(descriptor) = @enumFromInt(cookie + 1);
        forged_new_rejected = if (minted.active()) |_| false else |err| err == error.InvocationInactive;
        actual_narrow_succeeded = (context.len() catch unreachable) == 1 and
            (context.origin() catch unreachable).input_id.raw() == 1;
        stale_authority_context = context;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

var stale_authority_context: ?processor.ProcessContext(AuthorityStage.descriptor) = null;

test "process contexts reject retyped broader, newly minted, and stale cookies" {
    try std.testing.expectEqual(
        @as(u64, 0x629b_8ddd_5171_2b5d),
        legacyAuthorityBinding(AuthorityStage.descriptor),
    );
    try std.testing.expectEqual(
        legacyAuthorityBinding(AuthorityStage.descriptor),
        legacyAuthorityBinding(collision_forged_descriptor),
    );
    try std.testing.expectEqual(
        legacyAuthorityBinding(AuthorityStage.descriptor),
        legacyAuthorityBinding(metadata_collision_forged_descriptor),
    );
    const P = pipeline.Pipeline(.{AuthorityStage});
    const unminted: processor.ProcessContext(AuthorityStage.descriptor) =
        @enumFromInt(std.math.maxInt(u64));
    try std.testing.expectError(error.InvocationInactive, unminted.active());
    forged_read_rejected = false;
    forged_edit_rejected = false;
    forged_disposition_rejected = false;
    forged_output_rejected = false;
    forged_raw_rejected = false;
    forged_metadata_input_rejected = false;
    forged_metadata_output_rejected = false;
    forged_new_rejected = false;
    actual_narrow_succeeded = false;
    stale_authority_context = null;
    const fixtures = [_]testing.PacketFixture{.{ .bytes = &.{1} }};
    const Harness = testing.ProcessorTestHarness(P);
    var harness = try Harness.init(
        std.testing.allocator,
        .{null},
        .{
            .packet_access = .trusted_raw_edit,
            .trusted_raw_edit_opt_in = true,
            .available_outputs = &.{ output_id, collision_output_id, metadata_collision_output_id },
            .dispositions = .{ .accept = true },
        },
        limits(P, 0, 0, 1, packet.max_batch),
        .{ .id = 1 },
    );
    defer harness.deinit();
    var result = try harness.submit(
        &fixtures,
        .{ .input_id = .init(1), .queue_id = .init(1) },
        9,
        try P.InputMetadata.init(fixtures.len),
        .{
            .outputs = &.{output_id},
            .default_output = output_id,
            .continue_policy = .{ .accept = output_id },
        },
    );
    defer result.deinit();
    try std.testing.expect(forged_read_rejected);
    try std.testing.expect(forged_edit_rejected);
    try std.testing.expect(forged_disposition_rejected);
    try std.testing.expect(forged_output_rejected);
    try std.testing.expect(forged_raw_rejected);
    try std.testing.expect(forged_metadata_input_rejected);
    try std.testing.expect(forged_metadata_output_rejected);
    try std.testing.expect(forged_new_rejected);
    try std.testing.expect(actual_narrow_succeeded);
    try std.testing.expectEqualSlices(u8, fixtures[0].bytes, result.packet_bytes[0]);
    try std.testing.expect(result.execution.final_dispositions[0] == .Accept);
    try std.testing.expectError(error.InvocationInactive, stale_authority_context.?.active());
}

const StageIsolationKey = struct {
    /// Stable two-stage isolation metadata identity.
    pub const id: u32 = 0x4953_4f01;
    /// Inline two-stage isolation metadata value.
    pub const Value = u16;
};

var isolated_narrow_read = false;
var isolated_narrow_broad_rejected = false;
var isolated_broad_metadata = false;
var isolated_broad_raw = false;
var isolated_broad_accept = false;

const IsolationNarrowStage = struct {
    /// Narrow fixture has no prepared state.
    pub const Prepared = void;
    /// Narrow fixture has no worker state.
    pub const Worker = void;
    /// Declares only read and metadata-production rights.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(93),
        .packet_access = .read,
        .metadata_outputs = processor.MetadataKeys(.{StageIsolationKey}),
        .work = .{ .maximum_total = packet.max_batch },
        .resource_categories = .{ .metadata_scratch = true },
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Uses only narrow rights and rejects the later stage's broader context.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        isolated_narrow_read = (context.packetLength(0) catch unreachable) == 46;
        context.produceMetadata(StageIsolationKey, 0, 0x5151) catch unreachable;
        const broad: processor.ProcessContext(IsolationBroadStage.descriptor) =
            @enumFromInt(@intFromEnum(context));
        isolated_narrow_broad_rejected = if (broad.trustedRawWrite(
            0,
            .{ .offset = 0, .len = 0 },
            &.{},
            .{},
        )) false else |err| err == error.DescriptorMismatch;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const IsolationBroadStage = struct {
    /// Broad fixture has no prepared state.
    pub const Prepared = void;
    /// Broad fixture has no worker state.
    pub const Worker = void;
    /// Declares raw edit, metadata consumption, output, and Accept rights.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(94),
        .packet_access = .trusted_raw_edit,
        .dispositions = .{ .accept = true },
        .outputs = &.{output_id},
        .metadata_inputs = processor.MetadataKeys(.{StageIsolationKey}),
        .work = .{ .maximum_total = packet.max_batch },
        .resource_categories = .{ .metadata_scratch = true },
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Uses the exact broad rights declared only for this later stage.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        isolated_broad_metadata = (context.metadata(StageIsolationKey, 0) catch unreachable) == 0x5151;
        context.trustedRawWrite(
            0,
            .{ .offset = 0, .len = 1 },
            &.{0},
            .{ .invalidates = .{ .l2 = true } },
        ) catch unreachable;
        context.finalize(0) catch unreachable;
        isolated_broad_raw = true;
        context.accept(active, output_id) catch unreachable;
        isolated_broad_accept = true;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

test "two stages isolate exact capabilities under broad application authority" {
    const P = pipeline.Pipeline(.{ IsolationNarrowStage, IsolationBroadStage });
    const Harness = testing.ProcessorTestHarness(P);
    isolated_narrow_read = false;
    isolated_narrow_broad_rejected = false;
    isolated_broad_metadata = false;
    isolated_broad_raw = false;
    isolated_broad_accept = false;
    var harness = try Harness.init(
        std.testing.allocator,
        .{ null, null },
        .{
            .packet_access = .trusted_raw_edit,
            .trusted_raw_edit_opt_in = true,
            .available_outputs = &.{output_id},
            .dispositions = .{ .accept = true, .drop = true },
            .monotonic_time = true,
        },
        limits(P, 0, 0, 1, packet.max_batch * 2),
        .{ .id = 1 },
    );
    defer harness.deinit();
    var bytes = mutableIpv4Fixture();
    const fixtures = [_]testing.PacketFixture{.{ .bytes = &bytes }};
    var result = try harness.submit(
        &fixtures,
        .{ .input_id = .init(1), .queue_id = .init(1) },
        9,
        try P.InputMetadata.init(fixtures.len),
        .{
            .outputs = &.{output_id},
            .default_output = output_id,
            .continue_policy = .{ .accept = output_id },
        },
    );
    defer result.deinit();
    try std.testing.expect(isolated_narrow_read);
    try std.testing.expect(isolated_narrow_broad_rejected);
    try std.testing.expect(isolated_broad_metadata);
    try std.testing.expect(isolated_broad_raw);
    try std.testing.expect(isolated_broad_accept);
    try std.testing.expectEqualSlices(u8, fixtures[0].bytes, result.packet_bytes[0]);
    try std.testing.expect(result.execution.final_dispositions[0] == .Accept);
}

var cross_thread_a_cookie = std.atomic.Value(u64).init(0);
var cross_thread_b_cookie = std.atomic.Value(u64).init(0);
var cross_thread_a_complete = std.atomic.Value(bool).init(false);
var cross_thread_failed = std.atomic.Value(bool).init(false);
var cross_thread_distinct = std.atomic.Value(bool).init(false);
var cross_thread_escaped_active_rejected = std.atomic.Value(bool).init(false);
var cross_thread_escaped_packet_rejected = std.atomic.Value(bool).init(false);
var cross_thread_current_active = std.atomic.Value(bool).init(false);

const CrossThreadAuthorityStage = struct {
    /// Cross-thread authority fixture has no prepared state.
    pub const Prepared = void;
    /// Worker identity selects the deterministic A or B role.
    pub const Worker = struct { id: u32 };
    /// Both threads invoke this exact descriptor and effective capability set.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(91),
        .packet_access = .read,
        .services = .{ .worker_state = true },
        .work = .{ .maximum_total = packet.max_batch },
        .update_modes = .{ .flush = true },
        .default_update_mode = .flush,
    };
    /// Reports bounded work and no allocated resources.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Retains only the scalar test worker identity.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, worker: processor.WorkerDescriptor) processor.InstantiationError!Worker {
        return .{ .id = worker.id };
    }
    /// Transfers A's completed scalar cookie into B's active same-descriptor call.
    pub fn processBatch(worker: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        const cookie = @intFromEnum(context);
        if (worker.id == 1) {
            cross_thread_a_cookie.store(cookie, .release);
        } else {
            const escaped_cookie = cross_thread_a_cookie.load(.acquire);
            cross_thread_b_cookie.store(cookie, .release);
            cross_thread_distinct.store(escaped_cookie != cookie, .release);
            const escaped: processor.ProcessContext(descriptor) = @enumFromInt(escaped_cookie);
            cross_thread_escaped_active_rejected.store(
                if (escaped.active()) |_| false else |err| err == error.InvocationInactive,
                .release,
            );
            cross_thread_escaped_packet_rejected.store(
                if (escaped.packetLength(0)) |_| false else |err| err == error.InvocationInactive,
                .release,
            );
            cross_thread_current_active.store(
                (context.packetLength(0) catch unreachable) == 1,
                .release,
            );
        }
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans scalar worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const CrossThreadAuthorityPipeline = pipeline.Pipeline(.{CrossThreadAuthorityStage});
const CrossThreadAuthorityHarness = testing.ProcessorTestHarness(CrossThreadAuthorityPipeline);

fn submitCrossThreadAuthority(harness: *CrossThreadAuthorityHarness) !void {
    const fixtures = [_]testing.PacketFixture{.{ .bytes = &.{1} }};
    var result = try harness.submit(
        &fixtures,
        .{ .input_id = .init(1), .queue_id = .init(1) },
        9,
        try CrossThreadAuthorityPipeline.InputMetadata.init(fixtures.len),
        .{
            .outputs = &.{output_id},
            .default_output = output_id,
            .continue_policy = .{ .accept = output_id },
        },
    );
    result.deinit();
}

fn runCrossThreadAuthorityA(harness: *CrossThreadAuthorityHarness) void {
    defer cross_thread_a_complete.store(true, .release);
    submitCrossThreadAuthority(harness) catch
        cross_thread_failed.store(true, .release);
}

fn runCrossThreadAuthorityB(harness: *CrossThreadAuthorityHarness) void {
    while (!cross_thread_a_complete.load(.acquire)) std.atomic.spinLoopHint();
    submitCrossThreadAuthority(harness) catch
        cross_thread_failed.store(true, .release);
}

test "same-descriptor process contexts are unique and inactive across threads" {
    cross_thread_a_cookie.store(0, .monotonic);
    cross_thread_b_cookie.store(0, .monotonic);
    cross_thread_a_complete.store(false, .monotonic);
    cross_thread_failed.store(false, .monotonic);
    cross_thread_distinct.store(false, .monotonic);
    cross_thread_escaped_active_rejected.store(false, .monotonic);
    cross_thread_escaped_packet_rejected.store(false, .monotonic);
    cross_thread_current_active.store(false, .monotonic);

    var harness_a = try CrossThreadAuthorityHarness.init(
        std.testing.allocator,
        .{null},
        .{ .packet_access = .read, .available_outputs = &.{output_id} },
        limits(CrossThreadAuthorityPipeline, 0, 0, 1, packet.max_batch),
        .{ .id = 1 },
    );
    defer harness_a.deinit();
    var harness_b = try CrossThreadAuthorityHarness.init(
        std.testing.allocator,
        .{null},
        .{ .packet_access = .read, .available_outputs = &.{output_id} },
        limits(CrossThreadAuthorityPipeline, 0, 0, 1, packet.max_batch),
        .{ .id = 2 },
    );
    defer harness_b.deinit();

    const thread_a = try std.Thread.spawn(.{}, runCrossThreadAuthorityA, .{&harness_a});
    const thread_b = try std.Thread.spawn(.{}, runCrossThreadAuthorityB, .{&harness_b});
    thread_a.join();
    thread_b.join();

    try std.testing.expect(!cross_thread_failed.load(.acquire));
    try std.testing.expect(cross_thread_a_cookie.load(.acquire) != 0);
    try std.testing.expect(cross_thread_b_cookie.load(.acquire) != 0);
    try std.testing.expect(cross_thread_distinct.load(.acquire));
    try std.testing.expect(cross_thread_escaped_active_rejected.load(.acquire));
    try std.testing.expect(cross_thread_escaped_packet_rejected.load(.acquire));
    try std.testing.expect(cross_thread_current_active.load(.acquire));
}

const TestMetric = struct {
    /// Stable test metric identity.
    pub const id = processor.MetricId.init(1);
    /// Bounded inline metric value.
    pub const Value = u64;
    /// Explicit finite cardinality.
    pub const maximum_series: u16 = 4;
};

const TestEvent = struct {
    /// Stable test event identity.
    pub const id = processor.EventId.init(1);
    /// Bounded inline event payload.
    pub const Payload = struct { code: u16 };
    /// Explicit finite per-batch record limit.
    pub const maximum_records_per_batch: u16 = 8;
};

const SchemaStage = struct {
    /// Schema fixture has no prepared state.
    pub const Prepared = void;
    /// Schema fixture has no worker state.
    pub const Worker = void;
    /// Declares concrete metric and event schemas without runtime handles.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(92),
        .metrics = processor.MetricDeclarations(.{TestMetric}),
        .events = processor.EventDeclarations(.{TestEvent}),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Reports exact bounded work.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Observes the active selection; observability runtime remains deferred.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

test "metric and event schemas require exact application availability before prepare" {
    const P = pipeline.Pipeline(.{SchemaStage});
    const exact = limits(P, 0, 0, 1, packet.max_batch);
    try std.testing.expectError(
        error.CapabilityUnavailable,
        P.prepare(std.testing.allocator, .{null}, .{}, exact),
    );
    try std.testing.expectError(
        error.CapabilityUnavailable,
        P.prepare(
            std.testing.allocator,
            .{null},
            .{ .available_metrics = &.{TestMetric.id} },
            exact,
        ),
    );
    const prepared = try P.prepare(
        std.testing.allocator,
        .{null},
        .{
            .available_metrics = &.{TestMetric.id},
            .available_events = &.{TestEvent.id},
        },
        exact,
    );
    try prepared.deinit();
}
