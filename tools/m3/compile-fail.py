#!/usr/bin/env python3
"""Validate stable Zig 0.16 M3 processor-specific compile failures."""

from __future__ import annotations

import os
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]

PREFIX = r'''
const std = @import("std");
const saint = @import("saint_shield");
const p = saint.processor;
const packet = saint.packet;
const pipeline = saint.pipeline;

const Good = struct {
    pub const Prepared = void;
    pub const Worker = void;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(1),
        .work = .{ .maximum_total = packet.max_batch },
    };
    pub fn estimateResources(_: ?p.ConfigurationArtifact, _: usize) p.EstimateError!p.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker {}
    pub fn processBatch(_: *Worker, context: p.ProcessContext(descriptor)) p.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};
'''

GOOD_MEMBERS = r'''    pub const Prepared = void;
    pub const Worker = void;
    pub fn estimateResources(_: ?p.ConfigurationArtifact, _: usize) p.EstimateError!p.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker {}
    pub fn processBatch(_: *Worker, context: p.ProcessContext(descriptor)) p.ProcessResult {
        const active = context.active() catch unreachable;
        return .{ .visited_packets = @intCast(active.count()), .work_units = @intCast(active.count()) };
    }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
'''

CASES: dict[str, tuple[str, str]] = {
    "public-invocation-bridge-unavailable": (
        "test { _ = p.invokeProcessor; }",
        "has no member named 'invokeProcessor'",
    ),
    "public-capability-installation-unavailable": (
        "test { _ = p.InstalledCapabilities; }",
        "has no member named 'InstalledCapabilities'",
    ),
    "public-context-identity-unavailable": (
        "test { _ = p.ProcessContext(Good.descriptor).authority_binding; }",
        "has no member named 'authority_binding'",
    ),
    "missing-descriptor": (
        "const Bad = struct {}; comptime { _ = pipeline.Pipeline(.{Bad}); }",
        "missing descriptor",
    ),
    "missing-type": (
        r'''
const Bad = struct {
    pub const descriptor = Good.descriptor;
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "missing Prepared",
    ),
    "missing-function": (
        r'''
const Bad = struct {
    pub const Prepared = void; pub const Worker = void;
    pub const descriptor = Good.descriptor;
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "missing estimateResources",
    ),
    "duplicate-id": (
        "comptime { _ = pipeline.Pipeline(.{ Good, Good }); }",
        "duplicate processor id",
    ),
    "invalid-id": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{ .id = .init(0), .work = .{ .maximum_total = packet.max_batch } };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "invalid processor id",
    ),
    "api-mismatch": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{ .id = .init(2), .api = 99, .work = .{ .maximum_total = packet.max_batch } };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "processor API mismatch",
    ),
    "wrong-signature": (
        r'''
const Bad = struct {
    pub const Prepared = void; pub const Worker = void;
    pub const descriptor: p.ProcessorDescriptor = .{ .id = .init(2), .work = .{ .maximum_total = packet.max_batch } };
    pub fn estimateResources(_: ?p.ConfigurationArtifact) p.EstimateError!p.ResourceEstimate { return .{}; }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker {}
    pub fn processBatch(_: *Worker, _: p.ProcessContext(descriptor)) p.ProcessResult { return .{}; }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "wrong estimateResources signature",
    ),
    "result-policy-mismatch": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .work = .{ .maximum_total = packet.max_batch },
        .process_error_mode = .bounded, .error_policy = .infallible,
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "infallible policy/result mismatch",
    ),
    "state-cleanup-mismatch": (
        r'''
const Bad = struct {
    pub const Prepared = void;
    pub const Worker = struct { value: u8 };
    pub const descriptor: p.ProcessorDescriptor = .{ .id = .init(2), .work = .{ .maximum_total = packet.max_batch } };
    pub fn estimateResources(_: ?p.ConfigurationArtifact, _: usize) p.EstimateError!p.ResourceEstimate { return .{ .maximum_batch_work = packet.max_batch }; }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker { return .{ .value = 0 }; }
    pub fn processBatch(_: *Worker, _: p.ProcessContext(descriptor)) p.ProcessResult { return .{}; }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "worker state/flag mismatch",
    ),
    "invalid-work": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{ .id = .init(2), .work = .{ .maximum_total = 0 } };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "invalid bounded-work declaration",
    ),
    "work-formula-exceeds-maximum": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2),
        .work = .{ .fixed_per_batch = 1, .per_active_packet = 1, .maximum_total = packet.max_batch },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "bounded-work formula exceeds maximum_total",
    ),
    "invalid-resource": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = u8; };
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .metadata_outputs = p.MetadataKeys(.{Key}),
        .work = .{ .maximum_total = packet.max_batch },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "metadata/resource declaration mismatch",
    ),
    "disposition-output-mismatch": (
        r'''
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .work = .{ .maximum_total = packet.max_batch },
        .process_error_mode = .bounded,
        .error_policy = .{ .terminal_active = .{ .drop = .init(1) } },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "error policy uses undeclared Drop",
    ),
    "invalid-update-mode": (
        r'''
const Bad = struct {
    pub const Prepared = void;
    pub const Worker = struct { value: u8 };
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .services = .{ .worker_state = true },
        .work = .{ .maximum_total = packet.max_batch },
        .update_modes = .{ .flush = true }, .default_update_mode = .retain_compatible,
    };
    pub fn estimateResources(_: ?p.ConfigurationArtifact, _: usize) p.EstimateError!p.ResourceEstimate { return .{ .maximum_batch_work = packet.max_batch }; }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker { return .{ .value = 0 }; }
    pub fn processBatch(_: *Worker, _: p.ProcessContext(descriptor)) p.ProcessResult { return .{}; }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "unsupported stateful default update mode",
    ),
    "metadata-duplicate": (
        r'''
const A = struct { pub const id: u32 = 1; pub const Value = u8; };
const B = struct { pub const id: u32 = 1; pub const Value = u8; };
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .metadata_outputs = p.MetadataKeys(.{ A, B }),
        .work = .{ .maximum_total = packet.max_batch }, .resource_categories = .{ .metadata_scratch = true },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "duplicate metadata producer in one stage",
    ),
    "metadata-type-conflict": (
        r'''
const A = struct { pub const id: u32 = 1; pub const Value = u8; };
const B = struct { pub const id: u32 = 1; pub const Value = u16; };
const First = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .metadata_outputs = p.MetadataKeys(.{A}),
        .work = .{ .maximum_total = packet.max_batch }, .resource_categories = .{ .metadata_scratch = true },
    };
};
const Second = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(3), .metadata_outputs = p.MetadataKeys(.{B}),
        .work = .{ .maximum_total = packet.max_batch }, .resource_categories = .{ .metadata_scratch = true },
    };
};
comptime { _ = pipeline.Pipeline(.{ First, Second }); }
''',
        "metadata producer type conflict",
    ),
    "metadata-consume-before-produce": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = u8; };
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .metadata_inputs = p.MetadataKeys(.{Key}),
        .work = .{ .maximum_total = packet.max_batch }, .resource_categories = .{ .metadata_scratch = true },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "metadata consumed before producer or typed pipeline input",
    ),
    "metadata-pointer-value": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = *const u8; };
comptime { _ = pipeline.PipelineWithInputMetadata(.{Good}, p.MetadataKeys(.{Key})); }
''',
        "metadata value must not contain pointer",
    ),
    "metadata-slice-value": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = []const u8; };
comptime { _ = pipeline.PipelineWithInputMetadata(.{Good}, p.MetadataKeys(.{Key})); }
''',
        "metadata value must not contain pointer",
    ),
    "metadata-function-value": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = fn () void; };
comptime { _ = pipeline.PipelineWithInputMetadata(.{Good}, p.MetadataKeys(.{Key})); }
''',
        "metadata value must not contain pointer, slice, function",
    ),
    "metadata-nested-pointer-value": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = struct { nested: ?*u8 }; };
comptime { _ = pipeline.PipelineWithInputMetadata(.{Good}, p.MetadataKeys(.{Key})); }
''',
        "metadata value must not contain pointer",
    ),
    "metadata-allocator-value": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = std.mem.Allocator; };
comptime { _ = pipeline.PipelineWithInputMetadata(.{Good}, p.MetadataKeys(.{Key})); }
''',
        "metadata value must not contain pointer",
    ),
    "metadata-undeclared-read": (
        r'''
const Key = struct { pub const id: u32 = 1; pub const Value = u8; };
const Bad = struct {
    pub const Prepared = void;
    pub const Worker = void;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .work = .{ .maximum_total = packet.max_batch },
    };
    pub fn estimateResources(_: ?p.ConfigurationArtifact, _: usize) p.EstimateError!p.ResourceEstimate {
        return .{ .maximum_batch_work = packet.max_batch };
    }
    pub fn prepare(_: std.mem.Allocator, _: ?p.ConfigurationArtifact) p.PreparationError!Prepared {}
    pub fn instantiate(_: std.mem.Allocator, _: *const Prepared, _: p.WorkerDescriptor) p.InstantiationError!Worker {}
    pub fn processBatch(_: *Worker, context: p.ProcessContext(descriptor)) p.ProcessResult {
        _ = context.metadata(Key, 0) catch null;
        return .{};
    }
    pub fn deinitWorker(_: *Worker, _: std.mem.Allocator) void {}
    pub fn deinitPrepared(_: *Prepared, _: std.mem.Allocator) void {}
};
test { var worker: Bad.Worker = {}; const context: p.ProcessContext(Bad.descriptor) = @enumFromInt(1); _ = Bad.processBatch(&worker, context); }
''',
        "processor used undeclared metadata input key",
    ),
    "metric-unbounded": (
        r'''
const Metric = struct { pub const id = p.MetricId.init(1); pub const Value = u64; };
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .metrics = p.MetricDeclarations(.{Metric}),
        .work = .{ .maximum_total = packet.max_batch },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "metric declaration requires nonzero maximum_series",
    ),
    "event-duplicate": (
        r'''
const A = struct { pub const id = p.EventId.init(1); pub const Payload = u8; pub const maximum_records_per_batch: u16 = 1; };
const B = struct { pub const id = p.EventId.init(1); pub const Payload = u8; pub const maximum_records_per_batch: u16 = 1; };
const Bad = struct {
    pub usingnamespace Good;
    pub const descriptor: p.ProcessorDescriptor = .{
        .id = .init(2), .events = p.EventDeclarations(.{ A, B }),
        .work = .{ .maximum_total = packet.max_batch },
    };
};
comptime { _ = pipeline.Pipeline(.{Bad}); }
''',
        "duplicate event id in processor",
    ),
}


def run_case(name: str, source: str, expected: str, directory: pathlib.Path) -> None:
    source = source.replace("    pub usingnamespace Good;\n", GOOD_MEMBERS)
    path = directory / f"{name}.zig"
    path.write_text(PREFIX + source + "\n", encoding="utf-8")
    command = [
        "zig",
        "test",
        "--dep",
        "saint_shield",
        f"-Mroot={path}",
        f"-Msaint_shield={ROOT / 'src/root.zig'}",
    ]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    combined = result.stdout + result.stderr
    if result.returncode == 0:
        raise SystemExit(f"{name}: invalid declaration compiled successfully")
    if expected not in combined:
        raise SystemExit(
            f"{name}: expected diagnostic {expected!r}\ncommand: {' '.join(command)}\n{combined}"
        )


def run_legitimate_pipeline(directory: pathlib.Path) -> None:
    path = directory / "legitimate-static-pipeline.zig"
    path.write_text(
        PREFIX + "\ntest { _ = pipeline.Pipeline(.{Good}); }\n",
        encoding="utf-8",
    )
    result = subprocess.run(
        [
            "zig",
            "test",
            "--dep",
            "saint_shield",
            f"-Mroot={path}",
            f"-Msaint_shield={ROOT / 'src/root.zig'}",
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(
            "legitimate external static pipeline failed\n"
            + result.stdout
            + result.stderr
        )


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="saint-shield-m3-compile-fail-") as raw:
        directory = pathlib.Path(raw)
        run_legitimate_pipeline(directory)
        for name, (source, expected) in CASES.items():
            run_case(name, source, expected, directory)
    print(f"m3 external contract passed: 1 legitimate pipeline and {len(CASES)} compile-fail cases")


if __name__ == "__main__":
    main()
