/* SPDX-License-Identifier: Apache-2.0 */
#define _GNU_SOURCE
#include "compat.h"

#include <errno.h>
#include <sched.h>
#include <stdio.h>
#include <stdlib.h>
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
_Static_assert(offsetof(struct saint_dpdk_mbuf_view, reserved_refcnt) ==
                   offsetof(struct rte_mbuf, refcnt),
               "rte_mbuf reserved refcount slot moved");
_Static_assert(sizeof(((struct saint_dpdk_mbuf_view *)0)->reserved_refcnt) ==
                   sizeof(((struct rte_mbuf *)0)->refcnt),
               "rte_mbuf reserved refcount slot size changed");
_Static_assert(_Alignof(struct saint_dpdk_reserved_u16) ==
                   _Alignof(__typeof__(((struct rte_mbuf *)0)->refcnt)),
               "rte_mbuf reserved refcount slot alignment changed");
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

struct saint_dpdk_context {
    struct rte_mempool *pool;
    struct rte_ring *rx_ring;
    struct rte_ring *tx_ring;
    struct rte_mbuf *prepared_token;
    uint16_t port_id;
    int injection;
    uint32_t allocated;
    uint32_t completed;
    uint32_t initial_available;
    uint32_t drained_rx;
    uint32_t drained_tx;
    uint32_t rx_bursts;
    uint32_t tx_bursts;
    uint8_t port_started;
    uint8_t eal_started;
};

static const uint8_t saint_payload[] = {
    0x53, 0x41, 0x49, 0x4e, 0x54, 0x2d, 0x53, 0x48,
    0x49, 0x45, 0x4c, 0x44, 0x2d, 0x4d, 0x30, 0x56,
};

static void
free_token(struct saint_dpdk_context *context, struct rte_mbuf *token)
{
    if (token == NULL)
        return;
    rte_pktmbuf_free(token);
    context->completed++;
}

static uint32_t
drain_ring(struct saint_dpdk_context *context, struct rte_ring *ring)
{
    uint32_t drained = 0;
    struct rte_mbuf *token = NULL;
    if (ring == NULL)
        return 0;
    while (rte_ring_dequeue(ring, (void **)&token) == 0) {
        free_token(context, token);
        drained++;
        token = NULL;
    }
    return drained;
}

static int
destroy_internal(struct saint_dpdk_context *context,
                 struct saint_dpdk_cleanup_report *report)
{
    if (report != NULL)
        memset(report, 0, sizeof(*report));
    if (context == NULL) {
        if (report != NULL)
            report->balanced = 1;
        return 0;
    }

    if (context->port_started) {
        (void)rte_eth_dev_stop(context->port_id);
        context->port_started = 0;
    }

    /* Ownership reconciliation: rings own queued tokens; this context owns
     * prepared_token only before its successful enqueue. */
    context->drained_rx += drain_ring(context, context->rx_ring);
    context->drained_tx += drain_ring(context, context->tx_ring);
    if (context->prepared_token != NULL) {
        free_token(context, context->prepared_token);
        context->prepared_token = NULL;
    }

    if (context->port_id != UINT16_MAX) {
        (void)rte_eth_dev_close(context->port_id);
        context->port_id = UINT16_MAX;
    }
    if (context->rx_ring != NULL) {
        rte_ring_free(context->rx_ring);
        context->rx_ring = NULL;
    }
    if (context->tx_ring != NULL) {
        rte_ring_free(context->tx_ring);
        context->tx_ring = NULL;
    }

    uint32_t final_available = 0;
    if (context->pool != NULL) {
        final_available = rte_mempool_avail_count(context->pool);
        rte_mempool_free(context->pool);
        context->pool = NULL;
    }
    if (context->eal_started) {
        (void)rte_eal_cleanup();
        context->eal_started = 0;
    }

    const uint8_t balanced =
        context->allocated == context->completed &&
        final_available == context->initial_available;
    if (report != NULL) {
        report->allocated = context->allocated;
        report->completed = context->completed;
        report->initial_available = context->initial_available;
        report->final_available = final_available;
        report->drained_rx = context->drained_rx;
        report->drained_tx = context->drained_tx;
        report->rx_bursts = context->rx_bursts;
        report->tx_bursts = context->tx_bursts;
        report->balanced = balanced;
    }
    free(context);
    return balanced ? 0 : -EUCLEAN;
}

static int
configure_ring_port(struct saint_dpdk_context *context)
{
    struct rte_eth_conf config;
    memset(&config, 0, sizeof(config));
    int result = rte_eth_dev_configure(context->port_id, 1, 1, &config);
    if (result != 0)
        return result;
    result = rte_eth_rx_queue_setup(context->port_id, 0, 64, SOCKET_ID_ANY,
                                    NULL, context->pool);
    if (result != 0)
        return result;
    result = rte_eth_tx_queue_setup(context->port_id, 0, 64, SOCKET_ID_ANY,
                                    NULL);
    if (result != 0)
        return result;
    result = rte_eth_dev_start(context->port_id);
    if (result == 0)
        context->port_started = 1;
    return result;
}

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

int
saint_dpdk_context_create(int injection,
                          struct saint_dpdk_context **context_out,
                          struct saint_dpdk_cleanup_report *failure_report)
{
    if (context_out == NULL || failure_report == NULL)
        return -EINVAL;
    *context_out = NULL;
    memset(failure_report, 0, sizeof(*failure_report));

    char lcore_arg[64];
    const int cpu = sched_getcpu();
    if (cpu < 0)
        return -errno;
    if (snprintf(lcore_arg, sizeof(lcore_arg), "--lcores=0@%d", cpu) < 0)
        return -EINVAL;
    char program[] = "saint-dpdk-zig-batch";
    char no_huge[] = "--no-huge";
    char no_pci[] = "--no-pci";
    char in_memory[] = "--in-memory";
    char no_telemetry[] = "--no-telemetry";
    char *eal_argv[] = {program, lcore_arg, no_huge, no_pci, in_memory,
                        no_telemetry};
    if (rte_eal_init((int)(sizeof(eal_argv) / sizeof(eal_argv[0])),
                     eal_argv) < 0)
        return -rte_errno;

    struct saint_dpdk_context *context = calloc(1, sizeof(*context));
    if (context == NULL) {
        (void)rte_eal_cleanup();
        return -ENOMEM;
    }
    context->eal_started = 1;
    context->port_id = UINT16_MAX;
    context->injection = injection;

    int result = -EIO;
    context->pool = rte_pktmbuf_pool_create(
        "saint_m0v_pool", 127, 0, 0, RTE_MBUF_DEFAULT_BUF_SIZE,
        SOCKET_ID_ANY);
    if (context->pool == NULL) {
        result = -rte_errno;
        goto failure;
    }
    context->initial_available = rte_mempool_avail_count(context->pool);
    if (injection == SAINT_DPDK_INJECT_AFTER_POOL)
        goto failure;

    context->rx_ring = rte_ring_create(
        "saint_m0v_rx", 64, SOCKET_ID_ANY, RING_F_SP_ENQ | RING_F_SC_DEQ);
    context->tx_ring = rte_ring_create(
        "saint_m0v_tx", 64, SOCKET_ID_ANY, RING_F_SP_ENQ | RING_F_SC_DEQ);
    if (context->rx_ring == NULL || context->tx_ring == NULL) {
        result = -rte_errno;
        goto failure;
    }
    if (injection == SAINT_DPDK_INJECT_AFTER_RINGS)
        goto failure;

    struct rte_ring *rx_queues[] = {context->rx_ring};
    struct rte_ring *tx_queues[] = {context->tx_ring};
    result = rte_eth_from_rings("saint_m0v", rx_queues, 1, tx_queues, 1,
                                SOCKET_ID_ANY);
    if (result < 0) {
        result = -rte_errno;
        goto failure;
    }
    context->port_id = (uint16_t)result;
    result = configure_ring_port(context);
    if (result != 0)
        goto failure;
    if (injection == SAINT_DPDK_INJECT_AFTER_PORT) {
        result = -EIO;
        goto failure;
    }

    context->prepared_token = rte_pktmbuf_alloc(context->pool);
    if (context->prepared_token == NULL) {
        result = -ENOMEM;
        goto failure;
    }
    context->allocated++;
    uint8_t *bytes = (uint8_t *)(void *)rte_pktmbuf_append(
        context->prepared_token, sizeof(saint_payload));
    if (bytes == NULL) {
        result = -ENOSPC;
        goto failure;
    }
    memcpy(bytes, saint_payload, sizeof(saint_payload));
    if (rte_ring_enqueue(context->rx_ring, context->prepared_token) != 0) {
        result = -ENOBUFS;
        goto failure;
    }
    /* Explicit transfer: prepared_token -> RX ring. */
    context->prepared_token = NULL;
    if (injection == SAINT_DPDK_INJECT_AFTER_ENQUEUE) {
        result = -EIO;
        goto failure;
    }

    *context_out = context;
    return 0;

failure:
    (void)destroy_internal(context, failure_report);
    return result;
}

uint16_t
saint_dpdk_rx_burst(struct saint_dpdk_context *context,
                    struct saint_dpdk_mbuf_view **tokens,
                    uint16_t capacity)
{
    if (context == NULL || tokens == NULL || capacity == 0)
        return 0;
    struct rte_mbuf *received[64];
    if (capacity > 64)
        capacity = 64;
    const uint16_t count = rte_eth_rx_burst(context->port_id, 0, received,
                                            capacity);
    context->rx_bursts++;
    for (uint16_t index = 0; index < count; index++)
        tokens[index] = (struct saint_dpdk_mbuf_view *)(void *)received[index];
    /* Explicit transfer: RX ring -> Zig batch token array. */
    return count;
}

uint16_t
saint_dpdk_tx_burst(struct saint_dpdk_context *context,
                    struct saint_dpdk_mbuf_view **tokens,
                    uint16_t count)
{
    if (context == NULL || tokens == NULL || count == 0)
        return 0;
    context->tx_bursts++;
    if (context->injection == SAINT_DPDK_INJECT_TX_REJECT)
        return 0;
    struct rte_mbuf *submitted[64];
    if (count > 64)
        count = 64;
    for (uint16_t index = 0; index < count; index++)
        submitted[index] = (struct rte_mbuf *)(void *)tokens[index];
    /* The returned prefix transfers from Zig to the TX ring. */
    return rte_eth_tx_burst(context->port_id, 0, submitted, count);
}

uint16_t
saint_dpdk_release_burst(struct saint_dpdk_context *context,
                         struct saint_dpdk_mbuf_view **tokens,
                         uint16_t count)
{
    if (context == NULL || tokens == NULL)
        return 0;
    uint16_t released = 0;
    for (uint16_t index = 0; index < count; index++) {
        if (tokens[index] != NULL) {
            free_token(context, (struct rte_mbuf *)(void *)tokens[index]);
            tokens[index] = NULL;
            released++;
        }
    }
    return released;
}

int
saint_dpdk_complete_tx(struct saint_dpdk_context *context, uint16_t expected)
{
    if (context == NULL)
        return -EINVAL;
    uint16_t completed = 0;
    struct rte_mbuf *token = NULL;
    while (completed < expected &&
           rte_ring_dequeue(context->tx_ring, (void **)&token) == 0) {
        free_token(context, token);
        token = NULL;
        completed++;
    }
    return completed == expected ? 0 : -EIO;
}

int
saint_dpdk_context_destroy(struct saint_dpdk_context *context,
                           struct saint_dpdk_cleanup_report *report)
{
    return destroy_internal(context, report);
}
