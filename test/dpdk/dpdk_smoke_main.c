/* SPDX-License-Identifier: Apache-2.0 */
#include "compat.h"

#include <stdio.h>

int
main(void)
{
    struct saint_dpdk_abi_report report;
    int result = saint_dpdk_validate_abi(&report);
    if (result != 0) {
        fprintf(stderr, "DPDK ABI runtime validation failed: %d\n", result);
        return 1;
    }
    printf("M0V_ABI size=%zu align=%zu data_off=%zu pkt_len=%zu data_len=%zu next=%zu\n",
           report.size, report.alignment, report.data_off_offset,
           report.pkt_len_offset, report.data_len_offset, report.next_offset);

    result = saint_dpdk_virtual_roundtrip();
    if (result != 0) {
        fprintf(stderr, "DPDK virtual round trip failed: %d\n", result);
        return 1;
    }
    puts("DPDK no-huge ring-PMD token round trip passed");
    return 0;
}
