/* SPDX-License-Identifier: Apache-2.0 */
#define _GNU_SOURCE
#include "compat.h"

#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>

#include <rte_eal.h>
#include <rte_errno.h>
#include <rte_eth_ring.h>
#include <rte_ethdev.h>
#include <rte_mempool.h>
#include <rte_ring.h>
#include <rte_version.h>

#if RTE_VER_YEAR != 25 || RTE_VER_MONTH != 11 || RTE_VER_MINOR != 2
#error "Saint Shield M0-V requires DPDK 25.11.2 exactly"
#endif
#if !RTE_IOVA_IN_MBUF
#error "Saint Shield mbuf view requires the pinned IOVA-in-mbuf configuration"
#endif

#define SAINT_ASSERT_MBUF_FIELD(field)                                      \
    _Static_assert(offsetof(struct saint_dpdk_mbuf_view, field) ==          \
                       offsetof(struct rte_mbuf, field),                    \
                   "rte_mbuf field offset changed: " #field);              \
    _Static_assert(sizeof(((struct saint_dpdk_mbuf_view *)0)->field) ==      \
                       sizeof(((struct rte_mbuf *)0)->field),                \
                   "rte_mbuf field size changed: " #field);                \
    _Static_assert(_Alignof(__typeof__(                                     \
                       ((struct saint_dpdk_mbuf_view *)0)->field)) ==        \
                       _Alignof(__typeof__(                                 \
                           ((struct rte_mbuf *)0)->field)),                  \
                   "rte_mbuf field alignment changed: " #field)

_Static_assert(sizeof(struct saint_dpdk_mbuf_view) == sizeof(struct rte_mbuf),
               "rte_mbuf size changed");
_Static_assert(_Alignof(struct saint_dpdk_mbuf_view) == _Alignof(struct rte_mbuf),
               "rte_mbuf alignment changed");
SAINT_ASSERT_MBUF_FIELD(buf_addr);
SAINT_ASSERT_MBUF_FIELD(buf_iova);
SAINT_ASSERT_MBUF_FIELD(data_off);
SAINT_ASSERT_MBUF_FIELD(refcnt);
SAINT_ASSERT_MBUF_FIELD(nb_segs);
SAINT_ASSERT_MBUF_FIELD(port);
SAINT_ASSERT_MBUF_FIELD(ol_flags);
SAINT_ASSERT_MBUF_FIELD(packet_type);
SAINT_ASSERT_MBUF_FIELD(pkt_len);
SAINT_ASSERT_MBUF_FIELD(data_len);
SAINT_ASSERT_MBUF_FIELD(vlan_tci);
SAINT_ASSERT_MBUF_FIELD(hash);
SAINT_ASSERT_MBUF_FIELD(vlan_tci_outer);
SAINT_ASSERT_MBUF_FIELD(buf_len);
SAINT_ASSERT_MBUF_FIELD(pool);
SAINT_ASSERT_MBUF_FIELD(next);

int
saint_dpdk_validate_abi(struct saint_dpdk_abi_report *report)
{
    if (report == NULL)
        return -EINVAL;

    report->size = sizeof(struct rte_mbuf);
    report->alignment = _Alignof(struct rte_mbuf);
    report->data_off_offset = offsetof(struct rte_mbuf, data_off);
    report->pkt_len_offset = offsetof(struct rte_mbuf, pkt_len);
    report->data_len_offset = offsetof(struct rte_mbuf, data_len);
    report->next_offset = offsetof(struct rte_mbuf, next);
    return 0;
}

static int
configure_ring_port(uint16_t port_id, struct rte_mempool *pool)
{
    struct rte_eth_conf config;
    memset(&config, 0, sizeof(config));

    int result = rte_eth_dev_configure(port_id, 1, 1, &config);
    if (result != 0)
        return result;
    result = rte_eth_rx_queue_setup(port_id, 0, 64, SOCKET_ID_ANY, NULL, pool);
    if (result != 0)
        return result;
    result = rte_eth_tx_queue_setup(port_id, 0, 64, SOCKET_ID_ANY, NULL);
    if (result != 0)
        return result;
    return rte_eth_dev_start(port_id);
}

int
saint_dpdk_virtual_roundtrip(void)
{
    char lcore_arg[64];
    const int cpu = sched_getcpu();
    if (cpu < 0)
        return -errno;
    if (snprintf(lcore_arg, sizeof(lcore_arg), "--lcores=0@%d", cpu) < 0)
        return -EINVAL;

    char program[] = "saint-dpdk-virtual";
    char no_huge[] = "--no-huge";
    char no_pci[] = "--no-pci";
    char in_memory[] = "--in-memory";
    char no_telemetry[] = "--no-telemetry";
    char *eal_argv[] = {
        program,
        lcore_arg,
        no_huge,
        no_pci,
        in_memory,
        no_telemetry,
    };

    int result = rte_eal_init((int)(sizeof(eal_argv) / sizeof(eal_argv[0])), eal_argv);
    if (result < 0)
        return -rte_errno;

    struct rte_mempool *pool = NULL;
    struct rte_ring *rx_ring = NULL;
    struct rte_ring *tx_ring = NULL;
    struct rte_mbuf *original = NULL;
    struct rte_mbuf *received = NULL;
    struct rte_mbuf *completed = NULL;
    uint16_t port_id = UINT16_MAX;
    int status = -1;

    pool = rte_pktmbuf_pool_create("saint_m0v_pool", 127, 0, 0,
                                  RTE_MBUF_DEFAULT_BUF_SIZE, SOCKET_ID_ANY);
    if (pool == NULL) {
        status = -rte_errno;
        goto cleanup;
    }
    rx_ring = rte_ring_create("saint_m0v_rx", 64, SOCKET_ID_ANY,
                              RING_F_SP_ENQ | RING_F_SC_DEQ);
    tx_ring = rte_ring_create("saint_m0v_tx", 64, SOCKET_ID_ANY,
                              RING_F_SP_ENQ | RING_F_SC_DEQ);
    if (rx_ring == NULL || tx_ring == NULL) {
        status = -rte_errno;
        goto cleanup;
    }

    struct rte_ring *rx_queues[] = {rx_ring};
    struct rte_ring *tx_queues[] = {tx_ring};
    result = rte_eth_from_rings("saint_m0v", rx_queues, 1, tx_queues, 1,
                                SOCKET_ID_ANY);
    if (result < 0) {
        status = -rte_errno;
        goto cleanup;
    }
    port_id = (uint16_t)result;
    result = configure_ring_port(port_id, pool);
    if (result != 0) {
        status = result;
        goto cleanup;
    }

    static const uint8_t payload[] = {
        0x53, 0x41, 0x49, 0x4e, 0x54, 0x2d, 0x53, 0x48,
        0x49, 0x45, 0x4c, 0x44, 0x2d, 0x4d, 0x30, 0x56,
    };
    original = rte_pktmbuf_alloc(pool);
    if (original == NULL) {
        status = -ENOMEM;
        goto cleanup;
    }
    uint8_t *bytes = (uint8_t *)(void *)rte_pktmbuf_append(original, sizeof(payload));
    if (bytes == NULL) {
        status = -ENOSPC;
        goto cleanup;
    }
    memcpy(bytes, payload, sizeof(payload));
    if (rte_ring_enqueue(rx_ring, original) != 0) {
        status = -ENOBUFS;
        goto cleanup;
    }

    if (rte_eth_rx_burst(port_id, 0, &received, 1) != 1 || received != original) {
        status = -EIO;
        goto cleanup;
    }
    original = NULL;
    if (received->pkt_len != sizeof(payload) ||
        received->data_len != sizeof(payload) ||
        memcmp(rte_pktmbuf_mtod(received, const uint8_t *), payload,
               sizeof(payload)) != 0) {
        status = -EBADMSG;
        goto cleanup;
    }
    if (rte_eth_tx_burst(port_id, 0, &received, 1) != 1) {
        status = -EIO;
        goto cleanup;
    }
    received = NULL;
    if (rte_ring_dequeue(tx_ring, (void **)&completed) != 0 || completed == NULL) {
        status = -EIO;
        goto cleanup;
    }
    if (completed->pkt_len != sizeof(payload) ||
        memcmp(rte_pktmbuf_mtod(completed, const uint8_t *), payload,
               sizeof(payload)) != 0) {
        status = -EBADMSG;
        goto cleanup;
    }

    status = 0;

cleanup:
    if (completed != NULL)
        rte_pktmbuf_free(completed);
    if (received != NULL)
        rte_pktmbuf_free(received);
    if (original != NULL)
        rte_pktmbuf_free(original);
    if (port_id != UINT16_MAX) {
        rte_eth_dev_stop(port_id);
        rte_eth_dev_close(port_id);
    }
    if (rx_ring != NULL)
        rte_ring_free(rx_ring);
    if (tx_ring != NULL)
        rte_ring_free(tx_ring);
    if (pool != NULL)
        rte_mempool_free(pool);
    result = rte_eal_cleanup();
    if (status == 0 && result != 0)
        status = result;
    return status;
}
