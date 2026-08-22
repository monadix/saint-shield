// SPDX-License-Identifier: Apache-2.0
//! Compile-time validated static processor pipelines with counted lifecycle
//! allocation, exact reverse cleanup, fixed typed metadata, direct stage calls,
//! and explicit error/default resolution.

const std = @import("std");
const internal_invocation = @import("../internal/processor_invocation.zig");
const packet = @import("../packet/root.zig");
const processor = @import("../processor/root.zig");

/// Candidate construction and execution failures exposed by a generated
/// pipeline. Processor-specific details remain in bounded stage status.
pub const PipelineError = error{
    OutOfMemory,
    InvalidResourceLimits,
    ResourceOverflow,
    ResourceLimitExceeded,
    CapabilityUnavailable,
    EstimateFailed,
    PreparationFailed,
    InstantiationFailed,
    ResourceUnderestimated,
    MetadataFailure,
    BatchFailure,
    DispositionFailure,
    InvocationFailure,
    WorkerCapacityExceeded,
    WorkersStillLive,
    StaleWorker,
    WrongWorkerOwner,
    OwnerIdentityExhausted,
    WorkContractViolation,
};

var prepared_identity_counter = std.atomic.Value(u64).init(0);

fn nextPreparedIdentity() PipelineError!u64 {
    var current = prepared_identity_counter.load(.monotonic);
    while (true) {
        if (current == std.math.maxInt(u64)) return error.OwnerIdentityExhausted;
        const next = current + 1;
        if (prepared_identity_counter.cmpxchgWeak(
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

/// One direct stage's bounded execution trace.
pub const StageStatus = enum(u8) {
    not_run,
    ok,
    skipped_empty,
    failed_continue,
    failed_terminal,
    failed_stop,
    contract_violation,
};

/// Aggregated values computed before any processor preparation.
pub const AggregateEstimate = struct {
    processor_prepared_bytes: usize,
    framework_prepared_bytes: usize,
    prepared_bytes: usize,
    processor_worker_bytes_each: usize,
    framework_worker_bytes_each: usize,
    worker_bytes_each: usize,
    worker_bytes_total: usize,
    metadata_scratch_bytes_each: usize,
    metadata_scratch_bytes_total: usize,
    bounded_pool_bytes_each: usize,
    bounded_pool_bytes_total: usize,
    maximum_batch_work: usize,
};

const LifecyclePart = enum { prepared, worker };

fn typeList(comptime ProcessorTypes: anytype, comptime field: LifecyclePart) [ProcessorTypes.len]type {
    var result: [ProcessorTypes.len]type = undefined;
    inline for (ProcessorTypes, 0..) |P, index| {
        result[index] = if (field == .prepared) P.Prepared else P.Worker;
    }
    return result;
}

fn TupleFor(comptime ProcessorTypes: anytype, comptime field: LifecyclePart) type {
    const types = typeList(ProcessorTypes, field);
    return std.meta.Tuple(&types);
}

fn KeyList(comptime keys: anytype) type {
    return struct {
        /// Compile-time ordered metadata key types.
        pub const list = keys;
    };
}

fn keyIndex(comptime keys: anytype, comptime Key: type) ?usize {
    inline for (keys, 0..) |candidate, index| {
        if (candidate.id == Key.id) return index;
    }
    return null;
}

fn appendUniqueKeys(comptime existing: anytype, comptime additions: anytype, comptime index: usize) type {
    if (index == additions.len) return KeyList(existing);
    const Key = additions[index];
    if (keyIndex(existing, Key)) |found| {
        if (existing[found].Value != Key.Value)
            @compileError("metadata type conflict for key id");
        return appendUniqueKeys(existing, additions, index + 1);
    }
    return appendUniqueKeys(existing ++ .{Key}, additions, index + 1);
}

fn collectProcessorKeys(
    comptime ProcessorTypes: anytype,
    comptime processor_index: usize,
    comptime current: anytype,
) type {
    if (processor_index == ProcessorTypes.len) return KeyList(current);
    const appended = appendUniqueKeys(
        current,
        ProcessorTypes[processor_index].descriptor.metadata_outputs.list,
        0,
    );
    return collectProcessorKeys(ProcessorTypes, processor_index + 1, appended.list);
}

fn allMetadataKeys(comptime ProcessorTypes: anytype, comptime InputMetadataKeys: anytype) type {
    return collectProcessorKeys(ProcessorTypes, 0, InputMetadataKeys);
}

fn keyExclusive(comptime Key: type) bool {
    return if (@hasDecl(Key, "exclusive")) Key.exclusive else true;
}

fn producedBefore(
    comptime ProcessorTypes: anytype,
    comptime stage_index: usize,
    comptime InputMetadataKeys: anytype,
    comptime Key: type,
) bool {
    if (keyIndex(InputMetadataKeys, Key)) |input_index| {
        if (InputMetadataKeys[input_index].Value != Key.Value)
            @compileError("input metadata type conflict");
        return true;
    }
    inline for (ProcessorTypes, 0..) |Earlier, earlier_index| {
        if (earlier_index < stage_index) {
            if (keyIndex(Earlier.descriptor.metadata_outputs.list, Key)) |output_index| {
                if (Earlier.descriptor.metadata_outputs.list[output_index].Value != Key.Value)
                    @compileError("produced metadata type conflict");
                return true;
            }
        }
    }
    return false;
}

fn validateMetadata(comptime ProcessorTypes: anytype, comptime InputMetadataKeys: anytype) void {
    inline for (InputMetadataKeys, 0..) |Key, index| {
        processor.validateInlineValueType(Key.Value, "metadata value");
        if (@sizeOf(Key.Value) > processor.MetadataStore.max_value_size)
            @compileError("metadata value exceeds fixed M3 slot size");
        if (Key.id == 0) @compileError("input metadata id must be nonzero");
        inline for (InputMetadataKeys, 0..) |Earlier, earlier_index| {
            if (earlier_index < index and Earlier.id == Key.id)
                @compileError("duplicate input metadata id");
        }
    }

    inline for (ProcessorTypes, 0..) |P, stage_index| {
        inline for (P.descriptor.metadata_inputs.list) |Key| {
            processor.validateInlineValueType(Key.Value, "metadata value");
            if (!producedBefore(ProcessorTypes, stage_index, InputMetadataKeys, Key))
                @compileError("metadata consumed before producer or typed pipeline input");
        }
        inline for (P.descriptor.metadata_outputs.list, 0..) |Key, output_index| {
            processor.validateInlineValueType(Key.Value, "metadata value");
            if (@sizeOf(Key.Value) > processor.MetadataStore.max_value_size)
                @compileError("metadata value exceeds fixed M3 slot size");
            if (Key.id == 0) @compileError("metadata output id must be nonzero");
            inline for (P.descriptor.metadata_outputs.list, 0..) |Earlier, earlier_index| {
                if (earlier_index < output_index and Earlier.id == Key.id)
                    @compileError("duplicate metadata producer in one stage");
            }
            inline for (ProcessorTypes, 0..) |EarlierProcessor, earlier_stage_index| {
                if (earlier_stage_index < stage_index) {
                    inline for (EarlierProcessor.descriptor.metadata_outputs.list) |EarlierKey| {
                        if (EarlierKey.id != Key.id) continue;
                        if (EarlierKey.Value != Key.Value)
                            @compileError("metadata producer type conflict");
                        if (keyExclusive(EarlierKey) or keyExclusive(Key))
                            @compileError("duplicate exclusive metadata producer");
                    }
                }
            }
        }
    }
}

fn validateSchemas(comptime ProcessorTypes: anytype) void {
    inline for (ProcessorTypes, 0..) |P, stage_index| {
        inline for (P.descriptor.metrics.list, 0..) |Metric, metric_index| {
            if (!@hasDecl(Metric, "id") or @TypeOf(Metric.id) != processor.MetricId)
                @compileError("metric declaration requires id: MetricId");
            if (!@hasDecl(Metric, "Value")) @compileError("metric declaration missing Value");
            if (!@hasDecl(Metric, "maximum_series") or @TypeOf(Metric.maximum_series) != u16 or
                Metric.maximum_series == 0)
                @compileError("metric declaration requires nonzero maximum_series: u16");
            processor.validateInlineValueType(Metric.Value, "metric value");
            inline for (P.descriptor.metrics.list, 0..) |Earlier, earlier_index| {
                if (earlier_index < metric_index and Earlier.id.raw() == Metric.id.raw())
                    @compileError("duplicate metric id in processor");
            }
            inline for (ProcessorTypes, 0..) |EarlierP, earlier_stage| {
                if (earlier_stage < stage_index) inline for (EarlierP.descriptor.metrics.list) |Earlier| {
                    if (Earlier.id.raw() == Metric.id.raw() and
                        (Earlier.Value != Metric.Value or Earlier.maximum_series != Metric.maximum_series))
                        @compileError("conflicting metric declaration across pipeline");
                };
            }
        }
        inline for (P.descriptor.events.list, 0..) |Event, event_index| {
            if (!@hasDecl(Event, "id") or @TypeOf(Event.id) != processor.EventId)
                @compileError("event declaration requires id: EventId");
            if (!@hasDecl(Event, "Payload")) @compileError("event declaration missing Payload");
            if (!@hasDecl(Event, "maximum_records_per_batch") or
                @TypeOf(Event.maximum_records_per_batch) != u16 or
                Event.maximum_records_per_batch == 0)
                @compileError("event declaration requires nonzero maximum_records_per_batch: u16");
            processor.validateInlineValueType(Event.Payload, "event payload");
            inline for (P.descriptor.events.list, 0..) |Earlier, earlier_index| {
                if (earlier_index < event_index and Earlier.id.raw() == Event.id.raw())
                    @compileError("duplicate event id in processor");
            }
            inline for (ProcessorTypes, 0..) |EarlierP, earlier_stage| {
                if (earlier_stage < stage_index) inline for (EarlierP.descriptor.events.list) |Earlier| {
                    if (Earlier.id.raw() == Event.id.raw() and
                        (Earlier.Payload != Event.Payload or
                            Earlier.maximum_records_per_batch != Event.maximum_records_per_batch))
                        @compileError("conflicting event declaration across pipeline");
                };
            }
        }
    }
}

fn hasOutput(comptime outputs: []const packet.OutputId, comptime output: packet.OutputId) bool {
    inline for (outputs) |candidate| if (candidate.raw() == output.raw()) return true;
    return false;
}

fn validateTerminalPolicy(comptime descriptor: processor.ProcessorDescriptor, comptime terminal: processor.TerminalDisposition) void {
    switch (terminal) {
        .accept => |output| {
            if (!descriptor.dispositions.accept) @compileError("error policy uses undeclared Accept");
            if (output) |id| if (!hasOutput(descriptor.outputs, id))
                @compileError("error policy uses undeclared output");
        },
        .drop => if (!descriptor.dispositions.drop)
            @compileError("error policy uses undeclared Drop"),
        .redirect => |redirect| {
            if (!descriptor.dispositions.redirect) @compileError("error policy uses undeclared Redirect");
            if (!hasOutput(descriptor.outputs, redirect.output))
                @compileError("error policy uses undeclared redirect output");
        },
        .complete => if (!descriptor.dispositions.complete)
            @compileError("error policy uses undeclared Complete"),
    }
}

fn exactFunction(comptime P: type, comptime name: []const u8, comptime Expected: type) void {
    if (!@hasDecl(P, name)) @compileError(@typeName(P) ++ " missing " ++ name);
    if (@TypeOf(@field(P, name)) != Expected)
        @compileError(@typeName(P) ++ " has wrong " ++ name ++ " signature");
}

fn validateProcessor(comptime P: type) void {
    if (!@hasDecl(P, "descriptor")) @compileError(@typeName(P) ++ " missing descriptor");
    if (@TypeOf(P.descriptor) != processor.ProcessorDescriptor)
        @compileError(@typeName(P) ++ " descriptor has wrong type");
    if (!@hasDecl(P, "Prepared")) @compileError(@typeName(P) ++ " missing Prepared");
    if (!@hasDecl(P, "Worker")) @compileError(@typeName(P) ++ " missing Worker");

    const descriptor = P.descriptor;
    if (descriptor.id.raw() == 0) @compileError(@typeName(P) ++ " has invalid processor id");
    if (descriptor.api != processor.api_version) @compileError(@typeName(P) ++ " processor API mismatch");
    if (descriptor.requires_artifact != (descriptor.artifact_content_type != null))
        @compileError(@typeName(P) ++ " artifact requirement is inconsistent");
    const declares_metadata = descriptor.metadata_inputs.list.len != 0 or
        descriptor.metadata_outputs.list.len != 0;
    if (declares_metadata != descriptor.resource_categories.metadata_scratch)
        @compileError(@typeName(P) ++ " metadata/resource declaration mismatch");
    if (descriptor.work.maximum_total == 0 or
        descriptor.work.fixed_per_batch > descriptor.work.maximum_total or
        descriptor.work.per_active_packet > descriptor.work.maximum_total)
        @compileError(@typeName(P) ++ " invalid bounded-work declaration");
    const maximum_declared_work = processor.checkedAdd(
        descriptor.work.fixed_per_batch,
        processor.checkedMul(descriptor.work.per_active_packet, packet.max_batch) catch
            @compileError(@typeName(P) ++ " bounded-work overflow"),
    ) catch @compileError(@typeName(P) ++ " bounded-work overflow");
    if (maximum_declared_work > descriptor.work.maximum_total)
        @compileError(@typeName(P) ++ " bounded-work formula exceeds maximum_total");

    inline for (descriptor.outputs, 0..) |output, index| {
        if (output.raw() == 0) @compileError(@typeName(P) ++ " invalid output id");
        inline for (descriptor.outputs[0..index]) |earlier| if (earlier.raw() == output.raw())
            @compileError(@typeName(P) ++ " duplicate output id");
    }
    const stateful = descriptor.services.worker_state;
    if (stateful != (P.Worker != void))
        @compileError(@typeName(P) ++ " worker state/flag mismatch");
    if (stateful != descriptor.update_modes.any())
        @compileError(@typeName(P) ++ " state/update-mode mismatch");
    if (stateful) {
        if (descriptor.default_update_mode == .none)
            @compileError(@typeName(P) ++ " stateful processor missing default update mode");
        const supported = switch (descriptor.default_update_mode) {
            .none => false,
            .flush => descriptor.update_modes.flush,
            .retain_compatible => descriptor.update_modes.retain_compatible,
            .lazy_reevaluate => descriptor.update_modes.lazy_reevaluate,
            .eager_reevaluate => descriptor.update_modes.eager_reevaluate,
            .processor_migration => descriptor.update_modes.processor_migration,
        };
        if (!supported) @compileError(@typeName(P) ++ " unsupported stateful default update mode");
    } else if (descriptor.default_update_mode != .none) {
        @compileError(@typeName(P) ++ " stateless processor declares update default");
    }

    switch (descriptor.error_policy) {
        .infallible => if (descriptor.process_error_mode != .infallible)
            @compileError(@typeName(P) ++ " infallible policy/result mismatch"),
        .continue_active => if (descriptor.process_error_mode != .bounded)
            @compileError(@typeName(P) ++ " bounded error policy/result mismatch"),
        .terminal_active => |terminal| {
            if (descriptor.process_error_mode != .bounded)
                @compileError(@typeName(P) ++ " terminal error policy/result mismatch");
            validateTerminalPolicy(descriptor, terminal);
        },
        .terminal_active_and_stop => |terminal| {
            if (descriptor.process_error_mode != .bounded)
                @compileError(@typeName(P) ++ " stop error policy/result mismatch");
            validateTerminalPolicy(descriptor, terminal);
        },
    }

    exactFunction(P, "estimateResources", fn (?processor.ConfigurationArtifact, usize) processor.EstimateError!processor.ResourceEstimate);
    exactFunction(P, "prepare", fn (std.mem.Allocator, ?processor.ConfigurationArtifact) processor.PreparationError!P.Prepared);
    exactFunction(P, "instantiate", fn (std.mem.Allocator, *const P.Prepared, processor.WorkerDescriptor) processor.InstantiationError!P.Worker);
    exactFunction(P, "deinitWorker", fn (*P.Worker, std.mem.Allocator) void);
    exactFunction(P, "deinitPrepared", fn (*P.Prepared, std.mem.Allocator) void);
    const Context = processor.ProcessContext(descriptor);
    if (descriptor.process_error_mode == .infallible) {
        exactFunction(P, "processBatch", fn (*P.Worker, Context) processor.ProcessResult);
    } else {
        exactFunction(P, "processBatch", fn (*P.Worker, Context) processor.ProcessError!processor.ProcessResult);
    }
}

fn validateProcessors(comptime ProcessorTypes: anytype, comptime InputMetadataKeys: anytype) void {
    inline for (ProcessorTypes, 0..) |P, index| {
        validateProcessor(P);
        inline for (ProcessorTypes, 0..) |Earlier, earlier_index| {
            if (earlier_index < index and Earlier.descriptor.id.raw() == P.descriptor.id.raw())
                @compileError("duplicate processor id");
        }
    }
    validateMetadata(ProcessorTypes, InputMetadataKeys);
    validateSchemas(ProcessorTypes);
    const AllKeys = allMetadataKeys(ProcessorTypes, InputMetadataKeys);
    if (AllKeys.list.len > processor.MetadataStore.max_keys)
        @compileError("pipeline exceeds fixed metadata key capacity");
}

fn outputAvailable(capabilities: processor.ApplicationCapabilities, output: packet.OutputId) bool {
    for (capabilities.available_outputs) |candidate|
        if (candidate.raw() == output.raw()) return true;
    return false;
}

fn metricAvailable(capabilities: processor.ApplicationCapabilities, id: processor.MetricId) bool {
    for (capabilities.available_metrics) |candidate| if (candidate.raw() == id.raw()) return true;
    return false;
}

fn eventAvailable(capabilities: processor.ApplicationCapabilities, id: processor.EventId) bool {
    for (capabilities.available_events) |candidate| if (candidate.raw() == id.raw()) return true;
    return false;
}

fn validateApplicationOutputs(capabilities: processor.ApplicationCapabilities) PipelineError!void {
    if (capabilities.available_outputs.len > packet.DispositionGroups.max_outputs)
        return error.CapabilityUnavailable;
    for (capabilities.available_outputs, 0..) |output, index| {
        if (output.raw() == 0) return error.CapabilityUnavailable;
        for (capabilities.available_outputs[0..index]) |earlier|
            if (earlier.raw() == output.raw()) return error.CapabilityUnavailable;
    }
}

fn validateCapabilities(comptime ProcessorTypes: anytype, capabilities: processor.ApplicationCapabilities) PipelineError!void {
    try validateApplicationOutputs(capabilities);
    inline for (ProcessorTypes) |P| {
        const descriptor = P.descriptor;
        if (@intFromEnum(descriptor.packet_access) > @intFromEnum(capabilities.packet_access))
            return error.CapabilityUnavailable;
        if (descriptor.packet_access == .trusted_raw_edit and !capabilities.trusted_raw_edit_opt_in)
            return error.CapabilityUnavailable;
        if (descriptor.services.monotonic_time and !capabilities.monotonic_time)
            return error.CapabilityUnavailable;
        if (descriptor.services.reusable_state and !capabilities.reusable_state)
            return error.CapabilityUnavailable;
        if ((descriptor.dispositions.accept and !capabilities.dispositions.accept) or
            (descriptor.dispositions.drop and !capabilities.dispositions.drop) or
            (descriptor.dispositions.redirect and !capabilities.dispositions.redirect) or
            (descriptor.dispositions.complete and !capabilities.dispositions.complete) or
            descriptor.dispositions.retain)
            return error.CapabilityUnavailable;
        for (descriptor.outputs) |output| if (!outputAvailable(capabilities, output))
            return error.CapabilityUnavailable;
        inline for (descriptor.metrics.list) |Metric|
            if (!metricAvailable(capabilities, Metric.id)) return error.CapabilityUnavailable;
        inline for (descriptor.events.list) |Event|
            if (!eventAvailable(capabilities, Event.id)) return error.CapabilityUnavailable;
    }
}

fn effectiveCapabilities(
    comptime descriptor: processor.ProcessorDescriptor,
    capabilities: processor.ApplicationCapabilities,
) internal_invocation.EffectiveCapabilities {
    comptime std.debug.assert(processor.MetadataStore.max_keys == internal_invocation.max_metadata_rights);
    var effective: internal_invocation.EffectiveCapabilities = .{
        .packet_access = @min(
            @intFromEnum(descriptor.packet_access),
            @intFromEnum(capabilities.packet_access),
        ),
        .dispositions = @as(u8, @bitCast(descriptor.dispositions)) &
            @as(u8, @bitCast(capabilities.dispositions)),
        .trusted_raw_edit = descriptor.packet_access == .trusted_raw_edit and
            capabilities.trusted_raw_edit_opt_in,
        .monotonic_time = descriptor.services.monotonic_time and
            capabilities.monotonic_time,
        .outputs = undefined,
        .output_count = descriptor.outputs.len,
        .metadata_inputs = undefined,
        .metadata_input_count = descriptor.metadata_inputs.list.len,
        .metadata_outputs = undefined,
        .metadata_output_count = descriptor.metadata_outputs.list.len,
    };
    inline for (descriptor.outputs, 0..) |output, index|
        effective.outputs[index] = output;
    inline for (descriptor.metadata_inputs.list, 0..) |Key, index|
        effective.metadata_inputs[index] = internal_invocation.metadataIdentity(Key);
    inline for (descriptor.metadata_outputs.list, 0..) |Key, index|
        effective.metadata_outputs[index] = internal_invocation.metadataIdentity(Key);
    return effective;
}

fn terminalPacketDisposition(terminal: processor.TerminalDisposition) packet.PacketDisposition {
    return switch (terminal) {
        .accept => |output| .{ .Accept = output },
        .drop => |reason| .{ .Drop = reason },
        .redirect => |redirect| .{ .Redirect = .{
            .output = redirect.output,
            .metadata = redirect.metadata,
        } },
        .complete => |id| .{ .Complete = id },
    };
}

/// Generates a complete M3 pipeline for the ordered processor tuple with no
/// application-supplied typed metadata.
pub fn Pipeline(comptime ProcessorTypes: anytype) type {
    return PipelineWithInputMetadata(ProcessorTypes, processor.MetadataKeys(.{}));
}

/// Generates a complete M3 pipeline with a fixed typed input-metadata key set.
/// Zig 0.16 has no default function parameters, so this separately named form
/// represents the architecture's optional second compile-time tuple.
pub fn PipelineWithInputMetadata(
    comptime ProcessorTypes: anytype,
    comptime InputMetadataKeySet: type,
) type {
    const InputMetadataKeys = InputMetadataKeySet.list;
    comptime validateProcessors(ProcessorTypes, InputMetadataKeys);

    const PreparedTuple = TupleFor(ProcessorTypes, .prepared);
    const WorkerTuple = TupleFor(ProcessorTypes, .worker);
    const AllKeys = allMetadataKeys(ProcessorTypes, InputMetadataKeys);
    const processor_count = ProcessorTypes.len;

    return struct {
        const Self = @This();

        /// Ordered processor types used to generate this pipeline.
        pub const processors = ProcessorTypes;
        /// Fixed complete metadata layout.
        pub const metadata_keys = AllKeys.list;

        /// Typed caller-owned input metadata. Only declared pipeline input keys
        /// may be written.
        pub const InputMetadata = struct {
            store: processor.MetadataStore = .{},

            /// Initializes fixed validity for one actual batch length.
            pub fn init(batch_len: usize) PipelineError!InputMetadata {
                var result = InputMetadata{};
                result.store.reset(AllKeys.list, batch_len) catch return error.MetadataFailure;
                return result;
            }

            /// Stores a typed input value for one packet.
            pub fn put(self: *InputMetadata, comptime Key: type, index: usize, value: Key.Value) PipelineError!void {
                comptime if (keyIndex(InputMetadataKeys, Key) == null)
                    @compileError("metadata key is not a declared pipeline input");
                self.store.put(Key, index, value) catch return error.MetadataFailure;
            }

            /// Returns fixed logical scratch accounting for the complete layout.
            pub fn scratchBytes() usize {
                return processor.metadataScratchBytes(AllKeys.list) catch unreachable;
            }
        };

        /// Prepared processor tuple, address-stable counted allocator, and exact
        /// construction prefix.
        pub const PreparedPipeline = struct {
            const WorkerSlot = struct {
                generation: u64 = 0,
                worker: ?*WorkerPipeline = null,
            };

            allocator: std.mem.Allocator,
            owner_identity: u64,
            budgets: [processor_count]processor.BudgetAllocator = undefined,
            values: PreparedTuple = undefined,
            initialized: usize = 0,
            estimates: [processor_count]processor.ResourceEstimate,
            aggregate: AggregateEstimate,
            installed_capabilities: [processor_count]internal_invocation.EffectiveCapabilities,
            application_outputs: [packet.DispositionGroups.max_outputs]packet.OutputId = undefined,
            application_output_count: usize,
            worker_capacity: usize,
            live_workers: usize = 0,
            worker_slots: []WorkerSlot,

            /// Destroys prepared parts only after every checked worker handle
            /// has been invalidated.
            pub fn deinit(self: *PreparedPipeline) PipelineError!void {
                if (self.live_workers != 0) return error.WorkersStillLive;
                inline for (0..processor_count) |reverse_offset| {
                    const index = processor_count - 1 - reverse_offset;
                    if (self.initialized > index) {
                        self.budgets[index].beginCleanup();
                        ProcessorTypes[index].deinitPrepared(
                            &self.values[index],
                            self.budgets[index].allocator(),
                        );
                        self.budgets[index].endCleanup();
                        std.debug.assert(self.budgets[index].current == 0);
                    }
                }
                const allocator = self.allocator;
                allocator.free(self.worker_slots);
                allocator.destroy(self);
            }

            /// Returns the sum of per-stage prepared allocation peaks.
            pub fn peakBytes(self: *const PreparedPipeline) usize {
                var total: usize = 0;
                for (self.budgets) |budget| total += budget.peak;
                return total;
            }

            fn resolveWorker(
                self: *PreparedPipeline,
                handle: WorkerHandle,
            ) PipelineError!*WorkerPipeline {
                if (handle.owner_identity == 0 or handle.owner_identity != self.owner_identity)
                    return error.WrongWorkerOwner;
                if (handle.generation == 0 or handle.slot >= self.worker_capacity)
                    return error.StaleWorker;
                if (self.worker_slots[handle.slot].generation != handle.generation)
                    return error.StaleWorker;
                const worker = self.worker_slots[handle.slot].worker orelse
                    return error.StaleWorker;
                if (worker.prepared != self or worker.slot != handle.slot or
                    worker.generation != handle.generation)
                    return error.StaleWorker;
                return worker;
            }

            fn applicationOutputAvailable(
                self: *const PreparedPipeline,
                output: packet.OutputId,
            ) bool {
                for (self.application_outputs[0..self.application_output_count]) |candidate|
                    if (candidate.raw() == output.raw()) return true;
                return false;
            }

            fn validateDispositionConfig(
                self: *const PreparedPipeline,
                config: packet.DispositionConfig,
            ) PipelineError!void {
                config.validate() catch return error.DispositionFailure;
                for (config.outputs) |output|
                    if (!self.applicationOutputAvailable(output))
                        return error.DispositionFailure;
                inline for (ProcessorTypes) |P| {
                    inline for (P.descriptor.outputs) |output|
                        if (!config.containsOutput(output))
                            return error.DispositionFailure;
                    if (P.descriptor.dispositions.accept and config.default_output == null)
                        return error.DispositionFailure;
                }
            }

            /// Returns the sum of per-stage worker allocation peaks after
            /// authenticating a pointer-free handle against this live owner.
            pub fn workerPeakBytes(
                self: *PreparedPipeline,
                handle: WorkerHandle,
            ) PipelineError!usize {
                const worker = try self.resolveWorker(handle);
                var total: usize = 0;
                for (worker.budgets) |budget| total += budget.peak;
                return total;
            }

            /// Returns construction allocation calls after authenticating the
            /// handle against this live owner.
            pub fn workerAllocationCount(
                self: *PreparedPipeline,
                handle: WorkerHandle,
            ) PipelineError!usize {
                const worker = try self.resolveWorker(handle);
                var total: usize = 0;
                for (worker.budgets) |budget| total += budget.allocations;
                return total;
            }

            /// Invalidates the owner slot before releasing worker storage.
            pub fn deinitWorker(
                self: *PreparedPipeline,
                handle: *WorkerHandle,
            ) PipelineError!void {
                const worker = try self.resolveWorker(handle.*);
                self.worker_slots[handle.slot].worker = null;
                std.debug.assert(self.live_workers != 0);
                self.live_workers -= 1;
                worker.destroyOwned();
                handle.generation = 0;
            }

            /// Executes through an explicitly live owner and a pointer-free,
            /// generation-checked worker handle. Invalid disposition routing
            /// rejects before callbacks. Any returned error after a callback
            /// invalidates the supplied batch generation and all derived
            /// packet/view/output handles; token reconciliation stays with the
            /// caller.
            pub fn processBatch(
                self: *PreparedPipeline,
                handle: WorkerHandle,
                owner: *packet.PacketBatchOwner,
                batch: packet.PacketBatch,
                input_metadata: InputMetadata,
                disposition_config: packet.DispositionConfig,
                monotonic_time_ns: u64,
            ) PipelineError!WorkerPipeline.ExecutionResult {
                return (try self.resolveWorker(handle)).processBatchOwned(
                    owner,
                    batch,
                    input_metadata,
                    disposition_config,
                    monotonic_time_ns,
                );
            }
        };

        /// Worker-local direct-call tuple and fixed batch metadata.
        pub const WorkerPipeline = struct {
            allocator: std.mem.Allocator,
            budgets: [processor_count]processor.BudgetAllocator = undefined,
            prepared: *PreparedPipeline,
            slot: usize,
            generation: u64,
            values: WorkerTuple = undefined,
            initialized: usize = 0,
            metadata: processor.MetadataStore = .{},

            fn destroyOwned(self: *WorkerPipeline) void {
                inline for (0..processor_count) |reverse_offset| {
                    const index = processor_count - 1 - reverse_offset;
                    if (self.initialized > index) {
                        self.budgets[index].beginCleanup();
                        ProcessorTypes[index].deinitWorker(
                            &self.values[index],
                            self.budgets[index].allocator(),
                        );
                        self.budgets[index].endCleanup();
                        std.debug.assert(self.budgets[index].current == 0);
                    }
                }
                const allocator = self.allocator;
                allocator.destroy(self);
            }

            /// Bounded per-stage trace plus final receive-ordered groups.
            pub const ExecutionResult = struct {
                dispositions: packet.DispositionGroups,
                final_dispositions: [packet.max_batch]packet.PacketDisposition,
                packet_count: usize,
                stage_status: [processor_count]StageStatus,
                stage_errors: [processor_count]?processor.ProcessError,
                request_stop: bool,
            };

            fn applyFailure(
                writer: packet.DispositionWriter,
                owner: *packet.PacketBatchOwner,
                comptime descriptor: processor.ProcessorDescriptor,
            ) PipelineError!StageStatus {
                const active = writer.activeSelection(owner) catch return error.DispositionFailure;
                return switch (descriptor.error_policy) {
                    .infallible => error.DispositionFailure,
                    .continue_active => .failed_continue,
                    .terminal_active => |terminal| blk: {
                        if (!active.isEmpty()) writer.setSelection(
                            owner,
                            active,
                            terminalPacketDisposition(terminal),
                        ) catch return error.DispositionFailure;
                        break :blk .failed_terminal;
                    },
                    .terminal_active_and_stop => |terminal| blk: {
                        if (!active.isEmpty()) writer.setSelection(
                            owner,
                            active,
                            terminalPacketDisposition(terminal),
                        ) catch return error.DispositionFailure;
                        break :blk .failed_stop;
                    },
                };
            }

            /// Executes one direct call per non-empty stage, never allocates,
            /// and resolves leftover Continue only through caller policy.
            fn processBatchOwned(
                self: *WorkerPipeline,
                owner: *packet.PacketBatchOwner,
                batch: packet.PacketBatch,
                input_metadata: InputMetadata,
                disposition_config: packet.DispositionConfig,
                monotonic_time_ns: u64,
            ) PipelineError!ExecutionResult {
                const batch_len = batch.len(owner) catch return error.BatchFailure;
                if (input_metadata.store.batch_len != batch_len) return error.MetadataFailure;
                try self.prepared.validateDispositionConfig(disposition_config);
                batch.requireRevocable(owner) catch return error.BatchFailure;
                self.metadata = input_metadata.store;
                const writer = packet.DispositionWriter.init(batch, owner) catch
                    return error.DispositionFailure;
                var callback_started = false;
                errdefer if (callback_started) batch.invalidate(owner) catch unreachable;
                var statuses = [_]StageStatus{.not_run} ** processor_count;
                var errors = [_]?processor.ProcessError{null} ** processor_count;
                var stopped = false;
                var exhausted = false;

                inline for (ProcessorTypes, 0..) |P, stage_index| {
                    if (!stopped and !exhausted) {
                        const active_before = writer.activeSelection(owner) catch
                            return error.DispositionFailure;
                        if (active_before.isEmpty()) {
                            statuses[stage_index] = .skipped_empty;
                            exhausted = true;
                        } else {
                            var successful: ?processor.ProcessResult = null;
                            var process_error: ?processor.ProcessError = null;
                            const Context = processor.ProcessContext(P.descriptor);
                            const cookie = internal_invocation.begin(
                                Context,
                                owner,
                                batch,
                                writer,
                                &self.metadata,
                                self.prepared.installed_capabilities[stage_index],
                                monotonic_time_ns,
                            ) catch return error.InvocationFailure;
                            const context: Context = @enumFromInt(cookie);
                            callback_started = true;
                            if (P.descriptor.process_error_mode == .infallible) {
                                successful = P.processBatch(&self.values[stage_index], context);
                            } else {
                                successful = P.processBatch(&self.values[stage_index], context) catch |err| blk: {
                                    process_error = err;
                                    break :blk null;
                                };
                            }
                            internal_invocation.end(cookie) catch return error.InvocationFailure;

                            if (successful) |result| {
                                const computed_work = processor.checkedAdd(
                                    P.descriptor.work.fixed_per_batch,
                                    processor.checkedMul(
                                        P.descriptor.work.per_active_packet,
                                        active_before.count(),
                                    ) catch return error.ResourceOverflow,
                                ) catch return error.ResourceOverflow;
                                if (result.visited_packets > active_before.count() or
                                    result.work_units > computed_work or
                                    result.work_units > P.descriptor.work.maximum_total or
                                    result.work_units > self.prepared.estimates[stage_index].maximum_batch_work)
                                {
                                    return error.WorkContractViolation;
                                } else {
                                    statuses[stage_index] = .ok;
                                }
                            } else {
                                errors[stage_index] = process_error.?;
                                statuses[stage_index] = try applyFailure(writer, owner, P.descriptor);
                                if (statuses[stage_index] == .failed_stop) stopped = true;
                            }
                        }
                    }
                }

                const groups = packet.DispositionGroups.resolve(
                    writer,
                    owner,
                    disposition_config,
                ) catch return error.DispositionFailure;
                var final_dispositions = [_]packet.PacketDisposition{.Continue} ** packet.max_batch;
                for (0..batch_len) |index| {
                    const recorded = writer.get(owner, index) catch return error.DispositionFailure;
                    final_dispositions[index] = switch (recorded) {
                        .Continue => switch (disposition_config.continue_policy) {
                            .accept => |output| .{ .Accept = output },
                            .drop => |reason| .{ .Drop = reason },
                            .complete => |id| .{ .Complete = id },
                        },
                        else => recorded,
                    };
                }
                return .{
                    .dispositions = groups,
                    .final_dispositions = final_dispositions,
                    .packet_count = batch_len,
                    .stage_status = statuses,
                    .stage_errors = errors,
                    .request_stop = stopped,
                };
            }
        };

        /// Copyable pointer-free worker authority. It carries only owner
        /// identity, slot index, and generation; every operation requires an
        /// explicitly live `PreparedPipeline` owner.
        pub const WorkerHandle = struct {
            owner_identity: u64,
            slot: usize,
            generation: u64,
        };

        /// Returns exact generated prepared-wrapper plus owner-registry bytes
        /// for the configured worker count.
        pub fn frameworkPreparedBytes(worker_count: usize) PipelineError!usize {
            return processor.checkedAdd(
                @sizeOf(PreparedPipeline),
                processor.checkedMul(
                    @sizeOf(PreparedPipeline.WorkerSlot),
                    worker_count,
                ) catch return error.ResourceOverflow,
            ) catch return error.ResourceOverflow;
        }

        /// Returns exact generated worker-wrapper bytes per live worker.
        pub fn frameworkWorkerBytesEach() usize {
            return @sizeOf(WorkerPipeline);
        }

        /// Performs all capability, estimate, checked aggregation, metadata,
        /// and application-limit validation before the first prepare call.
        pub fn prepare(
            allocator: std.mem.Allocator,
            artifacts: [processor_count]?processor.ConfigurationArtifact,
            capabilities: processor.ApplicationCapabilities,
            limits: processor.ResourceLimits,
        ) PipelineError!*PreparedPipeline {
            try validateCapabilities(ProcessorTypes, capabilities);
            if (limits.worker_count == 0) return error.InvalidResourceLimits;

            var estimates: [processor_count]processor.ResourceEstimate = undefined;
            var installed_capabilities: [processor_count]internal_invocation.EffectiveCapabilities = undefined;
            var processor_prepared_total: usize = 0;
            var processor_worker_each: usize = 0;
            var pool_each: usize = 0;
            var work_total: usize = 0;
            inline for (ProcessorTypes, 0..) |P, index| {
                const artifact = artifacts[index];
                if (P.descriptor.requires_artifact) {
                    const supplied = artifact orelse return error.PreparationFailed;
                    if (supplied.content_type.raw() != P.descriptor.artifact_content_type.?.raw())
                        return error.PreparationFailed;
                } else if (artifact != null) return error.PreparationFailed;

                const estimate = P.estimateResources(artifact, limits.worker_count) catch
                    return error.EstimateFailed;
                const declared_worst = processor.checkedAdd(
                    P.descriptor.work.fixed_per_batch,
                    processor.checkedMul(P.descriptor.work.per_active_packet, packet.max_batch) catch
                        return error.ResourceOverflow,
                ) catch return error.ResourceOverflow;
                if (estimate.maximum_batch_work < declared_worst or
                    estimate.maximum_batch_work > P.descriptor.work.maximum_total)
                    return error.ResourceLimitExceeded;
                if ((estimate.prepared_bytes != 0) != P.descriptor.resource_categories.prepared_memory or
                    (estimate.worker_bytes != 0) != P.descriptor.resource_categories.worker_memory or
                    (estimate.bounded_pool_bytes_per_worker != 0) != P.descriptor.resource_categories.bounded_pool)
                    return error.ResourceLimitExceeded;
                estimates[index] = estimate;
                installed_capabilities[index] = effectiveCapabilities(P.descriptor, capabilities);
                processor_prepared_total = processor.checkedAdd(processor_prepared_total, estimate.prepared_bytes) catch
                    return error.ResourceOverflow;
                processor_worker_each = processor.checkedAdd(processor_worker_each, estimate.worker_bytes) catch
                    return error.ResourceOverflow;
                pool_each = processor.checkedAdd(pool_each, estimate.bounded_pool_bytes_per_worker) catch
                    return error.ResourceOverflow;
                work_total = processor.checkedAdd(work_total, estimate.maximum_batch_work) catch
                    return error.ResourceOverflow;
            }

            const framework_prepared = try frameworkPreparedBytes(limits.worker_count);
            const framework_worker_each = frameworkWorkerBytesEach();
            const prepared_total = processor.checkedAdd(
                framework_prepared,
                processor_prepared_total,
            ) catch return error.ResourceOverflow;
            const worker_each = processor.checkedAdd(
                framework_worker_each,
                processor_worker_each,
            ) catch return error.ResourceOverflow;
            const metadata_each = processor.metadataScratchBytes(AllKeys.list) catch
                return error.ResourceOverflow;
            const worker_total = processor.checkedMul(worker_each, limits.worker_count) catch
                return error.ResourceOverflow;
            const metadata_total = processor.checkedMul(metadata_each, limits.worker_count) catch
                return error.ResourceOverflow;
            const pool_total = processor.checkedMul(pool_each, limits.worker_count) catch
                return error.ResourceOverflow;
            const aggregate = AggregateEstimate{
                .processor_prepared_bytes = processor_prepared_total,
                .framework_prepared_bytes = framework_prepared,
                .prepared_bytes = prepared_total,
                .processor_worker_bytes_each = processor_worker_each,
                .framework_worker_bytes_each = framework_worker_each,
                .worker_bytes_each = worker_each,
                .worker_bytes_total = worker_total,
                .metadata_scratch_bytes_each = metadata_each,
                .metadata_scratch_bytes_total = metadata_total,
                .bounded_pool_bytes_each = pool_each,
                .bounded_pool_bytes_total = pool_total,
                .maximum_batch_work = work_total,
            };
            if (prepared_total > limits.prepared_bytes or
                worker_each > limits.worker_bytes_each or
                worker_total > limits.worker_bytes_total or
                metadata_each > limits.metadata_scratch_bytes_each or
                metadata_total > limits.metadata_scratch_bytes_total or
                pool_each > limits.bounded_pool_bytes_each or
                pool_total > limits.bounded_pool_bytes_total or
                work_total > limits.maximum_batch_work)
                return error.ResourceLimitExceeded;

            const prepared = allocator.create(PreparedPipeline) catch return error.OutOfMemory;
            errdefer allocator.destroy(prepared);
            const worker_slots = allocator.alloc(
                PreparedPipeline.WorkerSlot,
                limits.worker_count,
            ) catch return error.OutOfMemory;
            errdefer allocator.free(worker_slots);
            @memset(worker_slots, .{});
            prepared.* = .{
                .allocator = allocator,
                .owner_identity = try nextPreparedIdentity(),
                .estimates = estimates,
                .aggregate = aggregate,
                .installed_capabilities = installed_capabilities,
                .application_output_count = capabilities.available_outputs.len,
                .worker_capacity = limits.worker_count,
                .worker_slots = worker_slots,
            };
            @memcpy(
                prepared.application_outputs[0..capabilities.available_outputs.len],
                capabilities.available_outputs,
            );
            inline for (0..processor_count) |index|
                prepared.budgets[index] = processor.BudgetAllocator.init(
                    allocator,
                    estimates[index].prepared_bytes,
                );
            inline for (ProcessorTypes, 0..) |P, index| {
                const denied_before = prepared.budgets[index].denied;
                prepared.values[index] = P.prepare(
                    prepared.budgets[index].allocator(),
                    artifacts[index],
                ) catch |err| {
                    inline for (0..index) |reverse_offset| {
                        const cleanup_index = index - 1 - reverse_offset;
                        prepared.budgets[cleanup_index].beginCleanup();
                        ProcessorTypes[cleanup_index].deinitPrepared(
                            &prepared.values[cleanup_index],
                            prepared.budgets[cleanup_index].allocator(),
                        );
                        prepared.budgets[cleanup_index].endCleanup();
                        std.debug.assert(prepared.budgets[cleanup_index].current == 0);
                    }
                    if (prepared.budgets[index].current != 0 or
                        prepared.budgets[index].denied != denied_before or
                        err == error.ResourceUnderestimated)
                        return error.ResourceUnderestimated;
                    return error.PreparationFailed;
                };
                prepared.budgets[index].seal();
                prepared.initialized += 1;
            }
            return prepared;
        }

        /// Constructs one worker tuple in order with counted allocation and
        /// exact reverse cleanup on every partial failure.
        pub fn instantiate(
            prepared: *PreparedPipeline,
            descriptor: processor.WorkerDescriptor,
        ) PipelineError!WorkerHandle {
            if (prepared.live_workers >= prepared.worker_capacity)
                return error.WorkerCapacityExceeded;
            var slot: usize = 0;
            while (slot < prepared.worker_capacity and prepared.worker_slots[slot].worker != null) : (slot += 1) {}
            if (slot == prepared.worker_capacity) return error.WorkerCapacityExceeded;
            const generation = std.math.add(u64, prepared.worker_slots[slot].generation, 1) catch
                return error.StaleWorker;
            const allocator = prepared.allocator;
            const worker = allocator.create(WorkerPipeline) catch return error.OutOfMemory;
            worker.* = .{
                .allocator = allocator,
                .prepared = prepared,
                .slot = slot,
                .generation = generation,
            };
            errdefer allocator.destroy(worker);
            inline for (0..processor_count) |index|
                worker.budgets[index] = processor.BudgetAllocator.init(
                    allocator,
                    prepared.estimates[index].worker_bytes,
                );
            inline for (ProcessorTypes, 0..) |P, index| {
                const denied_before = worker.budgets[index].denied;
                worker.values[index] = P.instantiate(
                    worker.budgets[index].allocator(),
                    &prepared.values[index],
                    descriptor,
                ) catch |err| {
                    inline for (0..index) |reverse_offset| {
                        const cleanup_index = index - 1 - reverse_offset;
                        worker.budgets[cleanup_index].beginCleanup();
                        ProcessorTypes[cleanup_index].deinitWorker(
                            &worker.values[cleanup_index],
                            worker.budgets[cleanup_index].allocator(),
                        );
                        worker.budgets[cleanup_index].endCleanup();
                        std.debug.assert(worker.budgets[cleanup_index].current == 0);
                    }
                    if (worker.budgets[index].current != 0 or
                        worker.budgets[index].denied != denied_before or
                        err == error.ResourceUnderestimated)
                        return error.ResourceUnderestimated;
                    return error.InstantiationFailed;
                };
                worker.budgets[index].seal();
                worker.initialized += 1;
            }
            prepared.worker_slots[slot].generation = generation;
            prepared.worker_slots[slot].worker = worker;
            prepared.live_workers += 1;
            return .{
                .owner_identity = prepared.owner_identity,
                .slot = slot,
                .generation = generation,
            };
        }
    };
}

const TestNoop = struct {
    /// No prepared state is required by the validation fixture.
    pub const Prepared = void;
    /// No worker state is required by the validation fixture.
    pub const Worker = void;
    /// Minimal valid processor declaration for pipeline unit tests.
    pub const descriptor: processor.ProcessorDescriptor = .{
        .id = .init(1),
        .work = .{ .maximum_total = packet.max_batch },
    };
    /// Reports the fixture's bounded batch work.
    pub fn estimateResources(_: ?processor.ConfigurationArtifact, _: usize) processor.EstimateError!processor.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    /// Constructs the fixture's empty prepared state.
    pub fn prepare(_: std.mem.Allocator, _: ?processor.ConfigurationArtifact) processor.PreparationError!Prepared {}
    /// Constructs the fixture's empty worker state.
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: processor.WorkerDescriptor) processor.InstantiationError!Worker {}
    /// Observes one active batch without changing dispositions.
    pub fn processBatch(_: *Worker, context: processor.ProcessContext(descriptor)) processor.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    /// Cleans the fixture's empty worker state.
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    /// Cleans the fixture's empty prepared state.
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};

test "zero and one-stage pipeline types validate" {
    _ = Pipeline(.{});
    _ = Pipeline(.{TestNoop});
}

const CapabilityIsolationKey = struct {
    /// Stable test-only metadata key identity.
    pub const id: u32 = 0x4341_5001;
    /// Inline test-only metadata value.
    pub const Value = u16;
};

const capability_isolation_output = packet.OutputId.init(0x4341_5002);

const capability_isolation_narrow: processor.ProcessorDescriptor = .{
    .id = .init(0x4341_5003),
    .packet_access = .read,
    .metadata_outputs = processor.MetadataKeys(.{CapabilityIsolationKey}),
};

const capability_isolation_broad: processor.ProcessorDescriptor = .{
    .id = .init(0x4341_5004),
    .packet_access = .trusted_raw_edit,
    .dispositions = .{ .accept = true },
    .outputs = &.{capability_isolation_output},
    .metadata_inputs = processor.MetadataKeys(.{CapabilityIsolationKey}),
    .services = .{ .monotonic_time = true },
};

test "broad application authority installs exact isolated stage capabilities" {
    const application: processor.ApplicationCapabilities = .{
        .packet_access = .trusted_raw_edit,
        .trusted_raw_edit_opt_in = true,
        .available_outputs = &.{capability_isolation_output},
        .dispositions = .{ .accept = true, .drop = true },
        .monotonic_time = true,
    };

    const narrow_effective = effectiveCapabilities(capability_isolation_narrow, application);
    try std.testing.expectEqual(@intFromEnum(processor.PacketAccess.read), narrow_effective.packet_access);
    try std.testing.expectEqual(@as(u8, 0), narrow_effective.dispositions);
    try std.testing.expect(!narrow_effective.trusted_raw_edit);
    try std.testing.expect(!narrow_effective.monotonic_time);
    try std.testing.expectEqual(@as(usize, 0), narrow_effective.output_count);
    try std.testing.expectEqual(@as(usize, 0), narrow_effective.metadata_input_count);
    try std.testing.expectEqual(@as(usize, 1), narrow_effective.metadata_output_count);
    try std.testing.expectEqual(
        internal_invocation.metadataIdentity(CapabilityIsolationKey),
        narrow_effective.metadata_outputs[0],
    );

    const broad_effective = effectiveCapabilities(capability_isolation_broad, application);
    try std.testing.expectEqual(@intFromEnum(processor.PacketAccess.trusted_raw_edit), broad_effective.packet_access);
    try std.testing.expectEqual(
        @as(u8, @bitCast(capability_isolation_broad.dispositions)),
        broad_effective.dispositions,
    );
    try std.testing.expect(broad_effective.trusted_raw_edit);
    try std.testing.expect(broad_effective.monotonic_time);
    try std.testing.expectEqual(@as(usize, 1), broad_effective.output_count);
    try std.testing.expectEqual(capability_isolation_output.raw(), broad_effective.outputs[0].raw());
    try std.testing.expectEqual(@as(usize, 1), broad_effective.metadata_input_count);
    try std.testing.expectEqual(
        internal_invocation.metadataIdentity(CapabilityIsolationKey),
        broad_effective.metadata_inputs[0],
    );
    try std.testing.expectEqual(@as(usize, 0), broad_effective.metadata_output_count);
}

test "one-stage direct pipeline prepares instantiates and resolves an empty batch" {
    const P = Pipeline(.{TestNoop});
    const limits = processor.ResourceLimits{
        .prepared_bytes = P.frameworkPreparedBytes(1) catch unreachable,
        .worker_bytes_each = P.frameworkWorkerBytesEach(),
        .worker_bytes_total = P.frameworkWorkerBytesEach(),
        .metadata_scratch_bytes_each = P.InputMetadata.scratchBytes(),
        .metadata_scratch_bytes_total = P.InputMetadata.scratchBytes(),
        .maximum_batch_work = packet.max_batch,
        .worker_count = 1,
    };
    const prepared = try P.prepare(std.testing.allocator, .{null}, .{}, limits);
    defer prepared.deinit() catch unreachable;
    var worker = try P.instantiate(prepared, .{ .id = 1 });
    defer prepared.deinitWorker(&worker) catch unreachable;

    const owner = try packet.PacketBatchOwner.init(std.testing.allocator);
    defer owner.deinit();
    const batch = try owner.begin(
        .{ .input_id = .init(1), .queue_id = .init(1) },
        &.{},
    );
    defer batch.invalidate(owner) catch {};
    const input = try P.InputMetadata.init(0);
    const result = try prepared.processBatch(worker, owner, batch, input, .{
        .outputs = &.{},
        .default_output = null,
        .continue_policy = .{ .drop = .init(1) },
    }, 0);
    try std.testing.expectEqual(StageStatus.skipped_empty, result.stage_status[0]);
    try std.testing.expectEqual(@as(usize, 0), result.dispositions.drop_count);
}
