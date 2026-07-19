#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

test "${SAINT_SHIELD_ZIG_VERSION:-}" = "0.16.0"
test "${SAINT_SHIELD_DPDK_VERSION:-}" = "25.11.2"
test "${SAINT_SHIELD_SCAPY_VERSION:-}" = "2.7.0"
test "${SAINT_SHIELD_AFL_VERSION:-}" = "5.00c"
test "${SAINT_SHIELD_TLA_VERSION:-}" = "1.7.4"
test "$(zig version)" = "0.16.0"
test "$(pkg-config --modversion libdpdk)" = "25.11.2"
jq -e '.nodes.nixpkgs.locked.rev == "61b7c44c4073f0b827768aff0049561b5110ea5a"' flake.lock >/dev/null
jq -e '
  .schema == "saint-shield-dependencies/v1" and
  ([.runtime_build[], .test_tooling[]] | all(
    (.name | type == "string") and
    (.version | type == "string") and
    (.license_spdx | type == "array" and length > 0) and
    (.license_spdx | all(type == "string" and length > 0))
  )) and
  (.runtime_build[] | select(.name == "DPDK") |
    .hash == "sha256-QYv+MhJkDulaHLEK9u02DK0jh2hv4nIfijqc0C1e9PI=")
' evidence/m0-v/dependencies.json >/dev/null

metadata_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-license-metadata.XXXXXX")
trap 'rm -rf "$metadata_dir"' EXIT HUP INT TERM
nix eval --json .#lib.dependencyMetadata.x86_64-linux \
    >"$metadata_dir/locked.json"
jq -S '{
  runtime_build: [.runtime_build[] | {name, version, license_spdx}],
  test_tooling: [.test_tooling[] | {name, version, license_spdx}]
}' evidence/m0-v/dependencies.json >"$metadata_dir/recorded.json"
jq -S . "$metadata_dir/locked.json" >"$metadata_dir/locked-sorted.json"
cmp "$metadata_dir/recorded.json" "$metadata_dir/locked-sorted.json"

test -f LICENSES/Apache-2.0.txt
test -f LICENSE
test -f SECURITY.md

(cd planning/specification/l4-protection-framework-technical-plan && sha256sum -c MANIFEST.sha256)
(cd planning/specification/l4-protection-framework-technical-plan/source-requirements && sha256sum -c MANIFEST.sha256)
printf '%s\n' "toolchain, dependency, archive, and license integrity passed"
