//! Saint Shield is a backend-neutral Zig framework for low-level Layer 4
//! protection tools. This M0-V surface establishes package and dependency
//! boundaries; packet behavior is introduced by the predecessor-gated M1-M3
//! milestones.

pub const foundation = @import("foundation/root.zig");
pub const packet = @import("packet/root.zig");
pub const processor = @import("processor/root.zig");
pub const pipeline = @import("pipeline/root.zig");
pub const update = @import("update/root.zig");
pub const observability = @import("observability/root.zig");
pub const state = @import("state/root.zig");
pub const policy = @import("policy/root.zig");
pub const testing = @import("testing/root.zig");
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

