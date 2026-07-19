# ADR-001: Apache-2.0 project license

- Status: accepted
- Date: 2026-07-19
- Decision owner: project owner

## Context

M0-V must record a project license before public source and documentation are
treated as distributable artifacts. The project owner explicitly authorized
any non-copyleft license on 2026-07-19.

## Decision

Saint Shield project-authored source is licensed under Apache-2.0. The full
text is stored at `LICENSES/Apache-2.0.txt`, the top-level `LICENSE` identifies
that file, and source files use `SPDX-License-Identifier: Apache-2.0`.

Third-party dependencies retain their own licenses. Their SPDX identifiers are
recorded from the locked Nix package metadata in
`evidence/m0-v/dependencies.json`; that inventory does not relicense them.

## Consequences

Apache-2.0 is permissive and includes an explicit patent grant and notice
requirements. New project-authored source must carry the same SPDX identifier
unless a later reviewed licensing decision records an exception.
