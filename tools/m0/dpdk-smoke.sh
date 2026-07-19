#!/bin/sh
set -eu

: "${DPDK_PREFIX:?enter the workspace with nix develop}"

output_dir="${ZIG_LOCAL_CACHE_DIR:-.zig-cache}/m0v-dpdk"
mkdir -p "$output_dir"

cflags=$(pkg-config --cflags libdpdk)
libs=$(pkg-config --libs libdpdk)
pmd_dir="$DPDK_PREFIX/lib/dpdk/pmds-26.0"

# Zig sees only the asserted narrow layout; Nix's C wrapper links the actual
# DPDK probe so GNU linker scripts and transitive Nix dependencies are honored.
zig build-exe test/dpdk/abi_smoke.zig -Isrc/io/dpdk \
    -ODebug -femit-bin="$output_dir/zig-abi-smoke"
# Intentional word splitting: pkg-config returns compiler/linker argument lists.
# shellcheck disable=SC2086
cc -std=c11 -Wall -Wextra -Werror -Isrc/io/dpdk $cflags \
    src/io/dpdk/compat.c test/dpdk/dpdk_smoke_main.c \
    $libs -L"$pmd_dir" -lrte_net_ring -o "$output_dir/dpdk-smoke"

zig_report=$("$output_dir/zig-abi-smoke" 2>&1)
dpdk_report=$(LD_LIBRARY_PATH="$DPDK_PREFIX/lib:$pmd_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    "$output_dir/dpdk-smoke")
c_report=$(printf '%s\n' "$dpdk_report" | sed -n '/^M0V_ABI /p')

printf '%s\n' "$zig_report"
printf '%s\n' "$dpdk_report"
if [ "$zig_report" != "$c_report" ]; then
    printf '%s\n' "Zig/C DPDK ABI reports differ" >&2
    exit 1
fi
printf '%s\n' "Zig/C DPDK ABI reports match"
