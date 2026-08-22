#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate retained M2 fuzz summaries and every bound source/seed hash."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[2]
SUMMARIES = {
    "parser": ROOT / "evidence/m2/fuzz-parser.json",
    "finalizer": ROOT / "evidence/m2/fuzz-finalizer.json",
}
FINAL_GATE_COMMIT = "bf76210a318f15f6ab71e6ffcf1a20f1c0bc9277"
FINAL_GATE_TREE = "b2609e0020b8a33147ee19e563c7f159039c0beb"
ACCEPTED_M2_COMMIT = "aaa406adde9cc6663b691599c5ebfbc5c8d936b6"
ACCEPTED_M2_TREE = "a0b8d91e166cc42ea9fda8eb73b60749e43d9b42"


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


def git_blob_digest(commit: str, path: str) -> str:
    result = subprocess.run(
        ["git", "show", f"{commit}:{path}"],
        cwd=ROOT,
        check=True,
        stdout=subprocess.PIPE,
    )
    return hashlib.sha256(result.stdout).hexdigest()


def is_ancestor(older: str, newer: str) -> bool:
    return subprocess.run(
        ["git", "merge-base", "--is-ancestor", older, newer],
        cwd=ROOT,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0


def validate_squash_bridge(source_commit: str, source_tree: str) -> None:
    if git("rev-parse", f"{source_commit}^{{tree}}") != source_tree:
        raise SystemExit("M2 fuzz source commit/tree binding is invalid")
    if git("rev-parse", f"{FINAL_GATE_COMMIT}^{{tree}}") != FINAL_GATE_TREE:
        raise SystemExit("M2 pre-squash final-gate anchor is invalid")
    if not is_ancestor(source_commit, FINAL_GATE_COMMIT):
        raise SystemExit("M2 fuzz source is not in the accepted pre-squash history")
    if git("rev-parse", f"{ACCEPTED_M2_COMMIT}^{{tree}}") != ACCEPTED_M2_TREE:
        raise SystemExit("M2 accepted squash anchor is invalid")
    if not is_ancestor(ACCEPTED_M2_COMMIT, "HEAD"):
        raise SystemExit("M2 accepted squash is not an ancestor of HEAD")


def validate_hash_records(
    records: list[dict[str, object]],
    label: str,
    source_commit: str,
) -> None:
    if not records:
        raise SystemExit(f"{label} records must not be empty")
    for record in records:
        path = ROOT / str(record["path"])
        if not path.is_file():
            raise SystemExit(f"{label} path is missing: {path.relative_to(ROOT)}")
        if digest(path) != record["sha256"]:
            raise SystemExit(f"{label} hash mismatch: {path.relative_to(ROOT)}")
        relative = str(record["path"])
        if git_blob_digest(source_commit, relative) != record["sha256"]:
            raise SystemExit(f"{label} source-object hash mismatch: {relative}")
        if git_blob_digest(ACCEPTED_M2_COMMIT, relative) != record["sha256"]:
            raise SystemExit(f"{label} accepted-squash hash mismatch: {relative}")


def main() -> None:
    for target, path in SUMMARIES.items():
        summary = json.loads(path.read_text(encoding="utf-8"))
        if summary.get("schema") != "saint-shield-m2-fuzz/v1":
            raise SystemExit(f"{path.relative_to(ROOT)} has the wrong schema")
        if summary.get("target") != target or summary.get("dirty") is not False:
            raise SystemExit(f"{target} summary target/dirty binding is invalid")
        commit = str(summary.get("source_commit"))
        expected_tree = str(summary.get("source_tree"))
        validate_squash_bridge(commit, expected_tree)
        tool = summary.get("tool", {})
        settings = summary.get("settings", {})
        result = summary.get("result", {})
        if tool.get("mode") != "qemu" or not str(tool.get("aflplusplus", "")).startswith("afl-fuzz++"):
            raise SystemExit(f"{target} AFL++ tool binding is invalid")
        expected_settings = {
            "campaign_seconds": 2,
            "execution_timeout_ms": 500,
            "maximum_input_bytes": 4096,
            "memory_limit": "none",
            "deterministic_seed_replay": True,
            "coverage_showmap": True,
            "semantic_negative_control": True,
        }
        if settings != expected_settings:
            raise SystemExit(f"{target} fuzz settings mismatch")
        if result != {"status": "pass", "saved_crashes": 0, "saved_timeouts": 0}:
            raise SystemExit(f"{target} retained fuzz result is not a clean pass")
        validate_hash_records(summary.get("sources", []), f"{target} source", commit)
        validate_hash_records(summary.get("seeds", []), f"{target} seed", commit)
        dictionary = summary.get("dictionary", {})
        validate_hash_records([dictionary], f"{target} dictionary", commit)
        coverage_hash = str(summary.get("coverage_map_sha256", ""))
        if len(coverage_hash) != 64:
            raise SystemExit(f"{target} coverage-map hash is malformed")
        workflow = summary.get("failure_workflow", {})
        if "--reproduce RAW_INPUT" not in str(workflow.get("reproducer", "")):
            raise SystemExit(f"{target} reproducer workflow is missing")
    print(
        "M2 retained fuzz summaries passed: pre-squash/squash anchors, "
        "source, seed, settings, and results"
    )


if __name__ == "__main__":
    main()
