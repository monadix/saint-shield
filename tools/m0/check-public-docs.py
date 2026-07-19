#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Check the M0-V public Zig and top-level module documentation contract."""

from pathlib import Path
import re
import sys


PUBLIC_DECLARATION = re.compile(r"^\s*(?:pub|export)\s+")
ZIG_ROOTS = [
    Path("build.zig"),
    Path("src"),
    Path("examples"),
    Path("bench"),
    Path("test"),
]
MODULES = [
    "foundation",
    "packet",
    "processor",
    "pipeline",
    "update",
    "observability",
    "state",
    "policy",
    "testing",
    "io",
]
MODULE_SECTIONS = [
    "## Responsibility",
    "## Requirements and invariants",
    "## Public contract",
    "## Dependencies",
    "## Object lifecycle and ownership",
    "## Concurrency",
    "## Allocation and work bounds",
    "## Failure behavior",
    "## Security boundary",
    "## Performance budget",
    "## Tests and evidence",
    "## Alternatives and evolution",
    "## Open questions",
]


def zig_files() -> list[Path]:
    files: list[Path] = []
    for root in ZIG_ROOTS:
        if root.is_file() and root.suffix == ".zig":
            files.append(root)
        elif root.is_dir():
            files.extend(root.rglob("*.zig"))
    return sorted(files)


failures: list[str] = []
for path in zig_files():
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if not PUBLIC_DECLARATION.match(line):
            continue
        previous = index - 1
        while previous >= 0 and not lines[previous].strip():
            previous -= 1
        if previous < 0 or not lines[previous].lstrip().startswith("///"):
            failures.append(f"{path}:{index + 1}: public declaration lacks /// documentation")

for module in MODULES:
    path = Path("docs/internals/modules") / f"{module}.md"
    if not path.is_file():
        failures.append(f"{path}: missing top-level module design record")
        continue
    contents = path.read_text(encoding="utf-8")
    for section in MODULE_SECTIONS:
        if section not in contents:
            failures.append(f"{path}: missing section {section}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    raise SystemExit(1)

print("public Zig declarations and top-level module records passed")
