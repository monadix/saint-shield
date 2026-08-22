#!/usr/bin/env python3
"""Generate or validate source-bound synthetic M3 dispatch evidence."""

from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import json
import math
import pathlib
import platform
import re
import statistics
import subprocess
import tempfile
from typing import Any


ROOT = pathlib.Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "bench/examples/benchmark.m3.json"
SCHEMA = ROOT / "bench/schemas/m3-benchmark-result.schema.json"
ENVIRONMENT = "bench/examples/environment.m0v.json"
SOURCES = [
    "bench/micro/m3_static_pipeline.zig",
    "bench/micro/cycle_counter.c",
    "tools/m3/benchmark-evidence.py",
    "tools/m3/benchmark-gate.py",
    "tools/m3/ci.sh",
    "src/root.zig",
    "src/foundation/root.zig",
    "src/packet/root.zig",
    "src/processor/root.zig",
    "src/internal/processor_invocation.zig",
    "src/pipeline/root.zig",
    "build.zig",
]
LINE = re.compile(
    r"run_id=(?P<run>\d+) batch=(?P<batch>\d+) sample=(?P<sample>\d+) "
    r"order=(?P<order>\d+) variant=(?P<variant>[a-z0-9_]+) "
    r"elapsed_ns=(?P<elapsed>\d+) cycles=(?P<cycles>\d+) "
    r"ns_per_packet=(?P<ns>[0-9.]+) cycles_per_packet=(?P<cpp>[0-9.]+) "
    r"packet_rate=(?P<pps>[0-9.]+)"
)
SETTINGS = re.compile(r"settings run_id=(?P<run>\d+) samples=(?P<samples>\d+)")
VARIANTS = ["direct0", "direct1", "direct2", "direct4", "direct8", "terminal4", "monolith", "batch_vtable"]
BATCHES = [32, 64]
INDEPENDENT_RUNS = 7
SAMPLES_PER_RUN = 5
SAMPLE_COUNT = INDEPENDENT_RUNS * SAMPLES_PER_RUN
THRESHOLD = 0.95
NS_PER_PACKET_ABS_TOLERANCE = 0.00000051
CYCLES_PER_PACKET_ABS_TOLERANCE = 0.00000051
PACKET_RATE_ABS_TOLERANCE = 0.00051
DIAGNOSTIC_CONTROLS = {
    "variants": ["monolith", "batch_vtable"],
    "classification": "non-comparable-diagnostic-only",
    "used_for_acceptance": False,
    "used_for_reversal_or_decision": False,
}
GENERATION_INPUT = {
    "batches": BATCHES,
    "independent_runs": INDEPENDENT_RUNS,
    "measurement_iterations": 2000,
    "samples_per_run": SAMPLES_PER_RUN,
    "metric_recomputation": {
        "cycles_per_packet_abs_tolerance": CYCLES_PER_PACKET_ABS_TOLERANCE,
        "ns_per_packet_abs_tolerance": NS_PER_PACKET_ABS_TOLERANCE,
        "packet_rate_abs_tolerance": PACKET_RATE_ABS_TOLERANCE,
        "packet_count": "batch_size * measurement_iterations",
    },
    "diagnostic_controls": DIAGNOSTIC_CONTROLS,
    "variants": VARIANTS,
    "warmup_iterations": 200,
}


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def object_bytes(commit: str, path: str) -> bytes:
    return subprocess.check_output(["git", "show", f"{commit}:{path}"], cwd=ROOT)


def generation_digest() -> str:
    encoded = json.dumps(GENERATION_INPUT, sort_keys=True, separators=(",", ":")).encode()
    return digest_bytes(encoded)


def parse_raw(text: str) -> dict[tuple[int, int, str], list[dict[str, float | int]]]:
    settings = [(int(match["run"]), int(match["samples"])) for match in SETTINGS.finditer(text)]
    if settings != [(run, SAMPLES_PER_RUN) for run in range(1, INDEPENDENT_RUNS + 1)]:
        raise ValueError("benchmark must contain seven ordered independent launch settings")
    grouped: dict[tuple[int, int, str], list[dict[str, float | int]]] = {}
    sample_orders: dict[tuple[int, int, int], list[tuple[int, str]]] = {}
    for match in LINE.finditer(text):
        run_id = int(match["run"])
        batch = int(match["batch"])
        sample = int(match["sample"])
        elapsed_ns = int(match["elapsed"])
        cycles = int(match["cycles"])
        if elapsed_ns <= 0 or cycles <= 0:
            raise ValueError("raw elapsed_ns and cycles must be positive")
        packet_count = batch * GENERATION_INPUT["measurement_iterations"]
        expected_ns = elapsed_ns / packet_count
        expected_cpp = cycles / packet_count
        expected_pps = packet_count * 1_000_000_000.0 / elapsed_ns
        reported_ns = float(match["ns"])
        reported_cpp = float(match["cpp"])
        reported_pps = float(match["pps"])
        if not math.isclose(reported_ns, expected_ns, rel_tol=0, abs_tol=NS_PER_PACKET_ABS_TOLERANCE):
            raise ValueError("ns_per_packet is inconsistent with elapsed_ns, batch, and measurement iterations")
        if not math.isclose(reported_cpp, expected_cpp, rel_tol=0, abs_tol=CYCLES_PER_PACKET_ABS_TOLERANCE):
            raise ValueError("cycles_per_packet is inconsistent with cycles, batch, and measurement iterations")
        if not math.isclose(reported_pps, expected_pps, rel_tol=0, abs_tol=PACKET_RATE_ABS_TOLERANCE):
            raise ValueError("packet_rate is inconsistent with elapsed_ns, batch, and measurement iterations")
        item: dict[str, float | int] = {
            "run_id": run_id,
            "sample": sample,
            "order": int(match["order"]),
            "elapsed_ns": elapsed_ns,
            "cycles": cycles,
            "ns_per_packet": reported_ns,
            "cycles_per_packet": reported_cpp,
            "packet_rate": reported_pps,
        }
        variant = match["variant"]
        grouped.setdefault((run_id, batch, variant), []).append(item)
        sample_orders.setdefault((run_id, batch, sample), []).append((int(match["order"]), variant))
    expected = {
        (run, batch, variant)
        for run in range(1, INDEPENDENT_RUNS + 1)
        for batch in BATCHES
        for variant in VARIANTS
    }
    if set(grouped) != expected:
        raise ValueError(f"benchmark variant/run mismatch: {sorted(set(grouped) ^ expected)}")
    expected_sample_orders = {
        (run, batch, sample)
        for run in range(1, INDEPENDENT_RUNS + 1)
        for batch in BATCHES
        for sample in range(1, SAMPLES_PER_RUN + 1)
    }
    if set(sample_orders) != expected_sample_orders:
        raise ValueError("benchmark run/batch/sample order groups are incomplete")
    for key, values in sample_orders.items():
        if sorted(order for order, _ in values) != list(range(1, len(VARIANTS) + 1)):
            raise ValueError(f"{key}: order must be a complete unique variant permutation")
        if {variant for _, variant in values} != set(VARIANTS) or len(values) != len(VARIANTS):
            raise ValueError(f"{key}: variants must form one complete order permutation")
    for key, values in grouped.items():
        if len(values) != SAMPLES_PER_RUN:
            raise ValueError(f"{key}: expected {SAMPLES_PER_RUN} samples, got {len(values)}")
        if sorted(int(item["sample"]) for item in values) != list(range(1, SAMPLES_PER_RUN + 1)):
            raise ValueError(f"{key}: missing or duplicate per-run sample numbers")
    return grouped


def variant_summary(variant: str, samples: list[dict[str, float | int]]) -> dict[str, Any]:
    rates = [float(item["packet_rate"]) for item in samples]
    cycles = [float(item["cycles_per_packet"]) for item in samples]
    return {
        "variant": variant,
        "samples": samples,
        "packet_rate_median": statistics.median(rates),
        "packet_rate_pstdev": statistics.pstdev(rates),
        "cycles_per_packet_median": statistics.median(cycles),
        "cycles_per_packet_pstdev": statistics.pstdev(cycles),
    }


def summarize(grouped: dict[tuple[int, int, str], list[dict[str, float | int]]]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    combined: list[dict[str, Any]] = []
    for batch in BATCHES:
        variants = [
            variant_summary(
                variant,
                [item for run in range(1, INDEPENDENT_RUNS + 1) for item in grouped[(run, batch, variant)]],
            )
            for variant in VARIANTS
        ]
        by_name = {item["variant"]: item for item in variants}
        ratio = by_name["direct4"]["packet_rate_median"] / by_name["direct0"]["packet_rate_median"]
        combined.append({
            "batch_size": batch,
            "variants": variants,
            "direct4_to_direct0_packet_rate_ratio": ratio,
            "perf_core_001_pass": ratio >= THRESHOLD,
        })
    runs: list[dict[str, Any]] = []
    for run in range(1, INDEPENDENT_RUNS + 1):
        batches: list[dict[str, Any]] = []
        for batch in BATCHES:
            variants = [variant_summary(variant, grouped[(run, batch, variant)]) for variant in VARIANTS]
            batches.append({"batch_size": batch, "variants": variants})
        runs.append({"run_id": run, "samples_per_variant": SAMPLES_PER_RUN, "batch_results": batches})
    return combined, runs


def schema_check(path: pathlib.Path) -> None:
    result = subprocess.run(
        ["check-jsonschema", "--schemafile", str(SCHEMA), str(path)],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"M3 benchmark schema failed:\n{result.stdout}{result.stderr}")


def document_for(raw: str, commit: str, source_from_worktree: bool = False) -> dict[str, Any]:
    grouped = parse_raw(raw)
    batches, runs = summarize(grouped)
    if not all(bool(item["perf_core_001_pass"]) for item in batches):
        raise ValueError("PERF-CORE-001 failed")
    tree = git("rev-parse", f"{commit}^{{tree}}")
    read_source = (lambda path: (ROOT / path).read_bytes()) if source_from_worktree else (lambda path: object_bytes(commit, path))
    sources = [{"path": path, "sha256": digest_bytes(read_source(path))} for path in SOURCES]
    environment_hash = digest_bytes(read_source(ENVIRONMENT))
    return {
        "schema": "saint-shield-bench/v1",
        "run_id": "m3-static-pipeline-dispatch",
        "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "git_commit": commit,
        "dirty": False,
        "build": {
            "zig": "0.16.0",
            "mode": "ReleaseFast",
            "target": f"{platform.machine()}-linux-{platform.release()}",
            "features": ["synthetic", "static-pipeline", "rdtscp", "monotonic-raw"],
        },
        "environment": ENVIRONMENT,
        "backend": {"name": "synthetic", "version": "m3", "mode": "host-local"},
        "application": {
            "pipeline": ["direct0", "direct1", "direct2", "direct4", "direct8"],
            "generation_digest": generation_digest(),
            "batch_max": 64,
            "resources": {
                "source_commit": commit,
                "source_tree": tree,
                "environment_sha256": environment_hash,
                "raw_output_sha256": digest_bytes(raw.encode()),
                "raw_output": raw,
                "sources": sources,
                "host_observation": {
                    "cpu_model": next((line.split(":", 1)[1].strip() for line in pathlib.Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "unknown"),
                    "kernel": platform.release(),
                    "machine": platform.machine(),
                    "ambient": "uncontrolled host-local run",
                },
            },
        },
        "traffic": {
            "generator": "deterministic-in-process-fixture",
            "frame_profile": "one-byte synthetic descriptor",
            "protocol": "synthetic",
            "flows": 1,
            "offered_pps": 0,
            "duration_s": sum(int(sample["elapsed_ns"]) for values in grouped.values() for sample in values) / 1_000_000_000,
        },
        "methodology": {
            "preflight": "clean committed ReleaseFast native tree; monotonic raw time and serialized RDTSCP; fixed warmup",
            "warmup_seconds": 0,
            "independent_run": INDEPENDENT_RUNS,
            "independent_runs": INDEPENDENT_RUNS,
            "load_order": "deterministically randomized per batch and sample in each independent launch",
            "zero_loss_search": "not-applicable",
            "timestamp_method": "CLOCK_MONOTONIC_RAW plus serialized RDTSCP",
            "timestamp_resolution_ns": 1,
            "generator_headroom_ratio": 0,
            "adapted_standards": [],
            "rejection_checks": [
                "schema-valid", "commit-tree-ancestry", "source-environment-raw-hashes",
                "generation-digest", "batch-32-and-64", "seven-independent-warmed-launches",
                "thirty-five-retained-samples-per-variant", "all-statistics-recomputed",
                "perf-core-001-at-least-0.95", "synthetic-regression-only", "not-production-capacity",
            ],
        },
        "result": {
            "rx_pps": 0, "tx_pps": 0, "loss_packets": 0,
            "latency_ns": {"p50": 0, "p99": 0, "p999": 0, "max": 0},
            "cpu": {"time_counter": "CLOCK_MONOTONIC_RAW", "cycle_counter": "RDTSCP", "serialization": "LFENCE"},
            "perf": {
                "warmup_iterations": 200,
                "measurement_iterations": 2000,
                "samples_per_run": SAMPLES_PER_RUN,
                "samples_per_variant": SAMPLE_COUNT,
                "independent_runs": INDEPENDENT_RUNS,
                "run_summaries": runs,
                "batch_results": batches,
                "metric_recomputation": GENERATION_INPUT["metric_recomputation"],
                "diagnostic_controls": DIAGNOSTIC_CONTROLS,
            },
            "memory_bytes": {"hot_path_allocations": 0},
        },
        "valid": True,
        "invalid_reason": None,
        "raw_files": SOURCES,
    }


def validate_document(
    document: dict[str, Any],
    path: pathlib.Path,
    check_schema: bool = True,
    source_from_worktree: bool = False,
) -> None:
    if check_schema:
        schema_check(path)
    if document["backend"] != {"name": "synthetic", "version": "m3", "mode": "host-local"}:
        raise ValueError("wrong backend scope")
    if document["dirty"] is not False:
        raise ValueError("dirty benchmark evidence")
    resources = document["application"]["resources"]
    commit = document["git_commit"]
    if resources["source_commit"] != commit:
        raise ValueError("source commit mismatch")
    try:
        resolved_commit = git("rev-parse", f"{commit}^{{commit}}")
        tree = git("rev-parse", f"{commit}^{{tree}}")
        subprocess.run(["git", "merge-base", "--is-ancestor", resolved_commit, "HEAD"], cwd=ROOT, check=True)
    except subprocess.CalledProcessError as error:
        raise ValueError("source commit is missing or not an ancestor of HEAD") from error
    if resolved_commit != commit or resources["source_tree"] != tree:
        raise ValueError("commit/tree binding mismatch")
    if document["application"]["generation_digest"] != generation_digest():
        raise ValueError("generation digest mismatch")
    if resources["raw_output_sha256"] != digest_bytes(resources["raw_output"].encode()):
        raise ValueError("raw output hash mismatch")
    read_source = (lambda source_path: (ROOT / source_path).read_bytes()) if source_from_worktree else (lambda source_path: object_bytes(commit, source_path))
    if resources["environment_sha256"] != digest_bytes(read_source(ENVIRONMENT)):
        raise ValueError("environment hash mismatch")
    if [item["path"] for item in resources["sources"]] != SOURCES or document["raw_files"] != SOURCES:
        raise ValueError("benchmark source list is incomplete or reordered")
    for source in resources["sources"]:
        if source["sha256"] != digest_bytes(read_source(source["path"])):
            raise ValueError(f"source hash mismatch: {source['path']}")
    grouped = parse_raw(resources["raw_output"])
    expected_batches, expected_runs = summarize(grouped)
    perf = document["result"]["perf"]
    if perf.get("metric_recomputation") != GENERATION_INPUT["metric_recomputation"]:
        raise ValueError("metric recomputation methodology or tolerances mismatch")
    if perf.get("diagnostic_controls") != DIAGNOSTIC_CONTROLS:
        raise ValueError("benchmark controls must remain non-comparable diagnostic-only data")
    if perf["independent_runs"] != INDEPENDENT_RUNS or perf["samples_per_run"] != SAMPLES_PER_RUN or perf["samples_per_variant"] != SAMPLE_COUNT:
        raise ValueError("run/sample accounting mismatch")
    if perf["run_summaries"] != expected_runs:
        raise ValueError("per-run aggregate mismatch")
    if perf["batch_results"] != expected_batches:
        raise ValueError("combined statistics, ratio, or threshold flag mismatch")


def generate(raw_path: pathlib.Path, output: pathlib.Path) -> None:
    if git("status", "--porcelain=v1", "--untracked-files=all"):
        raise SystemExit("benchmark generation requires a clean committed tree")
    raw = raw_path.read_text(encoding="utf-8")
    document = document_for(raw, git("rev-parse", "HEAD"))
    output.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    validate_document(document, output)
    for item in document["result"]["perf"]["batch_results"]:
        print(f"batch={item['batch_size']} direct4/direct0={item['direct4_to_direct0_packet_rate_ratio']:.6f} pass=true")


def synthetic_raw() -> str:
    lines: list[str] = []
    for run in range(1, INDEPENDENT_RUNS + 1):
        lines.append(f"settings run_id={run} samples={SAMPLES_PER_RUN} warmup_iterations=200 measurement_iterations=2000 seed={run} claim=synthetic-regression-not-capacity")
        for batch in BATCHES:
            for sample in range(1, SAMPLES_PER_RUN + 1):
                for order, variant in enumerate(VARIANTS, 1):
                    packet_count = batch * GENERATION_INPUT["measurement_iterations"]
                    ns_per_packet = 100 + VARIANTS.index(variant)
                    cycles_per_packet = 200 + VARIANTS.index(variant)
                    elapsed_ns = packet_count * ns_per_packet
                    cycles = packet_count * cycles_per_packet
                    pps = packet_count * 1_000_000_000.0 / elapsed_ns
                    lines.append(f"run_id={run} batch={batch} sample={sample} order={order} variant={variant} elapsed_ns={elapsed_ns} cycles={cycles} ns_per_packet={ns_per_packet:.6f} cycles_per_packet={cycles_per_packet:.6f} packet_rate={pps:.3f}")
    return "\n".join(lines) + "\n"


def mutate_raw(document: dict[str, Any], pattern: str, replacement: Any) -> None:
    resources = document["application"]["resources"]
    changed, count = re.subn(pattern, replacement, resources["raw_output"], count=1)
    if count != 1:
        raise AssertionError(f"self-test raw mutation did not match: {pattern}")
    resources["raw_output"] = changed
    resources["raw_output_sha256"] = digest_bytes(changed.encode())


def self_test() -> None:
    document = document_for(synthetic_raw(), git("rev-parse", "HEAD"), source_from_worktree=True)
    mutations = {
        "raw-hash": lambda item: item["application"]["resources"].__setitem__("raw_output_sha256", "0" * 64),
        "tree": lambda item: item["application"]["resources"].__setitem__("source_tree", "0" * 40),
        "generation": lambda item: item["application"].__setitem__("generation_digest", "0" * 64),
        "source-list": lambda item: item["application"]["resources"]["sources"].pop(),
        "median": lambda item: item["result"]["perf"]["batch_results"][0]["variants"][0].__setitem__("packet_rate_median", 1),
        "ratio": lambda item: item["result"]["perf"]["batch_results"][0].__setitem__("direct4_to_direct0_packet_rate_ratio", 99),
        "run-count": lambda item: item["result"]["perf"].__setitem__("independent_runs", 6),
        "duplicate-order": lambda item: mutate_raw(item, r"order=2 variant=direct1", "order=1 variant=direct1"),
        "inconsistent-elapsed": lambda item: mutate_raw(
            item,
            r"elapsed_ns=(\d+)",
            lambda match: f"elapsed_ns={int(match.group(1)) + 1}",
        ),
        "inconsistent-cycles": lambda item: mutate_raw(
            item,
            r"cycles=(\d+)",
            lambda match: f"cycles={int(match.group(1)) + 1}",
        ),
    }
    with tempfile.TemporaryDirectory(prefix="saint-shield-m3-evidence-self-test-") as raw_dir:
        directory = pathlib.Path(raw_dir)
        valid = directory / "valid.json"
        valid.write_text(json.dumps(document), encoding="utf-8")
        validate_document(document, valid, source_from_worktree=True)
        for name, mutate in mutations.items():
            forged = copy.deepcopy(document)
            mutate(forged)
            path = directory / f"{name}.json"
            path.write_text(json.dumps(forged), encoding="utf-8")
            try:
                validate_document(forged, path, check_schema=False, source_from_worktree=True)
            except ValueError:
                continue
            raise SystemExit(f"negative control accepted forged {name} evidence")
    print(f"M3 benchmark validator negative controls passed: {len(mutations)}")


def validate(path: pathlib.Path) -> None:
    document = json.loads(path.read_text(encoding="utf-8"))
    try:
        validate_document(document, path)
    except (KeyError, TypeError, ValueError) as error:
        raise SystemExit(f"M3 retained benchmark evidence failed: {error}") from error
    print("M3 retained benchmark evidence passed")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--generate", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path, default=EVIDENCE)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--validate", type=pathlib.Path, default=EVIDENCE)
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.generate:
        generate(args.generate, args.output)
    else:
        validate(args.validate)


if __name__ == "__main__":
    main()
