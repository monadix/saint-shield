// SPDX-License-Identifier: Apache-2.0

const c = @cImport({
    @cInclude("compat.h");
});

const expected_payload = "SAINT-SHIELD-M0V";

/// Runs one Zig-owned virtual batch and returns zero only when token and pool
/// accounting match the selected deterministic cleanup scenario.
export fn saint_zig_virtual_batch(
    injection: c_int,
    report: *c.struct_saint_dpdk_cleanup_report,
) c_int {
    var context: ?*c.struct_saint_dpdk_context = null;
    const create_result = c.saint_dpdk_context_create(injection, &context, report);

    const setup_failure = injection >= c.SAINT_DPDK_INJECT_AFTER_POOL and
        injection <= c.SAINT_DPDK_INJECT_AFTER_ENQUEUE;
    if (setup_failure) {
        if (create_result >= 0 or context != null)
            return -10;
        if (!reportIsBalanced(report))
            return -11;
        if (injection == c.SAINT_DPDK_INJECT_AFTER_ENQUEUE) {
            if (report.allocated != 1 or report.completed != 1 or
                report.drained_rx != 1 or report.drained_tx != 0)
                return -23;
        } else if (report.allocated != 0 or report.completed != 0 or
            report.drained_rx != 0 or report.drained_tx != 0)
        {
            return -24;
        }
        return 0;
    }
    if (create_result != 0 or context == null)
        return -12;

    const active_context = context.?;
    var tokens = [_]?*c.struct_saint_dpdk_mbuf_view{null};
    var zig_owns_token = false;
    var status: c_int = 0;

    const received = c.saint_dpdk_rx_burst(active_context, &tokens, 1);
    if (received != 1 or tokens[0] == null) {
        status = -13;
    } else {
        // Ownership transfer: the single RX batch call moved this real mbuf
        // token into the Zig batch. No C field accessor is used below.
        zig_owns_token = true;
        const view = tokens[0].?;
        if (view.nb_segs != 1 or view.next != null or
            view.pkt_len != expected_payload.len or
            view.data_len != expected_payload.len)
        {
            status = -14;
        } else {
            const buffer: [*]const u8 = @ptrCast(view.buf_addr.?);
            const start: usize = view.data_off;
            for (expected_payload, 0..) |expected, index| {
                if (buffer[start + index] != expected) {
                    status = -15;
                    break;
                }
            }
        }
    }

    if (status == 0) {
        const submitted = c.saint_dpdk_tx_burst(active_context, &tokens, 1);
        if (injection == c.SAINT_DPDK_INJECT_TX_REJECT) {
            if (submitted != 0) {
                status = -16;
            } else if (c.saint_dpdk_release_burst(active_context, &tokens, 1) != 1) {
                status = -17;
            } else {
                zig_owns_token = false;
            }
        } else if (submitted != 1) {
            status = -18;
        } else {
            // Explicit transfer: Zig batch -> TX ring accepted prefix.
            tokens[0] = null;
            zig_owns_token = false;
            if (injection != c.SAINT_DPDK_INJECT_AFTER_TX_ACCEPT and
                c.saint_dpdk_complete_tx(active_context, 1) != 0)
                status = -19;
        }
    }

    if (zig_owns_token) {
        if (c.saint_dpdk_release_burst(active_context, &tokens, 1) != 1 and
            status == 0)
            status = -20;
        zig_owns_token = false;
    }

    if (c.saint_dpdk_context_destroy(active_context, report) != 0 and
        status == 0)
        status = -21;
    context = null;
    if (!reportIsBalanced(report) and status == 0)
        status = -22;
    if (status == 0) {
        const expected_drained_tx: u32 = if (injection == c.SAINT_DPDK_INJECT_AFTER_TX_ACCEPT) 1 else 0;
        if (report.allocated != 1 or report.completed != 1 or
            report.drained_rx != 0 or report.drained_tx != expected_drained_tx or
            report.rx_bursts != 1 or report.tx_bursts != 1)
            status = -25;
    }
    return status;
}

fn reportIsBalanced(report: *const c.struct_saint_dpdk_cleanup_report) bool {
    return report.balanced == 1 and
        report.allocated == report.completed and
        report.initial_available == report.final_available;
}
