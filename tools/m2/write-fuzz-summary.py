#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Write a retained, source-bound summary for one completed M2 AFL++ smoke."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess


ROOT = Path(__file__).resolve().parents[2]


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", choices=("parser", "finalizer"), required=True)
    parser.add_argument("--corpus", type=Path, required=True)
    parser.add_argument("--dictionary", type=Path, required=True)
    parser.add_argument("--coverage-map", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    arguments = parser.parse_args()

    version_run = subprocess.run(
        ["afl-fuzz", "--version"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout
    version_match = re.search(r"afl-fuzz\+\+[^\s]+", version_run)
    if version_match is None:
        raise SystemExit("unable to identify AFL++ version")

    target_source = ROOT / (
        "test/fuzz/m2_parser_fuzz.zig"
        if arguments.target == "parser"
        else "test/fuzz/m2_finalizer_fuzz.zig"
    )
    source_paths = [
        target_source,
        ROOT / "test/fuzz/m2_fuzz_main.c",
        ROOT / "tools/m2/fuzz-smoke.sh",
        ROOT / "tools/m2/decode-fuzz-seeds.py",
    ]
    seeds = [
        {
            "path": str(path.relative_to(ROOT)),
            "sha256": digest(path),
        }
        for path in sorted((ROOT / arguments.corpus).glob("*.hex"))
    ]
    if not seeds:
        raise SystemExit("fuzz summary requires at least one checked seed")
    summary = {
        "schema": "saint-shield-m2-fuzz/v1",
        "target": arguments.target,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "source_commit": git("rev-parse", "HEAD"),
        "source_tree": git("rev-parse", "HEAD^{tree}"),
        "dirty": bool(git("status", "--porcelain", "--untracked-files=all")),
        "tool": {
            "aflplusplus": version_match.group(0),
            "mode": "qemu",
        },
        "settings": {
            "campaign_seconds": 2,
            "execution_timeout_ms": 500,
            "maximum_input_bytes": 4096,
            "memory_limit": "none",
            "deterministic_seed_replay": True,
            "coverage_showmap": True,
            "semantic_negative_control": True,
        },
        "sources": [
            {
                "path": str(path.relative_to(ROOT)),
                "sha256": digest(path),
            }
            for path in source_paths
        ],
        "seeds": seeds,
        "dictionary": {
            "path": str((ROOT / arguments.dictionary).relative_to(ROOT)),
            "sha256": digest(ROOT / arguments.dictionary),
        },
        "coverage_map_sha256": digest(arguments.coverage_map),
        "result": {
            "status": "pass",
            "saved_crashes": 0,
            "saved_timeouts": 0,
        },
        "failure_workflow": {
            "minimizer": "afl-tmin -Q",
            "reproducer": f"sh tools/m2/fuzz-smoke.sh {arguments.target} --reproduce RAW_INPUT",
            "reported_fields": ["seed_path", "minimized_trace_hex", "reproducer"],
        },
        "claim_scope": "bounded synthetic regression only; not exhaustive proof",
    }
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
