#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-schemas.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM

check-jsonschema --check-metaschema bench/schemas/benchmark-result.schema.json
check-jsonschema --check-metaschema bench/schemas/environment-manifest.schema.json
check-jsonschema --schemafile bench/schemas/benchmark-result.schema.json \
    bench/examples/benchmark.m0v.json
check-jsonschema --schemafile bench/schemas/environment-manifest.schema.json \
    bench/examples/environment.m0v.json

jq '.runtime.backend = {"name":"dpdk","version":"26.03","mode":"ring-pmd"}' \
    bench/examples/environment.m0v.json >"$work_dir/wrong-dpdk-environment.json"
if check-jsonschema --schemafile bench/schemas/environment-manifest.schema.json \
    "$work_dir/wrong-dpdk-environment.json" >/dev/null 2>&1; then
    printf '%s\n' "environment schema accepted a non-pinned DPDK backend" >&2
    exit 1
fi

jq '.runtime.backend = {"name":"af_xdp","version":"libxdp-1.5","mode":"zero-copy"} |
    .software.dpdk = null | .software.libbpf = "1.6" | .software.libxdp = "1.5"' \
    bench/examples/environment.m0v.json >"$work_dir/af-xdp-environment.json"
check-jsonschema --schemafile bench/schemas/environment-manifest.schema.json \
    "$work_dir/af-xdp-environment.json"

jq '.software.libxdp = null' "$work_dir/af-xdp-environment.json" \
    >"$work_dir/invalid-af-xdp-environment.json"
if check-jsonschema --schemafile bench/schemas/environment-manifest.schema.json \
    "$work_dir/invalid-af-xdp-environment.json" >/dev/null 2>&1; then
    printf '%s\n' "environment schema accepted AF_XDP without libxdp metadata" >&2
    exit 1
fi

jq '.backend = {"name":"synthetic","version":"25.11.2","mode":"host-local"}' \
    bench/examples/benchmark.m0v.json >"$work_dir/wrong-synthetic-benchmark.json"
if check-jsonschema --schemafile bench/schemas/benchmark-result.schema.json \
    "$work_dir/wrong-synthetic-benchmark.json" >/dev/null 2>&1; then
    printf '%s\n' "benchmark schema accepted a wrong synthetic backend version" >&2
    exit 1
fi

jq 'del(.methodology)' bench/examples/benchmark.m0v.json \
    >"$work_dir/missing-methodology.json"
if check-jsonschema --schemafile bench/schemas/benchmark-result.schema.json \
    "$work_dir/missing-methodology.json" >/dev/null 2>&1; then
    printf '%s\n' "benchmark schema accepted missing methodology evidence" >&2
    exit 1
fi

printf '%s\n' "benchmark/environment examples and negative schema conditions passed"
