#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Preserve exact M1/M2 coverage provenance under a compatible package."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
EXPECTED_M1 = "0.1.0-m1"
EXPECTED_M2 = "0.2.0-m2"
SUPPORTED_CURRENT = {EXPECTED_M2, "0.3.0-m3"}


def one(path: Path, pattern: str) -> str:
    matches = re.findall(pattern, path.read_text(encoding="utf-8"), re.MULTILINE)
    if len(matches) != 1:
        raise SystemExit(f"{path.relative_to(ROOT)} expected one version, found {len(matches)}")
    return matches[0]


def main() -> None:
    package = one(ROOT / "build.zig.zon", r'^\s*\.version = "([^"]+)",$')
    api = one(ROOT / "src/root.zig", r'^pub const version = "([^"]+)";$')
    versions = re.findall(
        r"^  since: (\S+)$",
        (ROOT / "docs/requirements/coverage.yaml").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    if package != api or package not in SUPPORTED_CURRENT:
        raise SystemExit(
            "current package/API mismatch while checking M2 compatibility: "
            f"package={package}, api={api}"
        )
    if versions.count(EXPECTED_M1) != 11 or versions.count(EXPECTED_M2) != 13:
        raise SystemExit(
            "coverage provenance mismatch: "
            f"m1={versions.count(EXPECTED_M1)} m2={versions.count(EXPECTED_M2)}"
        )
    print(
        "M2 compatibility version check passed: "
        f"11 {EXPECTED_M1} and 13 {EXPECTED_M2} claims preserved under current {package}"
    )


if __name__ == "__main__":
    main()
