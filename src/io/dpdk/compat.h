/* SPDX-License-Identifier: Apache-2.0 */
#ifndef SAINT_SHIELD_DPDK_COMPAT_H
#define SAINT_SHIELD_DPDK_COMPAT_H

#include <stddef.h>
#include <stdint.h>

/*
 * SAFETY: this narrow, stable-to-this-adapter view is asserted field-for-field
 * against the pinned rte_mbuf by compat.c. Zig imports this view instead of
 * translating DPDK's unrelated EAL/TLS declarations. It is an internal C ABI,
 * not a public framework type, and no pointer outlives backend ownership.
 */
struct saint_dpdk_mbuf_view {
    void *buf_addr;
    uint64_t buf_iova;
    uint16_t data_off;
    uint16_t refcnt;
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

_Static_assert(SAINT_DPDK_MBUF_OFFSET_BUF_ADDR < SAINT_DPDK_MBUF_OFFSET_DATA_OFF,
               "rte_mbuf prefix ordering changed");
_Static_assert(SAINT_DPDK_MBUF_OFFSET_DATA_OFF < SAINT_DPDK_MBUF_OFFSET_PKT_LEN,
               "rte_mbuf packet fields moved before data offset");
_Static_assert(SAINT_DPDK_MBUF_OFFSET_PKT_LEN < SAINT_DPDK_MBUF_OFFSET_NEXT,
               "rte_mbuf chaining field ordering changed");
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

int saint_dpdk_validate_abi(struct saint_dpdk_abi_report *report);
int saint_dpdk_virtual_roundtrip(void);

#endif
