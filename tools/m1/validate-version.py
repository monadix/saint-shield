#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Preserve exact M1 coverage provenance under the current package version."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
EXPECTED_M1 = "0.1.0-m1"
SUPPORTED_CURRENT = {"0.1.0-m1", "0.2.0-m2"}


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
    if package_version != api_version or package_version not in SUPPORTED_CURRENT:
        raise SystemExit(
            "current package/API mismatch while checking M1 compatibility: "
            f"package={package_version}, api={api_version}"
        )
    m1_claims = [version for version in coverage_versions if version == EXPECTED_M1]
    if len(m1_claims) != 11:
        raise SystemExit(f"M1 must preserve 11 {EXPECTED_M1} claims; found {len(m1_claims)}")
    print(
        f"M1 compatibility version check passed: {len(m1_claims)} preserved "
        f"{EXPECTED_M1} claims under current {package_version}"
    )


if __name__ == "__main__":
    main()
