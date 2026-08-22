#!/usr/bin/env python3
"""Capture seven fresh M3 benchmark launches and validate the same tree."""

from __future__ import annotations

import argparse
import pathlib
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[2]


def run(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--retain", type=pathlib.Path)
    args = parser.parse_args()

    if run(["git", "status", "--porcelain=v1", "--untracked-files=all"]).stdout:
        raise SystemExit("M3 benchmark gate requires a clean committed tree")
    commit = run(["git", "rev-parse", "HEAD"]).stdout.strip()
    if not commit:
        raise SystemExit("M3 benchmark gate could not resolve HEAD")

    with tempfile.TemporaryDirectory(prefix="saint-shield-m3-benchmark-gate-") as raw_dir:
        directory = pathlib.Path(raw_dir)
        raw_path = directory / "raw.txt"
        evidence_path = args.retain or (directory / "benchmark.m3.json")
        outputs: list[str] = []
        for run_id in range(1, 8):
            result = run([
                "zig", "build", "-Doptimize=ReleaseFast", "m3-bench", "--",
                "--run-id", str(run_id),
            ])
            if result.returncode != 0:
                raise SystemExit(
                    f"independent benchmark launch {run_id} failed\n{result.stdout}{result.stderr}"
                )
            outputs.append(result.stdout + result.stderr)
        raw_path.write_text("".join(outputs), encoding="utf-8")
        generated = run([
            "python3", "tools/m3/benchmark-evidence.py", "--generate", str(raw_path),
            "--output", str(evidence_path),
        ])
        if generated.returncode != 0:
            raise SystemExit(generated.stdout + generated.stderr)
        if run(["git", "rev-parse", "HEAD"]).stdout.strip() != commit:
            raise SystemExit("HEAD changed during M3 benchmark gate")
        if args.retain is None and run(["git", "status", "--porcelain=v1", "--untracked-files=all"]).stdout:
            raise SystemExit("M3 benchmark gate changed the committed tree")
        print(generated.stdout, end="")
        print("M3 fresh seven-launch benchmark gate passed")


if __name__ == "__main__":
    main()
