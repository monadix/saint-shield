#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

# Preserve the independently invocable predecessor gate, including all three
# x86 modes, ReleaseSafe AArch64, DPDK virtual/no-huge smoke, docs, and schemas.
sh tools/m0/ci.sh

zig build coverage
zig build coverage-self-test
zig build version-consistency
zig build pcap-fuzz-smoke
zig build -Doptimize=ReleaseFast m1-bench
zig build schemas
zig build docs-check

printf '%s\n' "complete cumulative M1 hardware-free CI gate passed"
