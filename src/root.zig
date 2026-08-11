// SPDX-License-Identifier: Apache-2.0
//! Saint Shield is a backend-neutral Zig framework for low-level Layer 4
//! protection tools. The M2 surface adds bounded parsing, selection,
//! dispositions, structured/raw mutation, software finalization, and explicit
//! retention to the M1 ownership and segment-safe view foundation.

/// Dependency-free identifiers, bounded errors/budgets, and monotonic time.
pub const foundation = @import("foundation/root.zig");
/// Backend-neutral packet segments, views, origins, and ownership accounting.
pub const packet = @import("packet/root.zig");
/// Native processor declarations and capability contracts, introduced in M3.
pub const processor = @import("processor/root.zig");
/// Compile-time tuple pipeline namespace, introduced in M3.
pub const pipeline = @import("pipeline/root.zig");
/// Prepared-generation publication namespace, predecessor-gated to M6.
pub const update = @import("update/root.zig");
/// Bounded metrics and event namespace, introduced after the core pipeline.
pub const observability = @import("observability/root.zig");
/// Optional reusable state namespace, predecessor-gated to M10.
pub const state = @import("state/root.zig");
/// Optional standard policy namespace, predecessor-gated to M9.
pub const policy = @import("policy/root.zig");
/// Public deterministic test facilities for framework extensions.
pub const testing = @import("testing/root.zig");
/// Adapter namespace; adapters depend on core contracts, never the reverse.
pub const io = @import("io/root.zig");

/// Exact framework source API version for the M2 implementation surface.
pub const version = "0.2.0-m2";

test "public module surface remains importable without optional adapters" {
    _ = foundation;
    _ = packet;
    _ = processor;
    _ = pipeline;
    _ = update;
    _ = observability;
    _ = state;
    _ = policy;
    _ = testing;
    _ = testing.default_seed;
    _ = io;
    _ = io.synthetic;
    _ = io.pcap;
}
