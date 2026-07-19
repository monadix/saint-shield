#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

nix flake check --no-build --all-systems

cache_root=$(mktemp -d "${TMPDIR:-/tmp}/saint-zig-cache.XXXXXX")
trap 'rm -rf "$cache_root"' EXIT HUP INT TERM
export ZIG_LOCAL_CACHE_DIR="$cache_root/local"
export ZIG_GLOBAL_CACHE_DIR="$cache_root/global"

zig fmt --check build.zig src examples test bench
zig build -Doptimize=Debug
zig build -Doptimize=Debug test
zig build -Doptimize=ReleaseSafe
zig build -Doptimize=ReleaseSafe test
zig build -Doptimize=ReleaseFast
zig build -Doptimize=ReleaseFast test
zig build -Doptimize=ReleaseSafe cross-aarch64
zig build -Doptimize=ReleaseSafe docs
zig build -Doptimize=ReleaseSafe example
zig build -Doptimize=ReleaseFast bench
zig build schemas
zig build integrity
zig build docs-check
zig build dpdk-smoke
zig build fuzz-smoke
printf '%s\n' "complete M0-V hardware-free CI gate passed"
