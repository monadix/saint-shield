#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

# Preserve every independently invocable predecessor gate before adding M3.
zig build ci-m2

# Root-module and dedicated M3 semantics must hold in every required mode.
zig build test
zig build -Doptimize=ReleaseSafe test
zig build -Doptimize=ReleaseFast test
zig build m3-test
zig build -Doptimize=ReleaseSafe m3-test
zig build -Doptimize=ReleaseFast m3-test

zig build m3-compile-fail
zig build m3-example
zig build m3-cross-aarch64
zig build m3-coverage
zig build m3-version-consistency
zig build m3-bench-gate
zig build m3-bench-evidence
zig build schemas
zig build docs-check

printf '%s\n' "complete cumulative M3 hardware-free CI gate passed"
