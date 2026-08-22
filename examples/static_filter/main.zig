// SPDX-License-Identifier: Apache-2.0
//! Deterministic three-processor static filter over the public synthetic
//! harness. It exercises preparation, worker-local state, fixed typed metadata,
//! mixed filtering, stage ordering, final acceptance, and reverse cleanup.

const std = @import("std");
const saint = @import("saint_shield");

const processor = saint.processor;
const packet = saint.packet;

const output_id = packet.OutputId.init(1);
const artifact_type = processor.ArtifactContentTypeId.init(1);

const Tenant = struct {
    /// Stable application input metadata identity.
    pub const id: u32 = 1;
    /// Tenant metadata value type.
    pub const Value = u8;
};

const Score = struct {
    /// Stable produced score metadata identity.
    pub const id: u32 = 2;
    /// Score metadata value type.
    pub const Value = u8;
};

const MetadataProducer = struct {
    /// Prepared producer state owns a copied configuration byte.
    pub const Prepared = struct {
        copied_artifact: []u8,
        bias: u8,
    };
    /// The producer needs no worker-local state.
    pub const Worker = void;
    /// Read-only metadata-producing stage declaration.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(1),
        .packet_access = .read,
        .requires_artifact = true,
        .artifact_content_type = artifact_type,
        .metadata_inputs = processor.MetadataKeys(.{Tenant}),
        .metadata_outputs = processor.MetadataKeys(.{Score}),
        .work = .{ .per_active_packet = 1, .maximum_total = packet.max_batch },
        .resource_categories = .{ .prepared_memory = true, .metadata_scratch = true },
    };

    /// Reports the artifact copy and bounded per-batch work.
    pub fn estimateResources(
        artifact: ?processor.ConfigurationArtifact,
        _: usize,
    ) processor.EstimateError!processor.ResourceEstimate {
        const supplied = artifact orelse return error.InvalidArtifact;
        if (supplied.payload.len != 1) return error.InvalidArtifact;
        return .{
            .prepared_bytes = @sizeOf(Prepared) + supplied.payload.len,
            .maximum_batch_work = packet.max_batch,
        };
    }

    /// Validates and copies the versioned producer artifact.
    pub fn prepare(
        allocator: std.mem.Allocator,
        artifact: ?processor.ConfigurationArtifact,
    ) processor.PreparationError!Prepared {
        const supplied = artifact orelse return error.InvalidArtifact;
        if (supplied.content_type.raw() != artifact_type.raw() or supplied.payload.len != 1)
            return error.InvalidArtifact;
        const copy = allocator.dupe(u8, supplied.payload) catch
            return error.ResourceUnderestimated;
        return .{ .copied_artifact = copy, .bias = copy[0] };
    }

    /// Constructs the producer's empty worker state.
    pub fn instantiate(
        _: std.mem.Allocator,
        _: *const Prepared,
        _: processor.WorkerDescriptor,
    ) processor.InstantiationError!Worker {}

    /// Copies packet data into typed score metadata.
    pub fn processBatch(
        _: *Worker,
        context: processor.ProcessContext(descriptor),
    ) processor.ProcessResult {
        const active = context.active() catch unreachable;
        var iterator = active.iterator();
        while (iterator.next()) |index| {
            var first_byte: [1]u8 = undefined;
            context.read(index.raw(), .{ .offset = 0, .len = 1 }, &first_byte) catch unreachable;
            const tenant = context.metadata(Tenant, index.raw()) catch unreachable orelse 0;
            context.produceMetadata(
                Score,
                index.raw(),
                first_byte[0] +% tenant,
            ) catch unreachable;
        }
        return .{
            .visited_packets = @intCast(active.count()),
            .work_units = @intCast(active.count()),
        };
    }

    /// Cleans the producer's empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}

    /// Releases the copied producer artifact.
    pub fn deinitPrepared(prepared: *Prepared, allocator: std.mem.Allocator) void {
        allocator.free(prepared.copied_artifact);
    }
};

const MixedFilter = struct {
    /// The filter needs no prepared state.
    pub const Prepared = void;
    /// Worker-local counter used by the example output.
    pub const Worker = struct { seen: u32 = 0 };
    /// Metadata-reading mixed-disposition filter declaration.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(2),
        .dispositions = .{ .drop = true },
        .metadata_inputs = processor.MetadataKeys(.{Score}),
        .services = .{ .worker_state = true },
        .work = .{ .per_active_packet = 1, .maximum_total = packet.max_batch },
        .process_error_mode = .bounded,
        .error_policy = .{ .terminal_active = .{ .drop = .init(99) } },
        .update_modes = .{ .flush = true },
        .default_update_mode = .flush,
        .resource_categories = .{ .worker_memory = true, .metadata_scratch = true },
    };

    /// Reports the worker-state size and bounded work.
    pub fn estimateResources(
        _: ?processor.ConfigurationArtifact,
        _: usize,
    ) processor.EstimateError!processor.ResourceEstimate {
        return .{
            .worker_bytes = @sizeOf(Worker),
            .maximum_batch_work = packet.max_batch,
        };
    }
    /// Constructs the filter's empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs one worker-local filter counter.
    pub fn instantiate(
        _: std.mem.Allocator,
        _: *const Prepared,
        _: processor.WorkerDescriptor,
    ) processor.InstantiationError!Worker {
        return .{};
    }
    /// Drops low-score packets and leaves the remaining selection active.
    pub fn processBatch(
        worker: *Worker,
        context: processor.ProcessContext(descriptor),
    ) processor.ProcessError!processor.ProcessResult {
        const active = context.active() catch return error.InvalidPacket;
        var iterator = active.iterator();
        while (iterator.next()) |index| {
            worker.seen += 1;
            const score = (context.metadata(Score, index.raw()) catch return error.InvalidPacket) orelse
                return error.StateUnavailable;
            if (score < 10) {
                const batch_len = context.len() catch return error.InvalidPacket;
                const selection = packet.PacketSelection.one(index.raw(), batch_len) catch
                    return error.InvalidPacket;
                context.drop(selection, .init(7)) catch return error.InvalidPacket;
            }
        }
        return .{
            .visited_packets = @intCast(active.count()),
            .work_units = @intCast(active.count()),
        };
    }
    /// Cleans the inline worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans the empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const FinalAccept = struct {
    /// The final stage needs no prepared state.
    pub const Prepared = void;
    /// The final stage needs no worker state.
    pub const Worker = void;
    /// Final explicit acceptance stage declaration.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(3),
        .dispositions = .{ .accept = true },
        .outputs = &.{output_id},
        .metadata_inputs = processor.MetadataKeys(.{Score}),
        .work = .{ .per_active_packet = 1, .maximum_total = packet.max_batch },
        .resource_categories = .{ .metadata_scratch = true },
    };
    /// Reports bounded final-stage work.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs the final stage's empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs the final stage's empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Accepts every packet still active at the final stage.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        if (!active.isEmpty()) context.accept(active, output_id) catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans the final stage's empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans the final stage's empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

const StaticFilter = saint.pipeline.PipelineWithInputMetadata(
    .{ MetadataProducer, MixedFilter, FinalAccept },
    processor.MetadataKeys(.{Tenant}),
);

/// Runs the deterministic public M3 example without live traffic.
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const artifact_payload = [_]u8{2};
    const artifact = processor.ConfigurationArtifact{
        .revision = 1,
        .content_type = artifact_type,
        .payload = &artifact_payload,
        .source_id = 1,
    };
    const metadata_scratch = StaticFilter.InputMetadata.scratchBytes();
    var harness = try saint.testing.ProcessorTestHarness(StaticFilter).init(
        allocator,
        .{ artifact, null, null },
        .{ .packet_access = .read, .available_outputs = &.{output_id} },
        .{
            .prepared_bytes = try StaticFilter.frameworkPreparedBytes(1) +
                @sizeOf(MetadataProducer.Prepared) + artifact_payload.len,
            .worker_bytes_each = StaticFilter.frameworkWorkerBytesEach() + @sizeOf(MixedFilter.Worker),
            .worker_bytes_total = StaticFilter.frameworkWorkerBytesEach() + @sizeOf(MixedFilter.Worker),
            .metadata_scratch_bytes_each = metadata_scratch,
            .metadata_scratch_bytes_total = metadata_scratch,
            .maximum_batch_work = packet.max_batch * 3,
            .worker_count = 1,
        },
        .{ .id = 7 },
    );
    defer harness.deinit();

    var input_metadata = try StaticFilter.InputMetadata.init(4);
    for (0..4) |index| try input_metadata.put(Tenant, index, 1);
    const fixtures = [_]saint.testing.PacketFixture{
        .{ .bytes = &.{3} },
        .{ .bytes = &.{9} },
        .{ .bytes = &.{20}, .split_offsets = &.{0} },
        .{ .bytes = &.{7} },
    };
    var result = try harness.submit(
        &fixtures,
        .{ .input_id = .init(1), .queue_id = .init(2) },
        123_456,
        input_metadata,
        .{
            .outputs = &.{output_id},
            .default_output = output_id,
            .continue_policy = .{ .drop = .init(88) },
        },
    );
    defer result.deinit();

    std.debug.print(
        "saint-shield {s} m3-static-filter packets={d} accepted={d} dropped={d}\n",
        .{
            saint.version,
            result.packet_count,
            result.execution.dispositions.outputs[0].count,
            result.execution.dispositions.drop_count,
        },
    );
}
