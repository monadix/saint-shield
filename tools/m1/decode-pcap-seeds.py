#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Decode reviewed hexadecimal PCAP fuzz seeds into raw temporary inputs."""

from pathlib import Path
import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: decode-pcap-seeds.py SOURCE_DIR OUTPUT_DIR", file=sys.stderr)
        return 2

    source_dir = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)
    sources = sorted(source_dir.glob("*.hex"))
    if not sources:
        print("PCAP seed corpus is empty", file=sys.stderr)
        return 1

    for source in sources:
        encoded = "".join(source.read_text(encoding="ascii").split())
        try:
            decoded = bytes.fromhex(encoded)
        except ValueError as error:
            print(f"{source}: invalid hexadecimal seed: {error}", file=sys.stderr)
            return 1
        if len(decoded) > 1024 * 1024:
            print(f"{source}: seed exceeds the 1 MiB target limit", file=sys.stderr)
            return 1
        (output_dir / source.stem).write_bytes(decoded)
    print(f"decoded {len(sources)} reviewed PCAP seeds")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
