/* SPDX-License-Identifier: Apache-2.0 */
#include "compat.h"

#include <stdio.h>
#include <stdlib.h>

extern int saint_zig_virtual_batch(int injection,
                                   struct saint_dpdk_cleanup_report *report);

int
main(int argc, char **argv)
{
    if (argc != 2)
        return 2;
    const int injection = atoi(argv[1]);

    struct saint_dpdk_abi_report abi;
    if (saint_dpdk_validate_abi(&abi) != 0)
        return 1;
    printf("M0V_ABI size=%zu align=%zu data_off=%zu pkt_len=%zu data_len=%zu next=%zu\n",
           abi.size, abi.alignment, abi.data_off_offset, abi.pkt_len_offset,
           abi.data_len_offset, abi.next_offset);

    struct saint_dpdk_cleanup_report cleanup;
    const int result = saint_zig_virtual_batch(injection, &cleanup);
    printf("M0V_CLEANUP injection=%d allocated=%u completed=%u initial=%u final=%u drained_rx=%u drained_tx=%u rx_bursts=%u tx_bursts=%u balanced=%u\n",
           injection, cleanup.allocated, cleanup.completed,
           cleanup.initial_available, cleanup.final_available,
           cleanup.drained_rx, cleanup.drained_tx, cleanup.rx_bursts,
           cleanup.tx_bursts, cleanup.balanced);
    if (result != 0) {
        fprintf(stderr, "Zig-driven virtual batch failed: %d\n", result);
        return 1;
    }
    return 0;
}
