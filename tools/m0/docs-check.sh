#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu

site_dir=$(mktemp -d "${TMPDIR:-/tmp}/saint-docs.XXXXXX")
trap 'rm -rf "$site_dir"' EXIT HUP INT TERM
python3 tools/m0/check-public-docs.py
mkdocs build --strict --site-dir "$site_dir/site"
linkchecker --no-warnings README.md docs
printf '%s\n' "authored documentation and local links passed"
