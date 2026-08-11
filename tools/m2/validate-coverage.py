#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the cumulative dependency-gated M2 requirement/evidence map."""

from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
M1_PATH = ROOT / "tools/m1/validate-coverage.py"
SPEC = importlib.util.spec_from_file_location("saint_m1_coverage", M1_PATH)
assert SPEC is not None and SPEC.loader is not None
M1 = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(M1)

EXPECTED_M2_IDS = set(M1.EXPECTED_M1_IDS) | {
    "FR-PKT-005",
    "FR-PKT-007",
    "FR-PKT-008",
    "FR-PKT-009",
    "FR-PKT-010",
    "FR-PKT-013",
    "FR-TEST-003",
    "INV-PKT-003",
    "INV-PKT-004",
    "INV-PKT-005",
    "AC-001",
    "AC-002",
    "AC-010",
}


def main() -> None:
    records = M1.parse_coverage()
    failures = M1.validate_records(
        records,
        M1.catalogue_ids(),
        M1.all_zig_tests(),
        M1.reachable_zig_tests(),
    )
    ids = {str(record["id"]) for record in records}
    if ids != EXPECTED_M2_IDS:
        missing = EXPECTED_M2_IDS - ids
        unexpected = ids - EXPECTED_M2_IDS
        if missing:
            failures.append("M2 map lacks IDs: " + ", ".join(sorted(missing)))
        if unexpected:
            failures.append("M2 map has unexpected IDs: " + ", ".join(sorted(unexpected)))
    for record in records:
        version = record.get("since")
        if str(record["id"]) in M1.EXPECTED_M1_IDS:
            if version != "0.1.0-m1":
                failures.append(f"{record['id']} must preserve since 0.1.0-m1")
        elif version != "0.2.0-m2":
            failures.append(f"{record['id']} must use since 0.2.0-m2")
    if failures:
        raise SystemExit("M2 coverage validation failed:\n" + "\n".join(failures))
    print(f"M2 coverage passed: {len(records)} exact cumulative claims")


if __name__ == "__main__":
    main()
