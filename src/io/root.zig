//! I/O adapters remain outside the framework core dependency graph.
pub const synthetic = @import("synthetic/root.zig");
pub const pcap = @import("pcap/root.zig");

