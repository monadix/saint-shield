// SPDX-License-Identifier: Apache-2.0
//! Synthetic host-local M3 dispatch benchmark. The monolith and batch-vtable
//! paths are non-comparable diagnostic-only controls; they are not imported by
//! the framework and cannot support acceptance or architecture decisions.

const std = @import("std");
const saint = @import("saint_shield");

const packet = saint.packet;
const processor = saint.processor;
const pipeline = saint.pipeline;

const samples_per_run = 5;
const warmup_iterations = 200;
const measurement_iterations = 2_000;

extern fn saint_cycle_begin() callconv(.c) u64;
extern fn saint_cycle_end() callconv(.c) u64;

fn Noop(comptime id: u64) type {
    return struct {
        /// Direct-stage fixture has no prepared state.
        pub const Prepared = void;
        /// Direct-stage fixture has no worker state.
        pub const Worker = void;
        /// Valid bounded descriptor for one benchmark stage.
        pub const descriptor: processor.ProcessorDescriptor = .{
            .id = .init(id),
            .work = .{ .maximum_total = packet.max_batch },
        };
        /// Reports bounded work and no allocated resources.
        pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
            return .{ .maximum_batch_work = packet.max_batch };
        }
        /// Constructs the empty prepared benchmark state.
        pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
        /// Constructs the empty worker benchmark state.
        pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
        /// Executes one direct no-op stage over the active selection.
        pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
            const active = context.active() catch unreachable;
            return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
        }
        /// Cleans the empty worker benchmark state.
        pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
        /// Cleans the empty prepared benchmark state.
        pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
    };
}

const P0 = pipeline.Pipeline(.{});
const P1 = pipeline.Pipeline(.{Noop(1)});
const P2 = pipeline.Pipeline(.{ Noop(1), Noop(2) });
const P4 = pipeline.Pipeline(.{ Noop(1), Noop(2), Noop(3), Noop(4) });
const P8 = pipeline.Pipeline(.{ Noop(1), Noop(2), Noop(3), Noop(4), Noop(5), Noop(6), Noop(7), Noop(8) });

var terminal_successor_calls: usize = 0;

const DropAll = struct {
    /// Terminal fixture has no prepared state.
    pub const Prepared = void;
    /// Terminal fixture has no worker state.
    pub const Worker = void;
    /// Declares the terminal drop used by the deep short-circuit benchmark.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(20),
        .dispositions = .{ .drop = true },
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
    /// Terminates every active packet at the first stage.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        context.drop(active, .init(20)) catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

fn CountSuccessor(comptime id: u64) type {
    return struct {
        /// Counter fixture has no prepared state.
        pub const Prepared = void;
        /// Counter fixture has no worker state.
        pub const Worker = void;
        /// Declares one successor that must never be invoked.
        pub const descriptor: processor.ProcessorDescriptor = .{
            .id = .init(id),
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
        /// Records an invalid successor invocation.
        pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
            terminal_successor_calls += 1;
            const active = context.active() catch unreachable;
            return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
        }
        /// Cleans empty worker state.
        pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
        /// Cleans empty prepared state.
        pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
    };
}

const PTerminal = pipeline.Pipeline(.{ DropAll, CountSuccessor(21), CountSuccessor(22), CountSuccessor(23) });

const Variant = enum(u8) { direct0, direct1, direct2, direct4, direct8, terminal4, monolith, batch_vtable };
const BatchFn = *const fn (usize) callconv(.c) usize;

fn vtableNoop(count: usize) callconv(.c) usize {
    return count;
}

var cleanup_audit_enabled = false;
var cleanup_audit: [12]u8 = undefined;
var cleanup_audit_len: usize = 0;
var token_audit_observed = false;
var token_audit_received: usize = 0;
var token_audit_completed: usize = 0;

fn recordCleanup(resource: u8) void {
    if (!cleanup_audit_enabled) return;
    cleanup_audit[cleanup_audit_len] = resource;
    cleanup_audit_len += 1;
}

fn reconcileTokens(
    tracker: *packet.TokenTracker,
    slots: []const packet.PacketSlot,
) void {
    for (slots) |slot| slot.adapterToken().returnToInput() catch unreachable;
    tracker.verifyReceivedCompleted() catch unreachable;
    if (cleanup_audit_enabled) {
        token_audit_observed = true;
        token_audit_received = tracker.receivedCount();
        token_audit_completed = tracker.completionCount();
    }
}

const Bench = struct {
    allocator: std.mem.Allocator,
    tracker: *packet.TokenTracker,
    owner: *packet.PacketBatchOwner,
    slots: [packet.max_batch]packet.PacketSlot,
    control_metadata: processor.MetadataStore = .{},
    prepared0: *P0.PreparedPipeline,
    prepared1: *P1.PreparedPipeline,
    prepared2: *P2.PreparedPipeline,
    prepared4: *P4.PreparedPipeline,
    prepared8: *P8.PreparedPipeline,
    prepared_terminal: *PTerminal.PreparedPipeline,
    worker0: P0.WorkerHandle,
    worker1: P1.WorkerHandle,
    worker2: P2.WorkerHandle,
    worker4: P4.WorkerHandle,
    worker8: P8.WorkerHandle,
    worker_terminal: PTerminal.WorkerHandle,

    fn limits(comptime P: type, comptime stages: usize) processor.ResourceLimits {
        return .{
            .prepared_bytes = P.frameworkPreparedBytes(1) catch unreachable,
            .worker_bytes_each = P.frameworkWorkerBytesEach(),
            .worker_bytes_total = P.frameworkWorkerBytesEach(),
            .metadata_scratch_bytes_each = P.InputMetadata.scratchBytes(),
            .metadata_scratch_bytes_total = P.InputMetadata.scratchBytes(),
            .maximum_batch_work = packet.max_batch * stages,
            .worker_count = 1,
        };
    }

    fn init(allocator: std.mem.Allocator) !Bench {
        const tracker = try allocator.create(packet.TokenTracker);
        errdefer allocator.destroy(tracker);
        tracker.* = try packet.TokenTracker.init(allocator, packet.max_batch);
        errdefer tracker.deinit();
        var slots: [packet.max_batch]packet.PacketSlot = undefined;
        var initialized_slots: usize = 0;
        const owner = try packet.PacketBatchOwner.init(allocator);
        errdefer owner.deinit();
        errdefer reconcileTokens(tracker, slots[0..initialized_slots]);
        const fixture = [_]u8{0};
        const descriptors = [_]packet.SegmentDescriptor{.fromBytes(&fixture)};
        for (&slots, 0..) |*slot, index| {
            const token = try tracker.registerInput();
            try token.receive();
            slot.* = packet.PacketSlot.init(
                token,
                &descriptors,
                fixture.len,
                index,
                .{},
                null,
            ) catch |err| {
                token.returnToInput() catch unreachable;
                return err;
            };
            initialized_slots += 1;
        }
        const p0 = try P0.prepare(allocator, .{}, .{}, limits(P0, 0));
        errdefer {
            p0.deinit() catch unreachable;
            recordCleanup(1);
        }
        const p1 = try P1.prepare(allocator, .{null}, .{}, limits(P1, 1));
        errdefer {
            p1.deinit() catch unreachable;
            recordCleanup(2);
        }
        const p2 = try P2.prepare(allocator, .{ null, null }, .{}, limits(P2, 2));
        errdefer {
            p2.deinit() catch unreachable;
            recordCleanup(3);
        }
        const p4 = try P4.prepare(allocator, .{ null, null, null, null }, .{}, limits(P4, 4));
        errdefer {
            p4.deinit() catch unreachable;
            recordCleanup(4);
        }
        const p8 = try P8.prepare(allocator, .{ null, null, null, null, null, null, null, null }, .{}, limits(P8, 8));
        errdefer {
            p8.deinit() catch unreachable;
            recordCleanup(5);
        }
        const p_terminal = try PTerminal.prepare(
            allocator,
            .{ null, null, null, null },
            .{},
            limits(PTerminal, 4),
        );
        errdefer {
            p_terminal.deinit() catch unreachable;
            recordCleanup(6);
        }
        var w0 = try P0.instantiate(p0, .{ .id = 1 });
        errdefer {
            p0.deinitWorker(&w0) catch unreachable;
            recordCleanup(7);
        }
        var w1 = try P1.instantiate(p1, .{ .id = 1 });
        errdefer {
            p1.deinitWorker(&w1) catch unreachable;
            recordCleanup(8);
        }
        var w2 = try P2.instantiate(p2, .{ .id = 1 });
        errdefer {
            p2.deinitWorker(&w2) catch unreachable;
            recordCleanup(9);
        }
        var w4 = try P4.instantiate(p4, .{ .id = 1 });
        errdefer {
            p4.deinitWorker(&w4) catch unreachable;
            recordCleanup(10);
        }
        var w8 = try P8.instantiate(p8, .{ .id = 1 });
        errdefer {
            p8.deinitWorker(&w8) catch unreachable;
            recordCleanup(11);
        }
        var w_terminal = try PTerminal.instantiate(p_terminal, .{ .id = 1 });
        errdefer {
            p_terminal.deinitWorker(&w_terminal) catch unreachable;
            recordCleanup(12);
        }
        return .{
            .allocator = allocator,
            .tracker = tracker,
            .owner = owner,
            .slots = slots,
            .prepared0 = p0,
            .prepared1 = p1,
            .prepared2 = p2,
            .prepared4 = p4,
            .prepared8 = p8,
            .prepared_terminal = p_terminal,
            .worker0 = w0,
            .worker1 = w1,
            .worker2 = w2,
            .worker4 = w4,
            .worker8 = w8,
            .worker_terminal = w_terminal,
        };
    }

    fn deinit(self: *Bench) void {
        self.prepared_terminal.deinitWorker(&self.worker_terminal) catch unreachable;
        recordCleanup(12);
        self.prepared8.deinitWorker(&self.worker8) catch unreachable;
        recordCleanup(11);
        self.prepared4.deinitWorker(&self.worker4) catch unreachable;
        recordCleanup(10);
        self.prepared2.deinitWorker(&self.worker2) catch unreachable;
        recordCleanup(9);
        self.prepared1.deinitWorker(&self.worker1) catch unreachable;
        recordCleanup(8);
        self.prepared0.deinitWorker(&self.worker0) catch unreachable;
        recordCleanup(7);
        self.prepared_terminal.deinit() catch unreachable;
        recordCleanup(6);
        self.prepared8.deinit() catch unreachable;
        recordCleanup(5);
        self.prepared4.deinit() catch unreachable;
        recordCleanup(4);
        self.prepared2.deinit() catch unreachable;
        recordCleanup(3);
        self.prepared1.deinit() catch unreachable;
        recordCleanup(2);
        self.prepared0.deinit() catch unreachable;
        recordCleanup(1);
        reconcileTokens(self.tracker, &self.slots);
        self.owner.deinit();
        self.tracker.deinit();
        self.allocator.destroy(self.tracker);
    }

    fn runPipeline(
        self: *Bench,
        comptime P: type,
        prepared: *P.PreparedPipeline,
        worker: P.WorkerHandle,
        batch_size: usize,
    ) usize {
        const batch = self.owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            self.slots[0..batch_size],
        ) catch unreachable;
        defer batch.invalidate(self.owner) catch unreachable;
        const input = P.InputMetadata.init(batch_size) catch unreachable;
        const result = prepared.processBatch(worker, self.owner, batch, input, .{
            .outputs = &.{},
            .default_output = null,
            .continue_policy = .{ .drop = .init(1) },
        }, 0) catch unreachable;
        return result.dispositions.drop_count;
    }

    fn runControl(self: *Bench, comptime indirect: bool, batch_size: usize) usize {
        const batch = self.owner.begin(
            .{ .input_id = .init(1), .queue_id = .init(1) },
            self.slots[0..batch_size],
        ) catch unreachable;
        defer batch.invalidate(self.owner) catch unreachable;
        const writer = packet.DispositionWriter.init(batch, self.owner) catch unreachable;
        const input = P4.InputMetadata.init(batch_size) catch unreachable;
        self.control_metadata = input.store;
        const active = writer.activeSelection(self.owner) catch unreachable;
        var total = active.count();
        if (indirect) {
            const functions = [_]BatchFn{ vtableNoop, vtableNoop, vtableNoop, vtableNoop };
            for (functions) |function| total = function(total);
        } else {
            inline for (0..4) |_| total +%= active.count();
        }
        std.mem.doNotOptimizeAway(&total);
        const groups = packet.DispositionGroups.resolve(writer, self.owner, .{
            .outputs = &.{},
            .default_output = null,
            .continue_policy = .{ .drop = .init(1) },
        }) catch unreachable;
        return groups.drop_count;
    }

    fn run(self: *Bench, variant: Variant, batch_size: usize) usize {
        return switch (variant) {
            .direct0 => self.runPipeline(P0, self.prepared0, self.worker0, batch_size),
            .direct1 => self.runPipeline(P1, self.prepared1, self.worker1, batch_size),
            .direct2 => self.runPipeline(P2, self.prepared2, self.worker2, batch_size),
            .direct4 => self.runPipeline(P4, self.prepared4, self.worker4, batch_size),
            .direct8 => self.runPipeline(P8, self.prepared8, self.worker8, batch_size),
            .terminal4 => self.runPipeline(
                PTerminal,
                self.prepared_terminal,
                self.worker_terminal,
                batch_size,
            ),
            .monolith => self.runControl(false, batch_size),
            .batch_vtable => self.runControl(true, batch_size),
        };
    }
};

test "benchmark constructor allocation sweep reconciles tokens and exact reverse teardown" {
    cleanup_audit_enabled = true;
    defer cleanup_audit_enabled = false;
    var reached_nonfailing_index = false;
    for (0..256) |fail_index| {
        cleanup_audit_len = 0;
        token_audit_observed = false;
        token_audit_received = 0;
        token_audit_completed = 0;
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
            .fail_index = fail_index,
        });
        const maybe_bench = Bench.init(failing.allocator());
        if (maybe_bench) |value| {
            var bench = value;
            bench.deinit();
        } else |_| {}
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        if (cleanup_audit_len > 1) {
            for (cleanup_audit[1..cleanup_audit_len], cleanup_audit[0 .. cleanup_audit_len - 1]) |current, previous|
                try std.testing.expect(current < previous);
        }
        if (token_audit_observed)
            try std.testing.expectEqual(token_audit_received, token_audit_completed);
        if (!failing.has_induced_failure) {
            reached_nonfailing_index = true;
            try std.testing.expectEqual(@as(usize, cleanup_audit.len), cleanup_audit_len);
            try std.testing.expect(token_audit_observed);
            break;
        }
    }
    try std.testing.expect(reached_nonfailing_index);
}

fn monotonicNs() u64 {
    var timestamp: std.os.linux.timespec = undefined;
    const rc = std.os.linux.clock_gettime(.MONOTONIC_RAW, &timestamp);
    if (rc != 0) unreachable;
    return @as(u64, @intCast(timestamp.sec)) * std.time.ns_per_s +
        @as(u64, @intCast(timestamp.nsec));
}

const Measurement = struct { elapsed_ns: u64, cycles: u64 };

fn measure(bench: *Bench, variant: Variant, batch_size: usize) Measurement {
    const started = monotonicNs();
    const cycle_started = saint_cycle_begin();
    var checksum: usize = 0;
    for (0..measurement_iterations) |_| checksum +%= bench.run(variant, batch_size);
    const cycles = saint_cycle_end() - cycle_started;
    const elapsed = monotonicNs() - started;
    std.mem.doNotOptimizeAway(&checksum);
    return .{ .elapsed_ns = elapsed, .cycles = cycles };
}

/// Emits deterministic shuffled M3 cycle and packet-rate samples.
pub fn main(init: std.process.Init.Minimal) !void {
    var arguments = std.process.Args.Iterator.init(init.args);
    _ = arguments.next();
    var run_id: u32 = 0;
    while (arguments.next()) |argument| {
        if (!std.mem.eql(u8, argument, "--run-id")) return error.InvalidArgument;
        const value = arguments.next() orelse return error.InvalidArgument;
        run_id = std.fmt.parseInt(u32, value, 10) catch return error.InvalidArgument;
    }
    var bench = try Bench.init(std.heap.page_allocator);
    defer bench.deinit();
    const variants = [_]Variant{ .direct0, .direct1, .direct2, .direct4, .direct8, .terminal4, .monolith, .batch_vtable };
    const batches = [_]usize{ 32, 64 };
    terminal_successor_calls = 0;
    _ = bench.run(.terminal4, 64);
    if (terminal_successor_calls != 0) return error.TerminalSuccessorCalled;
    std.debug.print(
        "settings run_id={d} samples={d} warmup_iterations={d} measurement_iterations={d} seed={d} claim=synthetic-regression-not-capacity\n",
        .{ run_id, samples_per_run, warmup_iterations, measurement_iterations, @as(u64, 0x4d33_4245_4e43_4831) + run_id },
    );
    for (batches) |batch_size| {
        for (variants) |variant| {
            var ignored: usize = 0;
            for (0..warmup_iterations) |_| ignored +%= bench.run(variant, batch_size);
            std.mem.doNotOptimizeAway(&ignored);
        }
        var prng = std.Random.DefaultPrng.init(0x4d33_4245_4e43_4831 + batch_size + run_id);
        const random = prng.random();
        for (0..samples_per_run) |sample| {
            var order = variants;
            random.shuffle(Variant, &order);
            for (order, 0..) |variant, order_index| {
                const measurement = measure(&bench, variant, batch_size);
                const packets: f64 = @floatFromInt(measurement_iterations * batch_size);
                const pps = packets * 1_000_000_000.0 / @as(f64, @floatFromInt(measurement.elapsed_ns));
                const ns_per_packet = @as(f64, @floatFromInt(measurement.elapsed_ns)) / packets;
                const cycles_per_packet = @as(f64, @floatFromInt(measurement.cycles)) / packets;
                std.debug.print(
                    "run_id={d} batch={d} sample={d} order={d} variant={s} elapsed_ns={d} cycles={d} ns_per_packet={d:.6} cycles_per_packet={d:.6} packet_rate={d:.3}\n",
                    .{ run_id, batch_size, sample + 1, order_index + 1, @tagName(variant), measurement.elapsed_ns, measurement.cycles, ns_per_packet, cycles_per_packet, pps },
                );
            }
        }
    }
    if (terminal_successor_calls != 0) return error.TerminalSuccessorCalled;
}
