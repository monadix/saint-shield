#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Require exact M3 package/API version and preserved requirement provenance."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
EXPECTED = "0.3.0-m3"


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
        (ROOT / "docs/requirements/coverage.yaml").read_text(),
        re.MULTILINE,
    )
    counts = {version: versions.count(version) for version in ("0.1.0-m1", "0.2.0-m2", EXPECTED)}
    if package != EXPECTED or api != EXPECTED:
        raise SystemExit(f"expected {EXPECTED}; package={package}, api={api}")
    if counts != {"0.1.0-m1": 11, "0.2.0-m2": 13, EXPECTED: 27}:
        raise SystemExit(f"coverage provenance mismatch: {counts}")
    print(f"M3 version consistency passed: {EXPECTED}; M1/M2 provenance preserved")


if __name__ == "__main__":
    main()
