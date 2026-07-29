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

## Non-material hygiene audit

The trailing whitespace formerly recorded as `M1-GATE-002` was removed and
the discovering verifier reported the workflow-only gate acceptable. It is
retained as an unnumbered audit note rather than a process finding.
