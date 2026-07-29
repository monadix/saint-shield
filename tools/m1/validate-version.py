#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Require one exact M1 version across package, API, and coverage claims."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
EXPECTED = "0.1.0-m1"


def one_match(path: Path, pattern: str, label: str) -> str:
    matches = re.findall(pattern, path.read_text(encoding="utf-8"), re.MULTILINE)
    if len(matches) != 1:
        raise SystemExit(
            f"{path.relative_to(ROOT)} must contain exactly one {label}; "
            f"found {len(matches)}"
        )
    return matches[0]


def main() -> None:
    package_version = one_match(
        ROOT / "build.zig.zon",
        r'^\s*\.version = "([^"]+)",$',
        "package version",
    )
    api_version = one_match(
        ROOT / "src/root.zig",
        r'^pub const version = "([^"]+)";$',
        "public API version",
    )
    coverage_versions = re.findall(
        r"^  since: (\S+)$",
        (ROOT / "docs/requirements/coverage.yaml").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if not coverage_versions:
        raise SystemExit("coverage map has no since versions")
    versions = {package_version, api_version, *coverage_versions}
    if versions != {EXPECTED}:
        raise SystemExit(
            "M1 version mismatch: expected "
            f"{EXPECTED}; package={package_version}, api={api_version}, "
            f"coverage={sorted(set(coverage_versions))}"
        )
    print(
        f"M1 version consistency passed: {EXPECTED} across package, API, "
        f"and {len(coverage_versions)} coverage claims"
    )


if __name__ == "__main__":
    main()
