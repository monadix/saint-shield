# Retrospective process review register

This register contains material governance and workflow findings. The entries
below were migrated from M1 product evidence after the semantic-risk lanes
separated process review from milestone review. Their `PROC` IDs are
retrospective; the old IDs remain as cross-references.

## PROC-GOV-001: Missing or incomplete closure register

- Previous ID: `M1-WORKFLOW-001`
- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: review-evidence completeness
- Observed issue: compacting the M1 ledger initially left no detailed closure
  register; the first retrospective register then omitted transactional
  receive failure atomicity.
- Bounded remediation: create and link the M1 retrospective register, retain
  its material technical findings, and add the missing transactional-receive
  entry using only preserved facts.
- Required focused checks: register-content reconciliation, local-link
  validation, and diff hygiene.
- Addressing evidence: the
  [M1 retrospective register](../m1/REVIEW.md) contains the technical review
  history and transactional-receive entry.
- Closure evidence: the discovering reviewer confirmed the completed M1
  register preserves the material findings, including transactional receive,
  and declared the finding closed.

## PROC-GOV-002: Decision versus edit authority

- Previous ID: `M1-WORKFLOW-002`
- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: sole-writer, closure, and root decision authority
- Observed issue: the workflow could be read as granting the main session
  routine tracked-file edit authority or the writer closure and acceptance
  authority.
- Bounded remediation: separate discovering-role ownership of finding closure;
  root ownership of classification/reclassification, orchestration, process or
  milestone acceptance, completion, and progression; and the selected sole
  writer's physical recording of reported decisions.
- Required focused checks: authority-wording search, independent governance
  review, local-link validation, and diff hygiene.
- Addressing evidence: `AGENTS.md` and `.codex/AGENT_WORKFLOW.md` distinguish
  decision authority from tracked-file edit authority.
- Closure evidence: the discovering reviewer confirmed the then-reviewed
  separation of root acceptance decisions from the selected sole writer's
  physical edits. The later closure-authority contradiction is tracked
  separately as PROC-GOV-004.

## PROC-GOV-003: Lane 2 verifier and gate boundary ambiguity

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: Lane 2 verification and Lane 2/Lane 3 gate boundary
- Observed issue: conditional-verifier wording did not make the listed
  governance triggers mandatory and could be read to allow Lane 2 changes to
  product or milestone gate semantics.
- Bounded remediation: require `gate_verifier` for process-only authority,
  documentary workflow gate, acceptance-evidence, and milestone-acceptance
  fact changes; normally omit it otherwise. Escalate any product/milestone
  correctness or performance gate, acceptance criterion, required command
  set, or executable-wiring change to Lane 3.
- Required focused checks: Lane 2 verifier-trigger and gate-boundary searches,
  documentation/link validation, and diff hygiene.
- Addressing evidence: `AGENTS.md`, `.codex/AGENT_WORKFLOW.md`, and L-007 now
  state the mandatory verifier triggers and exclusive Lane 3 gate boundary.
- Closure evidence: the discovering reviewer confirmed that the Lane 2
  verifier triggers are mandatory, the product/milestone gate boundary is
  unambiguous, and declared PROC-GOV-003 closed.

## PROC-GOV-004: Conflicting finding-closure authority

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: finding closure and root decision authority
- Observed issue: common lane wording assigned closure to root while the
  finding contract assigned closure exclusively to the discovering reviewer or
  verifier.
- Bounded remediation: assign finding-closure decisions and declarations
  exclusively to the discovering role; reserve classification/reclassification,
  orchestration, process or milestone acceptance, completion, and progression
  decisions to the main session; retain the selected sole writer for physical
  recording only.
- Required focused checks: closure/acceptance authority searches, independent
  governance review, documentation/link validation, and diff hygiene.
- Addressing evidence: `AGENTS.md`, `.codex/AGENT_WORKFLOW.md`, and L-007 now
  use the same exclusive authority split.
- Closure evidence: the discovering reviewer confirmed consistent
  discoverer-owned finding closure, root-owned classification and acceptance
  decisions, and sole-writer physical recording, and declared PROC-GOV-004
  closed.

## PROC-GOV-005: Post-integration command-selection gap

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: Lane 3 task envelopes and milestone squash integration
- Observed issue: post-integration checks were prerequisites for accepting the
  squash and deleting the local milestone branch, but the task-envelope and
  role contracts did not require the main session to select their exact
  commands.
- Bounded remediation: require the explorer to propose, the main session to
  select and record, and the sole writer to require and run exact
  envelope-specific post-integration commands while preserving final
  branch/main tree-ID equality and complete clean-status checks.
- Required focused checks: exact/recorded post-integration command searches,
  TOML parsing, documentation/link validation, unchanged specification and
  milestone ledger, and diff hygiene.
- Addressing evidence: `AGENTS.md`, L-008 in
  `planning/LOCAL_EXECUTION_PLAN.md`, `.codex/AGENT_WORKFLOW.md`, and the
  explorer and implementer role instructions now assign the proposal,
  selection, recording, and execution responsibilities without inventing a
  universal milestone command set.
- Closure evidence: the discovering reviewer rechecked those governance and
  role surfaces, confirmed that exact envelope-specific post-integration
  commands are required while tree equality and clean status remain mandatory,
  and declared PROC-GOV-005 closed.

## PROC-GOV-006: Conflicting remote-mutation authorization

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Low
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: sole-writer local and remote Git authority
- Observed issue: the common governance documents allowed remote mutation with
  separate user authorization while both implementer role instructions
  prohibited it unconditionally.
- Bounded remediation: make both implementer roles local-only by default and
  prohibit push, force-push, or other remote mutation unless the user
  separately authorizes it. The current process-change envelope remains
  local-only.
- Required focused checks: conditional remote-authorization searches, TOML
  parsing, documentation/link validation, unchanged specification and
  milestone ledger, and diff hygiene.
- Addressing evidence: `.codex/agents/fast_implementer.toml` and
  `.codex/agents/hard_implementer.toml` now use the same conditional remote
  authority as `AGENTS.md`, L-008, and `.codex/AGENT_WORKFLOW.md`.
- Closure evidence: the discovering reviewer rechecked both implementer roles
  against the common governance documents, confirmed the consistent
  local-by-default rule with separate user authorization required for remote
  mutation, and declared PROC-GOV-006 closed.

## PROC-AUTH-001: Fast writer leaked into Lane 3 follow-up routing

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: Lane 2 writer boundary and Lane 3 writer continuity
- Observed issue: the role table, config description, and fast-writer prompt
  allowed ambiguous low-risk follow-up work that could be read as Lane 3.
- Bounded remediation: restrict `fast_implementer` to Lane 2 and route every
  initial or follow-up Lane 3 edit to `standard_implementer` or
  `hard_implementer`, normally on the existing applicable writer thread.
- Required closure checks: search all fast/low-risk/follow-up references;
  strict-load TOML configuration; run documentation/link and diff checks; and
  confirm no protected product, milestone, specification, or build path changed.
- Addressing evidence: `.codex/AGENT_WORKFLOW.md`, `.codex/config.toml`, and
  `.codex/agents/fast_implementer.toml` now state the exclusive Lane 2 boundary
  and the standard/hard Lane 3 follow-up rule.
- Closure evidence: the discovering reviewer rechecked the corrected workflow,
  config, role prompt, and searches; confirmed fast writing is Lane 2-only and
  every Lane 3 edit routes to the standard or hard writer; and declared
  PROC-AUTH-001 closed.

## PROC-AUTH-002: New writer roles prohibited authorized remote mutation

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Low
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: consistent remote Git authority
- Observed issue: newly added writer prompts unconditionally prohibited remote
  mutation despite the canonical separately authorized remote-operation rule.
- Bounded remediation: retain local-only scope for the current envelope while
  making every writer role prohibit remote mutation only without separate user
  authorization.
- Required closure checks: search all remote-authority wording; strict-load
  TOML configuration; run documentation/link and diff checks; and confirm no
  remote operation occurred.
- Addressing evidence: the `fast_implementer`, `standard_implementer`,
  `hard_implementer`, and `spec_editor` role TOMLs now use the canonical
  `never mutate remotes without separate user authorization` boundary.
- Closure evidence: the discovering reviewer rechecked all applicable writer
  prompts and common remote-authority wording; confirmed the conditional
  separate-user-authorization rule is consistent; and declared PROC-AUTH-002
  closed.

## PROC-AUTH-003: Specification remediation and integration contract incomplete

- Discoverer: `reviewer`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: isolated Lane 3 specification maintenance
- Observed issue: the specification workflow omitted a finding register,
  stable IDs, explicit remediation/closure and repeated-gate rules, and a
  branch integration contract.
- Bounded remediation: define `evidence/spec/<slug>/REVIEW.md` with
  `SPEC-<PERSPECTIVE>-NNN` IDs, ordinary Lane 3 closure authority, corrective
  exact-tree regating, main-only acceptance, and clean non-WIP fast-forward
  integration with tree proof, post-integration checks, and main-directed
  local branch deletion.
- Required closure checks: search specification finding, closure, exact-tree,
  fast-forward, tree-identity, branch-deletion, squash, and remote-authority
  wording; strict-load TOML configuration; run documentation/link and diff
  checks; and confirm specification, milestone, product, and build paths remain
  unchanged.
- Addressing evidence: `.codex/AGENT_WORKFLOW.md` now defines the register,
  stable IDs, ordinary Lane 3 remediation/closure and repeated-gate rules,
  main-only acceptance, and the `git merge --ff-only spec/<slug>` integration
  lifecycle; the spec role TOMLs reference and review that canonical contract.
- Closure evidence: the discovering reviewer rechecked the specification
  finding, authority, repeated-gate, and integration wording; confirmed the
  dedicated register and fast-forward lifecycle are complete and consistent
  with the canonical workflow; and declared PROC-AUTH-003 closed.

## PROC-GOV-007: Missing pre-artifact authority-return inventory

- Discoverer: `process_reviewer` (successor authority: independent governance
  reviewer)
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: High/Critical Lane 3 ownership and authority-return
  remediation sequencing
- Observed issue: repeated M2 alias/authority remediations proceeded to
  source-bound fuzz and benchmark artifact refresh without one durable,
  reviewer-acknowledged inventory of returned authority surfaces, issuer and
  owner bindings, revocation, reuse behavior, and adversarial paths.
- Bounded remediation: add a named, mandatory pre-artifact checkpoint for the
  specified High/Critical ownership/lifetime finding class; require the writer
  to record the complete inventory in the existing milestone finding and the
  discovering reviewer or successor to acknowledge completeness. Invalidate
  that acknowledgment after corrective source changes and re-audit before
  refresh; retain ordinary closure when no source-bound refresh is needed.
- Required focused checks: trigger/field/invalidation searches; explicit
  non-gate and unchanged closure/post-High/exact-tree authority searches;
  documentation/link validation; `git diff --check`; and exact authorized-path
  diff audit.
- Addressing evidence: this commit adds the canonical checkpoint and concise
  AGENTS pointer in `.codex/AGENT_WORKFLOW.md` and `AGENTS.md`, and records
  this finding as addressed. Required commands and product and milestone
  acceptance gates remain unchanged.
- Closure evidence: the successor governance reviewer declared CLEAR/CLOSED
  after reviewing the complete `aaa406a..ea7cff8` tree, the exact three-path
  audit, authority/trigger/non-gate semantics, `git diff --check`, and the
  pinned `nix develop --command zig build docs-check` result (31 links
  passed). The tip, tree, and status were unchanged during review. This
  closure records reviewer authority and does not accept the process gate.

## Non-material hygiene audit

The trailing whitespace formerly recorded as `M1-GATE-002` was removed and
the discovering verifier reported the workflow-only gate acceptable. It is
retained as an unnumbered audit note rather than a process finding.

## PROC-GOV-008: Mutable final-verifier command envelope

- Discoverer: `process_reviewer`
- Successor closure authority: `proc_gov008_review`
- Assigned implementer: `fast_implementer`
- Severity: Medium
- Status progression: `open` -> `addressed` -> `closed`
- Affected workflow: independent final Lane 3 exact-tree verification
- Concrete evidence: M3-GATE-001 included an extra
  `nix develop --command python3 tools/m3/benchmark-gate.py --retain
  bench/examples/benchmark.m3.json` invocation that deterministically dirtied
  a tracked artifact and forced recovery and retry. This was process friction,
  not a product failure.
- Expected behavior: the main-selected envelope supplies one exact ordered
  command sequence with working directories and arguments; after verification
  starts, the verifier cannot add, omit, replace, reorder, or semantically
  alter commands. A changed sequence requires a new envelope and clean
  restart. Commands remain envelope-specific and cannot generate, refresh, or
  retain tracked evidence; retained evidence may be validated read-only.
  Ordinary status stays clean, no new non-ignored state appears, and only
  declared ignored caches/temp may change. Supplemental diagnostics are
  labeled non-gate, provably read-only, status/tree bracketed, and cannot
  substitute. The recognized Nix sandbox/user-cache fetcher-lock exception
  permits only an identical-command retry with narrow cache authorization and
  the first failure recorded. Acceptance and finding authority are unchanged.
- Observed behavior: the additional retain command was outside the selected
  sequence and changed tracked state, requiring recovery before the gate could
  proceed.
- Reproduction: run the M3-GATE-001 selected sequence and then the extra
  benchmark retain command above; inspect ordinary status before and after.
- Failing layer: process envelope definition and verifier command discipline;
  no product, milestone acceptance, or required gate command changed.
- Bounded remediation/rechecks: add the immutable command-envelope contract
  to `AGENTS.md`, `.codex/AGENT_WORKFLOW.md`, `gate_verifier.toml`, and L-011;
  retain this register entry; run strict TOML parsing, semantic authority and
  scope audits, docs-check, diff hygiene, and exact allowed-path review.
- Addressing evidence: the listed governance surfaces now require the exact
  ordered envelope, clean-status invariants, read-only supplemental
  diagnostics, and the narrow Nix retry exception. Status is addressed only;
  the writer does not close the finding.
- Closure pending: `proc_gov008_review` must independently recheck the
  governance meaning and rerun the named focused checks before declaring this
  finding closed. Main retains acceptance and progression authority.
