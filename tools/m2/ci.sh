#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

# Preserve the independently invocable M1 gate and its M0-V predecessor.
zig build ci-m1

zig build m2-coverage
zig build m2-version-consistency
zig build m2-scapy-differential
zig build m2-parser-fuzz-smoke
zig build m2-finalizer-fuzz-smoke
zig build m2-fuzz-evidence
zig build -Doptimize=ReleaseFast m2-bench
zig build schemas
zig build docs-check

printf '%s\n' "complete cumulative M2 hardware-free CI gate passed"
