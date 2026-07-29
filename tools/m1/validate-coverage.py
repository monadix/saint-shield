#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Validate the dependency-gated M1 requirement/evidence map."""

from pathlib import Path
import argparse
import ast
import copy
import re


ROOT = Path(__file__).resolve().parents[2]
COVERAGE = ROOT / "docs/requirements/coverage.yaml"
CANONICAL_TEST_ROOT = ROOT / "src/root.zig"
REQUIREMENTS = (
    ROOT
    / "planning/specification/l4-protection-framework-technical-plan"
    / "source-requirements/requirements.yaml"
)
INVARIANTS = (
    ROOT
    / "planning/specification/l4-protection-framework-technical-plan"
    / "01-architecture/invariants.md"
)
PERFORMANCE = (
    ROOT
    / "planning/specification/l4-protection-framework-technical-plan"
    / "03-performance/quantitative-gates.md"
)
EXPECTED_M1_IDS = {
    "FR-PKT-001",
    "FR-PKT-002",
    "FR-PKT-003",
    "FR-PKT-004",
    "FR-PKT-006",
    "FR-PKT-011",
    "FR-PKT-012",
    "FR-TEST-002",
    "INV-PKT-001",
    "INV-PKT-002",
    "PERF-CORE-004",
}
ACCEPTED_STATUSES = {"passing", "passing-synthetic-regression-only"}
TEST_PATTERN = re.compile(r'\btest\s+"([^"]+)"')
IMPORT_PATTERN = re.compile(r'@import\("([^"]+)"\)')


def scalar(value: str) -> str:
    value = value.strip()
    if value.startswith(("'", '"')):
        parsed = ast.literal_eval(value)
        if not isinstance(parsed, str):
            raise ValueError(f"expected string scalar, got {value}")
        return parsed
    return value


def parse_coverage(path: Path = COVERAGE) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    current: dict[str, object] | None = None
    section: str | None = None
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"- id: ([A-Z0-9-]+)", line)
        if match:
            current = {
                "id": match.group(1),
                "code": [],
                "tests": [],
                "line": line_number,
            }
            records.append(current)
            section = None
            continue
        if current is None:
            raise ValueError(f"{path}:{line_number}: field before first id")
        match = re.fullmatch(r"  (design|status|since): (.+)", line)
        if match:
            current[match.group(1)] = scalar(match.group(2))
            section = None
            continue
        match = re.fullmatch(r"  (code|tests):", line)
        if match:
            section = match.group(1)
            continue
        match = re.fullmatch(r"    - (.+)", line)
        if match and section is not None:
            values = current[section]
            assert isinstance(values, list)
            values.append(scalar(match.group(1)))
            continue
        raise ValueError(f"{path}:{line_number}: unsupported mapping syntax")
    return records


def catalogue_ids() -> set[str]:
    ids = set(
        re.findall(r"^- id: ([A-Z0-9-]+)$", REQUIREMENTS.read_text(), re.MULTILINE)
    )
    ids.update(
        re.findall(r"^\| (INV-[A-Z0-9-]+) \|", INVARIANTS.read_text(), re.MULTILINE)
    )
    ids.update(
        re.findall(r"^\| (PERF-[A-Z0-9-]+) \|", PERFORMANCE.read_text(), re.MULTILINE)
    )
    return ids


def all_zig_tests() -> set[str]:
    names: set[str] = set()
    for root_name in ("src", "test", "bench"):
        for path in (ROOT / root_name).rglob("*.zig"):
            names.update(TEST_PATTERN.findall(path.read_text(encoding="utf-8")))
    return names


def reachable_zig_sources(root: Path = CANONICAL_TEST_ROOT) -> set[Path]:
    pending = [root.resolve()]
    reachable: set[Path] = set()
    while pending:
        path = pending.pop()
        if path in reachable:
            continue
        if not path.is_file():
            raise ValueError(f"canonical test import is missing: {path}")
        path.relative_to(ROOT)
        reachable.add(path)
        source = path.read_text(encoding="utf-8")
        for imported in IMPORT_PATTERN.findall(source):
            if not imported.endswith(".zig"):
                continue
            imported_path = (path.parent / imported).resolve()
            try:
                imported_path.relative_to(ROOT)
            except ValueError as error:
                raise ValueError(
                    f"canonical test import escapes repository: {path}: {imported}"
                ) from error
            pending.append(imported_path)
    return reachable


def reachable_zig_tests() -> set[str]:
    names: set[str] = set()
    for path in reachable_zig_sources():
        names.update(TEST_PATTERN.findall(path.read_text(encoding="utf-8")))
    return names


def validate_records(
    records: list[dict[str, object]],
    known_ids: set[str],
    discovered_tests: set[str],
    executed_tests: set[str],
    coverage_path: Path = COVERAGE,
) -> list[str]:
    failures: list[str] = []
    seen: set[str] = set()

    for record in records:
        requirement_id = str(record["id"])
        line = record["line"]
        location = f"{coverage_path}:{line}"
        if requirement_id in seen:
            failures.append(f"{location}: duplicate id {requirement_id}")
        seen.add(requirement_id)
        if requirement_id not in known_ids:
            failures.append(f"{location}: unknown id {requirement_id}")
        for required_field in ("design", "status", "since"):
            if required_field not in record:
                failures.append(f"{location}: {requirement_id} lacks {required_field}")

        code_paths = record["code"]
        assert isinstance(code_paths, list)
        if not code_paths:
            failures.append(f"{location}: {requirement_id} has empty code list")
        for path_value in [record.get("design"), *code_paths]:
            if not isinstance(path_value, str) or not (ROOT / path_value).is_file():
                failures.append(
                    f"{location}: {requirement_id} references missing path {path_value}"
                )

        status = record.get("status")
        if status is not None and status not in ACCEPTED_STATUSES:
            failures.append(
                f"{location}: {requirement_id} has invalid status {status!r}"
            )
        mapped_tests = record["tests"]
        assert isinstance(mapped_tests, list)
        if status in ACCEPTED_STATUSES and not mapped_tests:
            failures.append(
                f"{location}: passing claim {requirement_id} has no test"
            )
        for test_name in mapped_tests:
            if test_name not in discovered_tests:
                failures.append(
                    f"{location}: {requirement_id} references missing test "
                    f"{test_name!r}"
                )
            elif test_name not in executed_tests:
                failures.append(
                    f"{location}: {requirement_id} references unreachable test "
                    f"{test_name!r}"
                )

    missing = EXPECTED_M1_IDS - seen
    unexpected = seen - EXPECTED_M1_IDS
    if missing:
        failures.append(f"M1 map lacks required IDs: {', '.join(sorted(missing))}")
    if unexpected:
        failures.append(
            "M1 map claims future or unselected IDs: "
            + ", ".join(sorted(unexpected))
        )
    return failures


def expect_self_test_failure(
    label: str,
    records: list[dict[str, object]],
    expected_text: str,
    known_ids: set[str],
    discovered_tests: set[str],
    executed_tests: set[str],
) -> None:
    failures = validate_records(
        records, known_ids, discovered_tests, executed_tests, Path("<self-test>")
    )
    if not any(expected_text in failure for failure in failures):
        raise AssertionError(
            f"coverage validator negative self-test {label!r} did not produce "
            f"{expected_text!r}: {failures}"
        )


def run_self_tests() -> None:
    records = parse_coverage()
    known_ids = catalogue_ids()
    discovered_tests = all_zig_tests()
    executed_tests = reachable_zig_tests()
    base_failures = validate_records(
        records, known_ids, discovered_tests, executed_tests
    )
    if base_failures:
        raise AssertionError(
            "canonical coverage must pass before negative self-tests:\n"
            + "\n".join(base_failures)
        )

    unknown = copy.deepcopy(records)
    unknown[0]["id"] = "UNKNOWN-M1-ID"
    expect_self_test_failure(
        "unknown id", unknown, "unknown id", known_ids, discovered_tests, executed_tests
    )

    duplicate = copy.deepcopy(records)
    duplicate.append(copy.deepcopy(duplicate[0]))
    expect_self_test_failure(
        "duplicate id",
        duplicate,
        "duplicate id",
        known_ids,
        discovered_tests,
        executed_tests,
    )

    missing_path = copy.deepcopy(records)
    missing_path[0]["code"] = ["src/does-not-exist.zig"]
    expect_self_test_failure(
        "missing path",
        missing_path,
        "references missing path",
        known_ids,
        discovered_tests,
        executed_tests,
    )

    missing_test = copy.deepcopy(records)
    missing_test[0]["tests"] = ["test that does not exist"]
    expect_self_test_failure(
        "missing test",
        missing_test,
        "references missing test",
        known_ids,
        discovered_tests,
        executed_tests,
    )

    unreachable_test = copy.deepcopy(records)
    unreachable_name = "self-test fixture outside canonical test import graph"
    unreachable_test[0]["tests"] = [unreachable_name]
    expect_self_test_failure(
        "unreachable test",
        unreachable_test,
        "references unreachable test",
        known_ids,
        discovered_tests | {unreachable_name},
        executed_tests,
    )

    invalid_status = copy.deepcopy(records)
    invalid_status[0]["status"] = "looks-good"
    expect_self_test_failure(
        "invalid status",
        invalid_status,
        "has invalid status",
        known_ids,
        discovered_tests,
        executed_tests,
    )

    empty_code = copy.deepcopy(records)
    empty_code[0]["code"] = []
    expect_self_test_failure(
        "empty code",
        empty_code,
        "has empty code list",
        known_ids,
        discovered_tests,
        executed_tests,
    )
    print("M1 coverage validator negative self-tests passed: 7 rejection classes")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run validator negative-control self-tests",
    )
    args = parser.parse_args()
    if args.self_test:
        run_self_tests()
        return

    records = parse_coverage()
    failures = validate_records(
        records,
        catalogue_ids(),
        all_zig_tests(),
        reachable_zig_tests(),
    )
    if failures:
        raise SystemExit("\n".join(failures))
    print(
        f"M1 coverage map passed: {len(records)} unique known IDs, all code paths "
        f"nonempty, statuses accepted, and mapped tests reachable from "
        f"{CANONICAL_TEST_ROOT.relative_to(ROOT)}"
    )


if __name__ == "__main__":
    main()
