#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate cumulative M3 requirements with preserved M1/M2 provenance."""

from __future__ import annotations

import importlib.util
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
M2_PATH = ROOT / "tools/m2/validate-coverage.py"
SPEC = importlib.util.spec_from_file_location("saint_m2_coverage", M2_PATH)
assert SPEC is not None and SPEC.loader is not None
M2 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M2)

EXPECTED_M3_ONLY = {
    "FR-COMP-001", "FR-COMP-002", "FR-COMP-003", "FR-COMP-005", "FR-COMP-006",
    "FR-PROC-001", "FR-PROC-002", "FR-PROC-003", "FR-PROC-004", "FR-PROC-005",
    "FR-PROC-006", "FR-PROC-007", "FR-PROC-008", "FR-PROC-009",
    "FR-EXT-001", "FR-EXT-002", "FR-EXT-003", "FR-PKT-014", "FR-PKT-015",
    "FR-STATE-001", "FR-STATE-004", "FR-TEST-001", "INV-RES-001", "INV-RES-002",
    "AC-003", "AC-012", "PERF-CORE-001",
}
EXPECTED_IDS = M2.EXPECTED_M2_IDS | EXPECTED_M3_ONLY
TEST_PATTERN = re.compile(r'\btest\s+"([^"]+)"')


def m3_tests() -> set[str]:
    executed = set(TEST_PATTERN.findall((ROOT / "test/m3/runtime.zig").read_text()))
    executed.update(TEST_PATTERN.findall((ROOT / "bench/micro/m3_static_pipeline.zig").read_text()))
    return executed


def main() -> None:
    records = M2.M1.parse_coverage()
    executed = M2.M1.reachable_zig_tests() | m3_tests()
    failures = M2.M1.validate_records(
        records,
        M2.M1.catalogue_ids(),
        M2.M1.all_zig_tests(),
        executed,
    )
    ids = {str(record["id"]) for record in records}
    if ids != EXPECTED_IDS:
        if EXPECTED_IDS - ids:
            failures.append("M3 map lacks IDs: " + ", ".join(sorted(EXPECTED_IDS - ids)))
        if ids - EXPECTED_IDS:
            failures.append("M3 map has unexpected IDs: " + ", ".join(sorted(ids - EXPECTED_IDS)))
    for record in records:
        requirement_id = str(record["id"])
        version = record.get("since")
        if requirement_id in M2.M1.EXPECTED_M1_IDS:
            expected = "0.1.0-m1"
        elif requirement_id in M2.EXPECTED_M2_IDS:
            expected = "0.2.0-m2"
        else:
            expected = "0.3.0-m3"
        if version != expected:
            failures.append(f"{requirement_id} must preserve since {expected}")
    if failures:
        raise SystemExit("M3 coverage validation failed:\n" + "\n".join(failures))
    print(f"M3 coverage passed: {len(records)} exact cumulative claims")


if __name__ == "__main__":
    main()
