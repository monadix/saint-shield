#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Compare M2 parsing and mutation bytes with the pinned Scapy 2.7 oracle."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

import scapy
from scapy.all import (
    Dot1Q,
    Ether,
    IP,
    IPOption_NOP,
    IPv6,
    IPv6ExtHdrFragment,
    IPv6ExtHdrHopByHop,
    PadN,
    Raw,
    TCP,
    UDP,
)


ROOT = Path(__file__).resolve().parents[2]
TEST_ETHER = {"src": "02:00:00:00:00:01", "dst": "02:00:00:00:00:02"}


def zig(mode: str, packet: bytes) -> str:
    command = [
        "zig", "run", "--dep", "saint_shield",
        "-Mroot=test/m2/oracle.zig", "-Msaint_shield=src/root.zig",
        "--", mode, packet.hex(),
    ]
    completed = subprocess.run(
        command,
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output = (completed.stdout + completed.stderr).strip().splitlines()
    if not output:
        raise AssertionError("Zig oracle produced no output")
    return output[-1]


def finalized(packet) -> bytes:
    return bytes(packet.__class__(bytes(packet)))


def compare(name: str, packet, network: str, transport: str) -> None:
    original = bytes(packet)
    decoded = json.loads(zig("parse", original))
    reparsed = Ether(original)
    layer = reparsed[IP] if network == "ipv4" else reparsed[IPv6]
    transport_layer = reparsed[UDP] if transport == "udp" else reparsed[TCP]
    assert decoded["length"] == len(original)
    assert decoded["ethernet"] == "present"
    assert decoded["network"] == "present"
    assert decoded["transport"] == "present"
    assert decoded["network_protocol"] == network
    assert decoded["transport_protocol"] == transport
    assert decoded["source_port"] == transport_layer.sport
    assert decoded["destination_port"] == transport_layer.dport
    if network == "ipv4":
        assert decoded["ipv4_ttl"] == layer.ttl
        assert decoded["ipv4_dscp"] == layer.tos >> 2
    else:
        assert decoded["ipv6_hop_limit"] == layer.hlim
        assert decoded["ipv6_traffic_class"] == layer.tc
    if transport == "udp":
        assert decoded["udp_length"] == transport_layer.len

    actual = bytes.fromhex(zig("mutate", original))
    expected = Ether(original)
    if network == "ipv4":
        expected[IP].tos = (7 << 2) | (expected[IP].tos & 3)
        expected[IP].ttl = 31
        expected[IP].src = "203.0.113.9"
        expected[IP].dst = "203.0.113.10"
        del expected[IP].chksum
    else:
        expected[IPv6].tc = 0xAB
        expected[IPv6].hlim = 33
        expected[IPv6].src = "2001:db8::9"
        expected[IPv6].dst = "2001:db8::a"
    expected_transport = expected[UDP] if transport == "udp" else expected[TCP]
    expected_transport.sport = 9999
    expected_transport.dport = 53
    if transport == "tcp":
        expected_transport.flags = 0x12
    del expected_transport.chksum
    expected_bytes = bytes(expected)
    assert actual == expected_bytes, f"{name}: final bytes differ"
    assert actual[-4:] == original[-4:], f"{name}: payload bytes changed"
    assert actual != original, f"{name}: expected changed header bytes"
    validated = Ether(actual)
    if network == "ipv4":
        assert IP(bytes(validated[IP])).chksum == validated[IP].chksum
    print(f"{name}: decoded fields, lengths, checksums, changed and unchanged bytes match")


def compare_fragment_absent(name: str, packet, network: str) -> None:
    decoded = json.loads(zig("parse", bytes(packet)))
    assert decoded["ethernet"] == "present"
    assert decoded["network"] == "present"
    assert decoded["network_protocol"] == network
    assert decoded["transport"] == "absent"
    assert decoded["transport_protocol"] == "none"
    assert decoded["non_initial_fragment"] is True
    assert decoded["incomplete_fragment"] is True
    print(f"{name}: non-initial fragment exposes no transport fields")


def compare_initial_udp_fragment(name: str, packet, network: str) -> None:
    original = bytes(packet)
    decoded = json.loads(zig("parse", original))
    reparsed = Ether(original)
    udp = reparsed[UDP]
    assert decoded["ethernet"] == "present"
    assert decoded["network"] == "present"
    assert decoded["network_protocol"] == network
    assert decoded["transport"] == "present"
    assert decoded["transport_protocol"] == "udp"
    assert decoded["non_initial_fragment"] is False
    assert decoded["incomplete_fragment"] is True
    assert decoded["source_port"] == udp.sport
    assert decoded["destination_port"] == udp.dport
    assert decoded["udp_length"] == udp.len
    assert udp.len > 8
    print(f"{name}: initial fragment exposes the complete local UDP header")


def main() -> None:
    if scapy.__version__ != "2.7.0":
        raise SystemExit(f"Scapy must be exactly 2.7.0, found {scapy.__version__}")
    compare(
        "ipv4-udp",
        Ether(**TEST_ETHER)/IP(src="192.0.2.1", dst="198.51.100.2", ttl=64, tos=0xB8)/
        UDP(sport=4660, dport=22136)/Raw(b"abcd"),
        "ipv4", "udp",
    )
    compare(
        "ipv4-tcp",
        Ether(**TEST_ETHER)/IP(src="192.0.2.3", dst="198.51.100.4", ttl=63)/
        TCP(sport=1234, dport=443, flags="A")/Raw(b"abcd"),
        "ipv4", "tcp",
    )
    compare(
        "ipv6-udp",
        Ether(**TEST_ETHER)/IPv6(src="2001:db8::1", dst="2001:db8::2", hlim=55, tc=0x22)/
        UDP(sport=4000, dport=5000)/Raw(b"abcd"),
        "ipv6", "udp",
    )
    compare(
        "ipv6-tcp-odd",
        Ether(**TEST_ETHER)/IPv6(src="2001:db8::3", dst="2001:db8::4", hlim=54, tc=0x33)/
        TCP(sport=1234, dport=443, flags="A")/Raw(b"abcde"),
        "ipv6", "tcp",
    )
    compare(
        "vlan-ipv4-udp",
        Ether(**TEST_ETHER)/Dot1Q(vlan=7)/
        IP(src="192.0.2.5", dst="198.51.100.6", ttl=62)/
        UDP(sport=1234, dport=5353)/Raw(b"abcde"),
        "ipv4", "udp",
    )
    compare(
        "ipv4-options-tcp",
        Ether(**TEST_ETHER)/
        IP(src="192.0.2.7", dst="198.51.100.8", ttl=61,
           options=[IPOption_NOP(), IPOption_NOP(), IPOption_NOP(), IPOption_NOP()])/
        TCP(sport=2222, dport=80, flags="PA")/Raw(b"abcde"),
        "ipv4", "tcp",
    )
    compare(
        "ipv6-extension-udp",
        Ether(**TEST_ETHER)/IPv6(src="2001:db8::5", dst="2001:db8::6", hlim=53)/
        IPv6ExtHdrHopByHop(options=PadN(optdata=b"\x00\x00\x00\x00"))/
        UDP(sport=6000, dport=7000)/Raw(b"abcde"),
        "ipv6", "udp",
    )
    padded = bytes(
        Ether(**TEST_ETHER)/IP(src="192.0.2.9", dst="198.51.100.10", ttl=60)/
        UDP(sport=8000, dport=9000)/Raw(b"abcde")
    ) + b"\xde\xad\xbe\xef"
    compare("padded-ipv4-udp", Ether(padded), "ipv4", "udp")
    compare(
        "ipv4-udp-zero",
        Ether(**TEST_ETHER)/IP(src="192.0.2.11", dst="198.51.100.12", ttl=59)/
        UDP(sport=1111, dport=2222, chksum=0)/Raw(b"abcde"),
        "ipv4", "udp",
    )
    compare(
        "ipv6-udp-zero",
        Ether(**TEST_ETHER)/IPv6(src="2001:db8::7", dst="2001:db8::8", hlim=52)/
        UDP(sport=3333, dport=4444, chksum=0)/Raw(b"abcde"),
        "ipv6", "udp",
    )
    compare_fragment_absent(
        "ipv4-noninitial-fragment",
        Ether(**TEST_ETHER)/IP(src="192.0.2.13", dst="198.51.100.14", proto=17, frag=1)/
        Raw(b"abcdefgh"),
        "ipv4",
    )
    compare_fragment_absent(
        "ipv6-noninitial-fragment",
        Ether(**TEST_ETHER)/IPv6(src="2001:db8::b", dst="2001:db8::c")/
        IPv6ExtHdrFragment(nh=17, offset=1)/Raw(b"abcdefgh"),
        "ipv6",
    )
    compare_initial_udp_fragment(
        "ipv4-initial-udp-fragment",
        Ether(**TEST_ETHER)/
        IP(src="192.0.2.15", dst="198.51.100.16", flags="MF", proto=17)/
        UDP(sport=1234, dport=4321, len=12, chksum=0),
        "ipv4",
    )
    compare_initial_udp_fragment(
        "ipv6-initial-udp-fragment",
        Ether(**TEST_ETHER)/
        IPv6(src="2001:db8::d", dst="2001:db8::e", plen=16, nh=44)/
        IPv6ExtHdrFragment(nh=17, offset=0, m=1, id=1)/
        UDP(sport=1234, dport=4321, len=12, chksum=0),
        "ipv6",
    )
    print("Scapy 2.7.0 M2 differential passed")


if __name__ == "__main__":
    main()
