// SPDX-License-Identifier: Apache-2.0
//! Saint Shield is a backend-neutral Zig framework for low-level Layer 4
//! protection tools. This M0-V surface establishes package and dependency
//! boundaries; packet behavior is introduced by the predecessor-gated M1-M3
//! milestones.

/// Dependency-free foundational contracts; the concrete API begins in M1.
pub const foundation = @import("foundation/root.zig");
/// Backend-neutral packet contracts; the concrete API begins in M1.
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

/// Exact framework source API version for the M0-V scaffold.
pub const version = "0.0.0-m0v";

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
    _ = io;
}
