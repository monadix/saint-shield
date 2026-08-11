#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Require exact M2 package/API version and preserved M1 coverage provenance."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
EXPECTED = "0.2.0-m2"


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
    if package != EXPECTED or api != EXPECTED:
        raise SystemExit(f"expected {EXPECTED}; package={package}, api={api}")
    if versions.count("0.1.0-m1") != 11 or versions.count(EXPECTED) != 13:
        raise SystemExit(
            "coverage provenance mismatch: "
            f"m1={versions.count('0.1.0-m1')} m2={versions.count(EXPECTED)}"
        )
    print(f"M2 version consistency passed: {EXPECTED}; M1 provenance preserved")


if __name__ == "__main__":
    main()
