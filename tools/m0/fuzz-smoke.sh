#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-d012.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

sanitizer_target="$work_dir/d012-sanitizer-fixture"
zig_target="$work_dir/d012-zig-fixture"
afl-clang-fast -O1 -g -fno-omit-frame-pointer \
    -fsanitize=address,undefined \
    test/fuzz/d012_fixture.c -o "$sanitizer_target"
zig build-obj test/fuzz/d012_zig_branch.zig -OReleaseSafe -fPIC \
    -femit-bin="$work_dir/d012-zig-branch.o"
zig cc -std=c11 -Wall -Wextra -Werror \
    test/fuzz/d012_zig_branch_main.c "$work_dir/d012-zig-branch.o" \
    -o "$zig_target"

run_failure() {
    input=$1
    log=$2
    if ASAN_OPTIONS=abort_on_error=1:symbolize=0 \
        "$sanitizer_target" "$input" >"$log" 2>&1; then
        printf '%s\n' "expected sanitizer failure did not occur" >&2
        return 1
    fi
    if ! grep -q "AddressSanitizer: heap-buffer-overflow" "$log"; then
        printf '%s\n' "saved input failed without the expected ASan report" >&2
        return 1
    fi
}

run_failure test/fuzz/reproducer-d012.txt "$work_dir/reproducer-1.log"
run_failure test/fuzz/reproducer-d012.txt "$work_dir/reproducer-2.log"
printf '%s\n' "saved reproducer deterministically triggered ASan twice"

afl-showmap -Q -q -e -o "$work_dir/zig-seed.map" -- \
    "$zig_target" test/fuzz/corpus/seed/minimal.txt
afl-showmap -Q -q -e -o "$work_dir/zig-probe.map" -- \
    "$zig_target" test/fuzz/zig-branch-probe-d012.txt
if cmp -s "$work_dir/zig-seed.map" "$work_dir/zig-probe.map"; then
    printf '%s\n' "equal-length safe inputs did not change the Zig coverage map" >&2
    exit 1
fi
printf '%s\n' "AFL++ QEMU maps observed distinct branches inside Zig 0.16.0 code"

set +e
afl-showmap -Q -q -t 100 -o "$work_dir/timeout.map" -- \
    "$zig_target" test/fuzz/timeout-d012.txt
timeout_status=$?
set -e
if [ "$timeout_status" -ne 1 ]; then
    printf '%s\n' "expected AFL++ timeout status 1, got $timeout_status" >&2
    exit 1
fi
printf '%s\n' "AFL++ classified the Zig HANG branch as timeout status 1 at 100 ms"

mkdir -p "$work_dir/findings"
AFL_BENCH_UNTIL_CRASH=1 \
AFL_I_DONT_CARE_ABOUT_MISSING_CRASHES=1 \
AFL_NO_UI=1 \
AFL_SKIP_CPUFREQ=1 \
timeout 30 afl-fuzz \
    -Q \
    -i test/fuzz/corpus/seed \
    -o "$work_dir/findings" \
    -x test/fuzz/d012.dict \
    -m none -t 500 \
    -- "$zig_target" @@

set -- "$work_dir"/findings/default/crashes/id:*
if [ ! -f "$1" ]; then
    printf '%s\n' "AFL++ did not save a crash within the bounded smoke run" >&2
    exit 1
fi
set +e
"$zig_target" "$1" >"$work_dir/zig-crash.log" 2>&1
zig_crash_status=$?
set -e
if [ "$zig_crash_status" -ne 134 ]; then
    printf '%s\n' "saved Zig crash replay returned $zig_crash_status, expected SIGABRT status 134" >&2
    exit 1
fi
run_failure "$1" "$work_dir/afl-crash-asan.log"
printf '%s\n' "AFL++ saved and replayed a Zig-branch crash; the same input was ASan-confirmed"
afl-fuzz -h 2>&1 | sed -n '1p'
