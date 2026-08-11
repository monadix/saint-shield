#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Decode reviewed M2 hex corpus files into a temporary AFL input directory."""

from pathlib import Path
import sys


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: decode-fuzz-seeds.py SOURCE_DIR DESTINATION_DIR")
    source = Path(sys.argv[1])
    destination = Path(sys.argv[2])
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob("*.hex")):
        text = "".join(path.read_text(encoding="utf-8").split())
        (destination / path.stem).write_bytes(bytes.fromhex(text))


if __name__ == "__main__":
    main()
