// SPDX-License-Identifier: Apache-2.0
//! I/O adapters remain outside the framework core dependency graph.
/// Deterministic hardware-free adapter namespace; its queue API begins in M1.
pub const synthetic = @import("synthetic/root.zig");
/// Bounded capture fixture namespace; its parser API begins in M1.
pub const pcap = @import("pcap/root.zig");
