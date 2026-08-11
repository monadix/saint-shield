#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

if [ "$#" -lt 1 ]; then
    printf '%s\n' "usage: $0 parser|finalizer [--reproduce RAW_INPUT|--summary JSON]" >&2
    exit 2
fi
target=$1
shift
case "$target" in
    parser)
        zig_source=test/fuzz/m2_parser_fuzz.zig
        export_name=saint_m2_parser_fuzz
        negative_export_name=saint_m2_parser_fuzz_negative_control
        corpus_source=test/fuzz/m2-parser-corpus
        dictionary=test/fuzz/m2-parser.dict
        negative_seed=ethernet-ipv4-udp
        ;;
    finalizer)
        zig_source=test/fuzz/m2_finalizer_fuzz.zig
        export_name=saint_m2_finalizer_fuzz
        negative_export_name=saint_m2_finalizer_fuzz_negative_control
        corpus_source=test/fuzz/m2-finalizer-corpus
        dictionary=test/fuzz/m2-finalizer.dict
        negative_seed=ipv4-udp-edit
        ;;
    *)
        printf '%s\n' "unknown M2 fuzz target: $target" >&2
        exit 2
        ;;
esac

mode=smoke
reproducer=
summary_output=
if [ "$#" -ne 0 ]; then
    if [ "$#" -ne 2 ]; then
        printf '%s\n' "usage: $0 parser|finalizer [--reproduce RAW_INPUT|--summary JSON]" >&2
        exit 2
    fi
    case "$1" in
        --reproduce)
            mode=reproduce
            reproducer=$2
            ;;
        --summary)
            summary_output=$2
            ;;
        *)
            printf '%s\n' "usage: $0 parser|finalizer [--reproduce RAW_INPUT|--summary JSON]" >&2
            exit 2
            ;;
    esac
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-m2-${target}-fuzz.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

zig build-obj -OReleaseSafe -fPIC -mcpu=baseline --dep saint_shield \
    -Mroot="$zig_source" -OReleaseSafe \
    -Msaint_shield=src/root.zig \
    -femit-bin="$work_dir/target.o"
zig cc -mcpu=baseline -std=c11 -Wall -Wextra -Werror \
    "-DSAINT_FUZZ_FUNCTION=$export_name" \
    "-DSAINT_FUZZ_NEGATIVE_FUNCTION=$negative_export_name" \
    test/fuzz/m2_fuzz_main.c "$work_dir/target.o" \
    -o "$work_dir/target"

if [ "$mode" = reproduce ]; then
    SAINT_M2_REPRODUCE=1 "$work_dir/target" "$reproducer"
    exit 0
fi

python3 tools/m2/decode-fuzz-seeds.py "$corpus_source" "$work_dir/corpus"
for input in "$work_dir"/corpus/*; do
    first=$(SAINT_M2_REPRODUCE=1 "$work_dir/target" "$input")
    second=$(SAINT_M2_REPRODUCE=1 "$work_dir/target" "$input")
    if [ "$first" != "$second" ]; then
        printf 'nondeterministic %s replay: seed=%s\n' "$target" "$input" >&2
        exit 1
    fi
done

negative_input="$work_dir/corpus/$negative_seed"
test -f "$negative_input"
set +e
negative_output=$(SAINT_M2_NEGATIVE_CONTROL=1 SAINT_M2_REPRODUCE=1 \
    "$work_dir/target" "$negative_input" 2>&1)
negative_status=$?
set -e
if [ "$negative_status" -ne 3 ] || [ "$negative_output" != "M2 bounded outcome: 6" ]; then
    printf 'M2 fuzz Zig semantic negative control mismatch: status=%s output=%s\n' \
        "$negative_status" "$negative_output" >&2
    exit 1
fi

afl-showmap -Q -e -q -o "$work_dir/coverage.map" -- \
    "$work_dir/target" "$work_dir/corpus/$(find "$work_dir/corpus" -type f -printf '%f\n' | sort | head -1)"
test -s "$work_dir/coverage.map"

mkdir -p "$work_dir/findings"
AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
AFL_NO_UI=1 \
AFL_SKIP_CPUFREQ=1 \
timeout 15 afl-fuzz -Q -V 2 \
    -i "$work_dir/corpus" -o "$work_dir/findings" \
    -x "$dictionary" -m none -t 500 -- "$work_dir/target" @@

failure=$(find "$work_dir/findings" \( -path '*/crashes/id:*' -o -path '*/hangs/id:*' \) -type f | sort | head -1)
if [ -n "$failure" ]; then
    minimized="$work_dir/minimized"
    afl-tmin -Q -i "$failure" -o "$minimized" -m none -t 500 -- "$work_dir/target" @@ >/dev/null
    printf 'M2 %s fuzz failure seed/path: %s\n' "$target" "$failure" >&2
    printf '%s' "minimized trace hex: " >&2
    od -An -tx1 -v "$minimized" | tr -d ' \n' >&2
    printf '\nreproduce: %s %s --reproduce %s\n' "$0" "$target" "$minimized" >&2
    exit 1
fi
if [ -n "$summary_output" ]; then
    python3 tools/m2/write-fuzz-summary.py \
        --target "$target" \
        --corpus "$corpus_source" \
        --dictionary "$dictionary" \
        --coverage-map "$work_dir/coverage.map" \
        --output "$summary_output"
    printf 'retained M2 %s fuzz summary: %s\n' "$target" "$summary_output"
fi
printf 'bounded M2 %s AFL++ smoke passed (seed corpus, 500 ms timeout, reproducer workflow)\n' "$target"
