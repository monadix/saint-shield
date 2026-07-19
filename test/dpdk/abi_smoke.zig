// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

const c = @cImport({
    @cInclude("compat.h");
});

comptime {
    if (@hasField(c.struct_saint_dpdk_mbuf_view, "refcnt"))
        @compileError("the DPDK adapter must not expose rte_mbuf.refcnt to Zig");
    if (@sizeOf(c.struct_saint_dpdk_mbuf_view) != c.SAINT_DPDK_MBUF_SIZE)
        @compileError("translated mbuf view size differs from C");
    if (@alignOf(c.struct_saint_dpdk_mbuf_view) != c.SAINT_DPDK_MBUF_ALIGN)
        @compileError("translated mbuf view alignment differs from C");
    if (@offsetOf(c.struct_saint_dpdk_mbuf_view, "data_off") != c.SAINT_DPDK_MBUF_OFFSET_DATA_OFF)
        @compileError("translated rte_mbuf.data_off offset differs");
    if (@offsetOf(c.struct_saint_dpdk_mbuf_view, "pkt_len") != c.SAINT_DPDK_MBUF_OFFSET_PKT_LEN)
        @compileError("translated rte_mbuf.pkt_len offset differs");
    if (@offsetOf(c.struct_saint_dpdk_mbuf_view, "data_len") != c.SAINT_DPDK_MBUF_OFFSET_DATA_LEN)
        @compileError("translated rte_mbuf.data_len offset differs");
    if (@offsetOf(c.struct_saint_dpdk_mbuf_view, "next") != c.SAINT_DPDK_MBUF_OFFSET_NEXT)
        @compileError("translated rte_mbuf.next offset differs");
}

/// Emits the Zig-translated layout and checks direct non-owning field access.
pub fn main() !void {
    // SAFETY: this stack value has no backend ownership; it exists only to
    // prove Zig emits direct field loads/stores at the C-asserted offsets.
    var imported: c.struct_saint_dpdk_mbuf_view = std.mem.zeroes(c.struct_saint_dpdk_mbuf_view);
    imported.data_off = 128;
    imported.pkt_len = 64;
    imported.data_len = 64;
    if (imported.data_off != 128 or imported.pkt_len != 64 or imported.data_len != 64)
        return error.DpdkDirectFieldAccessFailed;

    std.debug.print(
        "M0V_ABI size={d} align={d} data_off={d} pkt_len={d} data_len={d} next={d}\n",
        .{
            @sizeOf(c.struct_saint_dpdk_mbuf_view),
            @alignOf(c.struct_saint_dpdk_mbuf_view),
            @offsetOf(c.struct_saint_dpdk_mbuf_view, "data_off"),
            @offsetOf(c.struct_saint_dpdk_mbuf_view, "pkt_len"),
            @offsetOf(c.struct_saint_dpdk_mbuf_view, "data_len"),
            @offsetOf(c.struct_saint_dpdk_mbuf_view, "next"),
        },
    );
}
