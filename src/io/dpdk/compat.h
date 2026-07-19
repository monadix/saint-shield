/* SPDX-License-Identifier: Apache-2.0 */
#ifndef SAINT_SHIELD_DPDK_COMPAT_H
#define SAINT_SHIELD_DPDK_COMPAT_H

#include <stddef.h>
#include <stdint.h>

/* Private adapter view. Processors and the public library never see it. */
struct saint_dpdk_reserved_u16 {
    _Alignas(2) uint8_t bytes[2];
};

struct saint_dpdk_mbuf_view {
    void *buf_addr;
    uint64_t buf_iova;
    uint16_t data_off;
    struct saint_dpdk_reserved_u16 reserved_refcnt;
    uint16_t nb_segs;
    uint16_t port;
    uint64_t ol_flags;
    uint32_t packet_type;
    uint32_t pkt_len;
    uint16_t data_len;
    uint16_t vlan_tci;
    union {
        uint32_t words[2];
    } hash;
    uint16_t vlan_tci_outer;
    uint16_t buf_len;
    void *pool;
    _Alignas(64) struct saint_dpdk_mbuf_view *next;
};

enum saint_dpdk_mbuf_layout {
    SAINT_DPDK_MBUF_SIZE = sizeof(struct saint_dpdk_mbuf_view),
    SAINT_DPDK_MBUF_ALIGN = _Alignof(struct saint_dpdk_mbuf_view),
    SAINT_DPDK_MBUF_OFFSET_BUF_ADDR = offsetof(struct saint_dpdk_mbuf_view, buf_addr),
    SAINT_DPDK_MBUF_OFFSET_DATA_OFF = offsetof(struct saint_dpdk_mbuf_view, data_off),
    SAINT_DPDK_MBUF_OFFSET_NB_SEGS = offsetof(struct saint_dpdk_mbuf_view, nb_segs),
    SAINT_DPDK_MBUF_OFFSET_PORT = offsetof(struct saint_dpdk_mbuf_view, port),
    SAINT_DPDK_MBUF_OFFSET_OL_FLAGS = offsetof(struct saint_dpdk_mbuf_view, ol_flags),
    SAINT_DPDK_MBUF_OFFSET_PKT_LEN = offsetof(struct saint_dpdk_mbuf_view, pkt_len),
    SAINT_DPDK_MBUF_OFFSET_DATA_LEN = offsetof(struct saint_dpdk_mbuf_view, data_len),
    SAINT_DPDK_MBUF_OFFSET_NEXT = offsetof(struct saint_dpdk_mbuf_view, next),
};

_Static_assert(sizeof(((struct saint_dpdk_mbuf_view *)0)->pkt_len) == sizeof(uint32_t),
               "view pkt_len must remain 32-bit");
_Static_assert(sizeof(((struct saint_dpdk_mbuf_view *)0)->data_len) == sizeof(uint16_t),
               "view data_len must remain 16-bit");

struct saint_dpdk_abi_report {
    size_t size;
    size_t alignment;
    size_t data_off_offset;
    size_t pkt_len_offset;
    size_t data_len_offset;
    size_t next_offset;
};

struct saint_dpdk_cleanup_report {
    uint32_t allocated;
    uint32_t completed;
    uint32_t initial_available;
    uint32_t final_available;
    uint32_t drained_rx;
    uint32_t drained_tx;
    uint32_t rx_bursts;
    uint32_t tx_bursts;
    uint8_t balanced;
};

enum saint_dpdk_injection {
    SAINT_DPDK_INJECT_NONE = 0,
    SAINT_DPDK_INJECT_AFTER_POOL = 1,
    SAINT_DPDK_INJECT_AFTER_RINGS = 2,
    SAINT_DPDK_INJECT_AFTER_PORT = 3,
    SAINT_DPDK_INJECT_AFTER_ENQUEUE = 4,
    SAINT_DPDK_INJECT_TX_REJECT = 5,
    SAINT_DPDK_INJECT_AFTER_TX_ACCEPT = 6,
};

struct saint_dpdk_context;

int saint_dpdk_validate_abi(struct saint_dpdk_abi_report *report);
int saint_dpdk_context_create(int injection,
                              struct saint_dpdk_context **context,
                              struct saint_dpdk_cleanup_report *failure_report);
uint16_t saint_dpdk_rx_burst(struct saint_dpdk_context *context,
                             struct saint_dpdk_mbuf_view **tokens,
                             uint16_t capacity);
uint16_t saint_dpdk_tx_burst(struct saint_dpdk_context *context,
                             struct saint_dpdk_mbuf_view **tokens,
                             uint16_t count);
uint16_t saint_dpdk_release_burst(struct saint_dpdk_context *context,
                                  struct saint_dpdk_mbuf_view **tokens,
                                  uint16_t count);
int saint_dpdk_complete_tx(struct saint_dpdk_context *context,
                           uint16_t expected);
int saint_dpdk_context_destroy(struct saint_dpdk_context *context,
                               struct saint_dpdk_cleanup_report *report);

#endif
