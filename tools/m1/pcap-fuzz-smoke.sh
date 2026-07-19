#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

mode=smoke
reproducer=
if [ "$#" -ne 0 ]; then
    if [ "$#" -ne 2 ] || [ "$1" != "--reproduce" ]; then
        printf '%s\n' "usage: $0 [--reproduce RAW_INPUT]" >&2
        exit 2
    fi
    mode=reproduce
    reproducer=$2
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-pcap-fuzz.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

zig build-obj -OReleaseSafe -fPIC --dep pcap \
    -Mroot=test/fuzz/pcap_fuzz.zig -OReleaseSafe \
    -Mpcap=src/io/pcap/root.zig \
    -femit-bin="$work_dir/pcap-fuzz.o"
zig cc -std=c11 -Wall -Wextra -Werror \
    test/fuzz/pcap_fuzz_main.c "$work_dir/pcap-fuzz.o" \
    -o "$work_dir/pcap-fuzz"

if [ "$mode" = reproduce ]; then
    SAINT_PCAP_REPRODUCE=1 "$work_dir/pcap-fuzz" "$reproducer"
    exit 0
fi

python3 tools/m1/decode-pcap-seeds.py \
    test/fuzz/pcap-corpus "$work_dir/corpus"

for input in "$work_dir"/corpus/*; do
    first=$(SAINT_PCAP_REPRODUCE=1 "$work_dir/pcap-fuzz" "$input")
    second=$(SAINT_PCAP_REPRODUCE=1 "$work_dir/pcap-fuzz" "$input")
    if [ "$first" != "$second" ]; then
        printf '%s\n' "nondeterministic replay for $input" >&2
        exit 1
    fi
    printf '%s: %s\n' "$(basename "$input")" "$first"
done

afl-showmap -Q -q -e -o "$work_dir/little.map" -- \
    "$work_dir/pcap-fuzz" "$work_dir/corpus/little-micro-record"
afl-showmap -Q -q -e -o "$work_dir/big.map" -- \
    "$work_dir/pcap-fuzz" "$work_dir/corpus/big-nano-record"
if cmp -s "$work_dir/little.map" "$work_dir/big.map"; then
    printf '%s\n' "PCAP endian/resolution seeds produced identical Zig coverage" >&2
    exit 1
fi

mkdir -p "$work_dir/findings"
AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
AFL_NO_UI=1 \
AFL_SKIP_CPUFREQ=1 \
timeout 15 afl-fuzz \
    -Q \
    -V 2 \
    -i "$work_dir/corpus" \
    -o "$work_dir/findings" \
    -x test/fuzz/pcap.dict \
    -m none -t 500 \
    -- "$work_dir/pcap-fuzz" @@

if find "$work_dir/findings" -path '*/crashes/id:*' -type f | grep -q .; then
    printf '%s\n' "PCAP fuzz smoke found a crash" >&2
    exit 1
fi
if find "$work_dir/findings" -path '*/hangs/id:*' -type f | grep -q .; then
    printf '%s\n' "PCAP fuzz smoke found a hang" >&2
    exit 1
fi
printf '%s\n' "bounded classic-PCAP replay and AFL++ smoke passed"
