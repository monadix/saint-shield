#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Capture or validate source-bound M2 cycle-regression evidence."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import platform
import re
import statistics
import subprocess
import time


ROOT = Path(__file__).resolve().parents[2]
ARTIFACT = ROOT / "bench/examples/benchmark.m2.json"
ENVIRONMENT = ROOT / "bench/examples/environment.m0v.json"
BATCH_SIZES = [1, 4, 8, 16, 32, 64]
ITERATIONS = 2_000
WARMUP_ITERATIONS = 200
REPETITIONS = 5
SOURCE_PATHS = [
    ROOT / "bench/micro/m2_parser_disposition.zig",
    ROOT / "bench/micro/cycle_counter.c",
    ROOT / "tools/m2/benchmark-evidence.py",
    ROOT / "build.zig",
]
FINAL_GATE_COMMIT = "bf76210a318f15f6ab71e6ffcf1a20f1c0bc9277"
FINAL_GATE_TREE = "b2609e0020b8a33147ee19e563c7f159039c0beb"
ACCEPTED_M2_COMMIT = "aaa406adde9cc6663b691599c5ebfbc5c8d936b6"
ACCEPTED_M2_TREE = "a0b8d91e166cc42ea9fda8eb73b60749e43d9b42"
EXPECTED_EVOLVED_PATHS = {"build.zig", "tools/m2/benchmark-evidence.py"}
SETTINGS_PATTERN = re.compile(
    r"^settings iterations=(\d+) warmup_iterations=(\d+) repetitions=(\d+) "
    r"claim=synthetic-regression-not-capacity$"
)
SAMPLE_PATTERN = re.compile(
    r"^batch=(\d+) run=(\d+) parser_cycles_per_packet=([0-9]+(?:\.[0-9]+)?) "
    r"noop_disposition_cycles_per_packet=([0-9]+(?:\.[0-9]+)?)$"
)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def git_blob_digest(commit: str, path: str) -> str:
    result = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return digest_bytes(result.stdout)


def is_ancestor(older: str, newer: str) -> bool:
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", older, newer],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def validate_squash_bridge(source_commit: str, source_tree: str) -> None:
    if git("rev-parse", f"{source_commit}^{{tree}}") != source_tree:
        raise SystemExit("M2 benchmark commit/tree binding is invalid")
    if git("rev-parse", f"{FINAL_GATE_COMMIT}^{{tree}}") != FINAL_GATE_TREE:
        raise SystemExit("M2 pre-squash final-gate anchor is invalid")
    if not is_ancestor(source_commit, FINAL_GATE_COMMIT):
        raise SystemExit("M2 benchmark source is not in the accepted pre-squash history")
    if git("rev-parse", f"{ACCEPTED_M2_COMMIT}^{{tree}}") != ACCEPTED_M2_TREE:
        raise SystemExit("M2 accepted squash anchor is invalid")
    if not is_ancestor(ACCEPTED_M2_COMMIT, "HEAD"):
        raise SystemExit("M2 accepted squash is not an ancestor of HEAD")


def fixture_bytes() -> bytes:
    data = bytearray(46)
    data[12:14] = bytes((0x08, 0x00))
    data[14] = 0x45
    data[16:18] = bytes((0, 32))
    data[22] = 64
    data[23] = 17
    data[26:30] = bytes((192, 0, 2, 1))
    data[30:34] = bytes((198, 51, 100, 2))
    data[34:36] = bytes((0x12, 0x34))
    data[36:38] = bytes((0x56, 0x78))
    data[38:40] = bytes((0, 12))
    data[42:46] = bytes((1, 2, 3, 4))
    return bytes(data)


def source_records() -> list[dict[str, str]]:
    return [
        {"path": str(path.relative_to(ROOT)), "sha256": digest(path)}
        for path in SOURCE_PATHS
    ]


def parse_raw(output: str) -> tuple[list[str], dict[int, list[dict[str, float | int]]]]:
    raw_lines = [line.strip() for line in output.splitlines() if line.strip()]
    settings = [match for line in raw_lines if (match := SETTINGS_PATTERN.fullmatch(line))]
    if len(settings) != 1:
        raise SystemExit("benchmark output must contain exactly one settings line")
    if tuple(map(int, settings[0].groups())) != (ITERATIONS, WARMUP_ITERATIONS, REPETITIONS):
        raise SystemExit("benchmark output settings do not match the evidence contract")

    samples: dict[int, list[dict[str, float | int]]] = {batch: [] for batch in BATCH_SIZES}
    for line in raw_lines:
        match = SAMPLE_PATTERN.fullmatch(line)
        if match is None:
            continue
        batch, run = map(int, match.groups()[:2])
        if batch not in samples:
            raise SystemExit(f"unexpected benchmark batch size: {batch}")
        samples[batch].append(
            {
                "run": run,
                "parser_cycles_per_packet": float(match.group(3)),
                "noop_disposition_cycles_per_packet": float(match.group(4)),
            }
        )
    for batch, batch_samples in samples.items():
        if [sample["run"] for sample in batch_samples] != list(range(1, REPETITIONS + 1)):
            raise SystemExit(f"batch {batch} does not contain the required ordered repetitions")
        if any(
            sample[metric] <= 0 or not math.isfinite(float(sample[metric]))
            for sample in batch_samples
            for metric in ("parser_cycles_per_packet", "noop_disposition_cycles_per_packet")
        ):
            raise SystemExit(f"batch {batch} contains a non-positive or non-finite sample")
    if sum(len(batch_samples) for batch_samples in samples.values()) != len(BATCH_SIZES) * REPETITIONS:
        raise SystemExit("benchmark output contains the wrong sample count")
    return raw_lines, samples


def host_cpu_model() -> str:
    cpuinfo = Path("/proc/cpuinfo")
    if cpuinfo.is_file():
        for line in cpuinfo.read_text(encoding="utf-8").splitlines():
            if line.startswith("model name") and ":" in line:
                return line.split(":", 1)[1].strip()
    return platform.processor() or "not-reported"


def capture(output_path: Path) -> None:
    if git("status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("refusing to capture benchmark evidence from a dirty source tree")
    source_commit = git("rev-parse", "HEAD")
    source_tree = git("rev-parse", "HEAD^{tree}")
    started = time.monotonic()
    run = subprocess.run(
        ["zig", "build", "-Doptimize=ReleaseFast", "m2-bench-raw"],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    duration = time.monotonic() - started
    raw_lines, samples = parse_raw(run.stdout)
    if git("status", "--porcelain", "--untracked-files=all"):
        raise SystemExit("benchmark capture changed the tracked or untracked source tree")
    if git("rev-parse", "HEAD") != source_commit or git("rev-parse", "HEAD^{tree}") != source_tree:
        raise SystemExit("benchmark source commit/tree changed during capture")

    zig_version = subprocess.run(
        ["zig", "version"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout.strip()
    zig_environment = subprocess.run(
        ["zig", "env"], check=True, text=True, stdout=subprocess.PIPE
    ).stdout
    target_match = re.search(r'^\s*\.target = "([^"]+)",$', zig_environment, re.MULTILINE)
    target = (
        target_match.group(1)
        if target_match is not None
        else f"{platform.machine()}-{platform.system().lower()}"
    )
    normalized_raw = "\n".join(raw_lines) + "\n"
    batch_results = []
    for batch in BATCH_SIZES:
        batch_samples = samples[batch]
        batch_results.append(
            {
                "batch_size": batch,
                "runs": batch_samples,
                "parser_cycles_per_packet_median": statistics.median(
                    float(sample["parser_cycles_per_packet"]) for sample in batch_samples
                ),
                "noop_disposition_cycles_per_packet_median": statistics.median(
                    float(sample["noop_disposition_cycles_per_packet"])
                    for sample in batch_samples
                ),
            }
        )

    artifact = {
        "schema": "saint-shield-bench/v1",
        "run_id": "m2-parser-disposition-cycles",
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "git_commit": source_commit,
        "dirty": False,
        "build": {
            "zig": zig_version,
            "mode": "ReleaseFast",
            "target": target,
            "features": ["synthetic", "rdtscp", "parser", "dispositions"],
        },
        "environment": str(ENVIRONMENT.relative_to(ROOT)),
        "backend": {"name": "synthetic", "version": "m2", "mode": "host-local"},
        "application": {
            "pipeline": [],
            "generation_digest": digest_bytes(fixture_bytes()),
            "batch_max": 64,
            "resources": {
                "parser_cache": "preallocated",
                "selection_words": 1,
                "source_tree": source_tree,
                "environment_sha256": digest(ENVIRONMENT),
                "fixture_sha256": digest_bytes(fixture_bytes()),
                "sources": source_records(),
                "raw_output_sha256": digest_bytes(normalized_raw.encode("utf-8")),
                "host_observation": {
                    "cpu_model": host_cpu_model(),
                    "kernel": platform.release(),
                    "machine": platform.machine(),
                    "ambient": "uncontrolled host-local run",
                },
            },
        },
        "traffic": {
            "generator": "deterministic-in-process-fixture",
            "frame_profile": "Ethernet-IPv4-UDP-46-byte",
            "protocol": "IPv4-UDP",
            "flows": 1,
            "offered_pps": 0,
            "duration_s": duration,
        },
        "methodology": {
            "preflight": "ReleaseFast native serialized RDTSCP; iteration warmup; five repeated measurement windows per batch",
            "warmup_seconds": 0,
            "independent_run": 1,
            "independent_runs": 1,
            "load_order": "batch-1-4-8-16-32-64; warmup then runs-1-through-5",
            "zero_loss_search": "not-applicable",
            "timestamp_method": "serialized-rdtscp",
            "timestamp_resolution_ns": 0,
            "generator_headroom_ratio": 0,
            "adapted_standards": [],
            "rejection_checks": [
                "schema-valid",
                "clean-commit-tree-binding",
                "source-environment-fixture-hashes",
                "all-required-batch-sizes",
                "warmup-and-five-positive-raw-samples",
                "raw-output-hash",
                "synthetic-regression-only",
                "not-production-capacity",
            ],
        },
        "result": {
            "rx_pps": 0,
            "tx_pps": 0,
            "loss_packets": 0,
            "latency_ns": {"p50": 0, "p99": 0, "p999": 0, "max": 0},
            "cpu": {"counter": "RDTSCP", "serialization": "LFENCE"},
            "perf": {
                "iterations_per_batch": ITERATIONS,
                "warmup_iterations_per_batch": WARMUP_ITERATIONS,
                "repetitions_per_batch": REPETITIONS,
                "raw_lines": raw_lines,
                "batch_results": batch_results,
            },
            "memory_bytes": {"hot_path_allocations": 0},
        },
        "valid": True,
        "invalid_reason": None,
        "raw_files": [str(path.relative_to(ROOT)) for path in SOURCE_PATHS],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(artifact, indent=2) + "\n", encoding="utf-8")
    print(
        f"wrote source-bound M2 benchmark evidence for {source_commit} "
        f"({len(BATCH_SIZES) * REPETITIONS} raw samples) to {output_path}"
    )


def validate_hash_records(records: object, source_commit: str) -> None:
    if not isinstance(records, list) or not records:
        raise SystemExit("benchmark source hash records must not be empty")
    for record in records:
        if not isinstance(record, dict):
            raise SystemExit("benchmark source hash record is malformed")
        relative = str(record.get("path", ""))
        expected = record.get("sha256")
        path = ROOT / relative
        if relative not in EXPECTED_EVOLVED_PATHS and (
            not path.is_file() or digest(path) != expected
        ):
            raise SystemExit(f"benchmark current source hash mismatch: {path}")
        if git_blob_digest(source_commit, relative) != expected:
            raise SystemExit(f"benchmark source-object hash mismatch: {relative}")
        if git_blob_digest(ACCEPTED_M2_COMMIT, relative) != expected:
            raise SystemExit(f"benchmark accepted-squash hash mismatch: {relative}")


def validate() -> None:
    artifact = json.loads(ARTIFACT.read_text(encoding="utf-8"))
    if artifact.get("schema") != "saint-shield-bench/v1" or artifact.get("dirty") is not False:
        raise SystemExit("M2 benchmark schema/dirty binding is invalid")
    commit = str(artifact.get("git_commit", ""))
    resources = artifact.get("application", {}).get("resources", {})
    source_tree = str(resources.get("source_tree", ""))
    validate_squash_bridge(commit, source_tree)
    if artifact.get("environment") != str(ENVIRONMENT.relative_to(ROOT)):
        raise SystemExit("M2 benchmark environment path is invalid")
    if resources.get("environment_sha256") != digest(ENVIRONMENT):
        raise SystemExit("M2 benchmark environment hash is invalid")
    fixture_hash = digest_bytes(fixture_bytes())
    if resources.get("fixture_sha256") != fixture_hash:
        raise SystemExit("M2 benchmark fixture hash is invalid")
    if artifact.get("application", {}).get("generation_digest") != fixture_hash:
        raise SystemExit("M2 benchmark generation digest is invalid")
    validate_hash_records(resources.get("sources"), commit)
    if artifact.get("build", {}).get("zig") != "0.16.0" or artifact.get("build", {}).get("mode") != "ReleaseFast":
        raise SystemExit("M2 benchmark build binding is invalid")
    methodology = artifact.get("methodology", {})
    required_rejections = {
        "clean-commit-tree-binding",
        "source-environment-fixture-hashes",
        "warmup-and-five-positive-raw-samples",
        "raw-output-hash",
        "synthetic-regression-only",
        "not-production-capacity",
    }
    if not required_rejections.issubset(set(methodology.get("rejection_checks", []))):
        raise SystemExit("M2 benchmark methodology does not preserve its evidence scope")

    perf = artifact.get("result", {}).get("perf", {})
    if (
        perf.get("iterations_per_batch") != ITERATIONS
        or perf.get("warmup_iterations_per_batch") != WARMUP_ITERATIONS
        or perf.get("repetitions_per_batch") != REPETITIONS
    ):
        raise SystemExit("M2 benchmark iteration/warmup/repetition settings mismatch")
    raw_lines = perf.get("raw_lines")
    if not isinstance(raw_lines, list) or not all(isinstance(line, str) for line in raw_lines):
        raise SystemExit("M2 benchmark retained raw lines are malformed")
    normalized_raw = "\n".join(raw_lines) + "\n"
    if resources.get("raw_output_sha256") != digest_bytes(normalized_raw.encode("utf-8")):
        raise SystemExit("M2 benchmark retained raw-output hash is invalid")
    _, parsed_samples = parse_raw(normalized_raw)
    batch_results = perf.get("batch_results")
    if not isinstance(batch_results, list) or [item.get("batch_size") for item in batch_results] != BATCH_SIZES:
        raise SystemExit("M2 benchmark required batch set/order is invalid")
    for result in batch_results:
        batch = result["batch_size"]
        if result.get("runs") != parsed_samples[batch]:
            raise SystemExit(f"M2 benchmark retained raw samples disagree for batch {batch}")
        parser_median = statistics.median(
            float(sample["parser_cycles_per_packet"]) for sample in parsed_samples[batch]
        )
        disposition_median = statistics.median(
            float(sample["noop_disposition_cycles_per_packet"])
            for sample in parsed_samples[batch]
        )
        if not math.isclose(result.get("parser_cycles_per_packet_median", -1), parser_median):
            raise SystemExit(f"M2 benchmark parser median mismatch for batch {batch}")
        if not math.isclose(
            result.get("noop_disposition_cycles_per_packet_median", -1), disposition_median
        ):
            raise SystemExit(f"M2 benchmark disposition median mismatch for batch {batch}")
    if artifact.get("valid") is not True or artifact.get("invalid_reason") is not None:
        raise SystemExit("M2 benchmark retained result is not a valid regression sample")
    print(
        "M2 retained benchmark passed: pre-squash/squash anchors, "
        "environment/fixture/source hashes, warmup, 30 raw samples, medians, "
        "and non-capacity scope"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--summary",
        type=Path,
        help="capture a new artifact from the clean current tree instead of validating the retained artifact",
    )
    arguments = parser.parse_args()
    if arguments.summary is None:
        validate()
    else:
        capture(arguments.summary)


if __name__ == "__main__":
    main()
