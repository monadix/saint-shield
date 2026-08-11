# Saint Shield Multi-Agent Workflow

This is the canonical delegation, review, verification, finding, Git, and
specification-maintenance runbook. `AGENTS.md` contains universal rules;
`planning/LOCAL_EXECUTION_PLAN.md` contains accepted local product and resource
decisions.

The user-controlled main session is the only orchestrator. It owns
classification, task decomposition, delegation, user decisions, process and
milestone acceptance, completion, progression, and retrospective synthesis.
Exactly one selected writer makes tracked-file and physical Git changes at its
direction. Delegated agents never delegate.

## Delegation test and task envelope

Before every spawn, the main session records:

- the qualifying reason: measurable parallelism, substantial context
  isolation, independent assurance, or a mandatory gate;
- selected role and Lane 3 tier, if applicable;
- `fork_turns` mode and justification for any inherited turns;
- the agent's authority and file/system boundary;
- expected evidence and output;
- why completing the task in the main session is not cheaper.

Do not spawn for tiny sequential checks, duplicate exploration, routine status
collection, or an unresolved product decision. Resolve product ambiguity with
the user first. Agent/thread ceilings are capacity limits, not quotas.

Prefer a follow-up on the same role thread while its bounded contract and
relevant repository state remain valid. A new task defaults to
`fork_turns="none"` and receives a self-contained envelope. Inherit only one to
three recent turns when those exact turns materially reduce a safe,
self-contained handoff; record why. `fork_turns="all"` is normally prohibited
and is itself a process-review trigger if genuinely needed.

Every delegated envelope states:

- the authorized Saint Shield repository and defensive/engineering outcome;
- recorded lane and, for Lane 3, standard or critical tier;
- active milestone and applicable requirement, invariant, or gate;
- allowed synthetic, virtual, hardware, and external-system boundary;
- exact scope, allowed paths, exclusions, and stop conditions;
- read-only, validation-only, or sole-writer authority;
- focused checks, expected evidence, and output format;
- for Lane 3, final exact-tree gate commands.

Security-adjacent envelopes explicitly exclude external targeting, broad
scanning, credential access, exploitation, exfiltration, malware deployment,
and destructive actions unless separately and narrowly authorized.

A Lane 3 milestone envelope additionally records the concrete local `main`
baseline, exact `milestone/<lowercase-id>` branch, whether it exists, complete
tracked and untracked status, allowed paths, slice checks, final gate, and
exact envelope-specific post-integration commands. The writer never infers
these facts or a universal milestone command set.

## Roles, tiers, and runtime trust

| Role | Intended assignment | Authority | Use |
| --- | --- | --- | --- |
| `explorer` | Terra, medium | Read-only | Triggered reconciliation of requirements, code, risks, slices, and gates. |
| `fast_implementer` | Luna, medium | Sole writer | Lane 2 changes only. |
| `standard_implementer` | Terra, medium | Sole writer | Standard Lane 3 implementation with explicit contracts. |
| `hard_implementer` | Sol, xhigh | Sole writer | Critical correctness, architecture, security, ownership, or performance work. |
| `reviewer` | Sol, high | Read-only | Independent product owner review from named perspectives. |
| `gate_verifier` | Terra, high | Validation-only | Focused and final exact-tree gates and evidence audit. |
| `process_reviewer` | Terra, medium | Read-only | Triggered analysis of bounded evidence of process friction. |
| `spec_editor` | Sol, high | Sole writer | Separately activated normative specification maintenance. |
| `spec_reviewer` | Sol, high | Read-only | Independent authority and consistency review of specification maintenance. |

These are intended assignments in the legacy repo-local schema accepted by
Codex 0.144.4. The role TOMLs each contain a unique marker, but neither a task
label nor agent self-report proves that the runtime applied its role, model, or
sandbox. Treat all assignments as unusable for model-specific routing until
the smoke below passes on the current surface. Do not migrate this repository
to the newer standalone-agent schema on Codex 0.144.4.

### Role-routing smoke

Before claiming model- or sandbox-specific routing:

1. Strict-load the repo configuration with
   `codex --strict-config doctor --summary --no-color`.
2. Activate one harmless read-only task per role through the role-capable
   runtime surface, using a self-contained `fork_turns="none"` envelope.
3. Inspect parent/runtime activation events or trusted runtime diagnostics—not
   the child's prose—for the exact role marker and effective model and sandbox.
4. Compare all three values to the role TOML. Record the Codex version,
   command/surface, timestamp, and captured metadata.
5. Mark only matching roles proven. A missing marker or missing/mismatched
   runtime model/sandbox is `unproven`; do not infer success.

The current task-label smoke did not apply the project role configuration or
expose runtime model/sandbox metadata. This surface is unproven, so delegation
must not claim a custom model or sandbox until a later smoke supplies trusted
metadata. After proof, do not silently substitute an unavailable model or
sandbox; stop or rerun the proof for an explicitly approved assignment.

## Change classification and routing

The main session records the highest semantic lane before editing or
delegation and alone may reclassify it. File type, diff size, and file count do
not lower classification. Mixed changes take the highest lane unless split
into genuinely independent envelopes; splitting to evade review is forbidden.

| Lane | Boundary | Routing |
| --- | --- | --- |
| 1 — mechanical documentation | Spelling, formatting, or equivalent link repair only; no normative, product, API, authority, gate, evidence, milestone, build, or security meaning. | Main session edits directly; focused documentation/link/diff checks. No spawn or register. |
| 2 — governance/semantic documentation | Agent rules, execution plans, evidence claims, milestone records, security guidance, or role wiring/instructions without product/runtime or executable project-tooling effect. | One sole writer, one independent governance/authority reviewer, and focused validation. Add verifier only on protected triggers below. |
| 3 — product/milestone | Runtime, API, tests, build, schema, executable CI/delivery tooling, milestone implementation/evidence, requirements mappings, correctness/performance gates, or mixed higher-risk work. | Standard or critical workflow below. |

Lane 2 protected surfaces are Lane 2 minimum. Its verifier is mandatory when
the diff changes governance/process-only authority boundaries, documentary
workflow gate definitions or commands, acceptance-evidence statements, or
milestone acceptance facts; normally omit it otherwise. Lane 2 cannot change
product or milestone acceptance criteria, required command sets,
correctness/performance gates, or executable project wiring. That is Lane 3.

Lane 3 standard uses `standard_implementer`, independent `reviewer`, and
`gate_verifier`. Critical adds `explorer`, uses `hard_implementer`, and selects
all applicable specialist review perspectives. Critical includes public
contracts, unsafe or ownership/lifetime boundaries, allocation cleanup,
untrusted parsing/mutation, concurrency/QSBR, FFI/adapters, dependency pins,
policy/state semantics, correctness/performance architecture, and
cross-module/cross-authority work. If tier selection is uncertain, use
critical.

Every initial or follow-up Lane 3 edit uses `standard_implementer` or
`hard_implementer` according to the recorded tier, normally by following up on
the existing applicable writer thread while its contract remains valid.
`fast_implementer` never writes Lane 3 changes.

`explorer` is triggered, not a standing prerequisite or quota. It is mandatory
for critical Lane 3, milestone-exit reconciliation, unresolved scope or
requirement ambiguity, cross-module/cross-authority boundary discovery, or
materially stale/changed relevant repository state. One activation remains
valid for focused remediation in an unchanged envelope. Do not respawn for a
review finding alone or duplicate an existing reconciliation.

A writer encountering work outside its lane, tier, or boundary stops and
reports it. Never run two writers concurrently. A writer handoff requires the
current writer to stop and report changed paths, checks, pending work, and
repository state.

## Lane workflows

### Lane 1

The main session performs focused reconnaissance, edits the bounded mechanical
change, and runs affected documentation, link, and diff checks. Any semantic
doubt stops and escalates.

### Lane 2

1. Main records Lane 2, passes the delegation test, and supplies one bounded
   writer envelope. Exploration is used only if a trigger above applies.
2. The sole writer edits and runs focused validation.
3. One independent reviewer checks governance meaning, authority,
   consistency, classification bypass, and preserved product/milestone facts.
4. Add `gate_verifier` only for the protected triggers.
5. Return material actionable findings to the same writer thread. The
   discovering reviewer/verifier alone closes its finding; main accepts the
   process change.

Clean reviews and non-material hygiene observations create no register entry.

### Lane 3 adversarial contract review

Before a correctness-sensitive writer starts, main records applicable
ownership/lifetime/aliasing/cleanup, untrusted parsing and checked arithmetic,
mutation/finalization/partial failure, concurrency/publication/shutdown,
FFI/provenance/token transfer, policy/state/capability/resource, and
quantitative/instrumentation/artifact-binding boundaries. Mark non-applicable
ones explicitly. Main also selects review perspectives and names focused
preflight and final gate commands. Unspecified public behavior returns to the
user.

### High ownership/lifetime authority-return checkpoint

When a Critical or High Lane 3 finding concerns ownership, lifetime, aliasing,
provenance, capability, or token transfer and its remediation changes
authority-return behavior, main names this checkpoint in the remediation
envelope. After focused semantic tests and before regenerating any
source-bound fuzz or benchmark artifact, the writer records an authority-return
inventory in the existing milestone finding. The discovering reviewer (or its
named successor) audits and acknowledges that inventory is complete. The
checkpoint is mandatory process sequencing, not a product or milestone
acceptance gate; it does not add commands or alter required commands, finding
closure, post-High fresh full-diff review, or exact-tree gate authority.

The inventory must identify the exact authority surface (handle, pointer,
slice, token, iterator, descriptor, or callback); issuer boundary
(public, processor-trusted, adapter-trusted, or internal); owner, generation,
index, lease, and capability binding; whether raw storage or authority survives
return; revocability; behavior after retain/transfer, completion, invalidation,
and reuse; enforcement and failure atomicity; and adversarial evidence for
pre-minted, newly minted, stale, and recycled paths. A non-revocable surface
requires an already-accepted enforcement mechanism. If public behavior is
unspecified, stop through the existing user/ADR/specification decision
workflow. Any later corrective source change invalidates the acknowledgment
and requires re-audit before artifact refresh. If no source-bound refresh is
needed, audit the inventory during ordinary closure without a separate round.
The writer records the inventory, the discovering reviewer audits it, and that
acknowledgment never transfers closure authority.

### Lane 3 implementation

1. Complete the startup checks; record lane/tier, milestone, gate, baseline,
   branch, checks, and post-integration commands.
2. Run triggered exploration. For standard work without a trigger, main's
   focused reconnaissance supplies the implementation packet.
3. Complete the adversarial review and bounded sole-writer handoff.
4. The selected writer implements coherent vertical slices with tests,
   mappings, documentation, cleanup paths, and benchmark/ADR evidence as
   applicable, using narrow checks while iterating.
5. After a stable diff, run independent review and focused verification. They
   may run concurrently when the delegation test justifies it.
6. Register actionable findings and return them to the same writer thread.
   Their discoverers rerun focused checks and alone declare closure.
7. After a Critical or High correctness finding closes, run a fresh
   unanchored full-diff review with the original requirements and complete
   diff.
8. After all blocking findings close, `gate_verifier` runs the final exact-tree
   full gate. A corrective tree change requires a new commit and repeated gate.
9. Main accepts the gate and directs the sole writer to record compact
   acceptance evidence. Recording conveys no acceptance authority.

## Lane 3 milestone Git lifecycle

This applies only to unfinished Lane 3 milestones.

### Branch and commits

1. Use the exact local `milestone/<lowercase-id>` branch from the recorded
   accepted local `main`; only one milestone branch may be active. Deferred
   milestones and later-risk spikes require separate main activation.
2. Before create, resume, switch, or integration, inspect complete tracked and
   untracked status. Dirtiness, a missing/ambiguous base, branch conflict, or
   advanced `main` stops for user direction. Never stash, reset, clean, or
   absorb unrelated files.
3. The writer alone performs branch changes, explicit-path staging, commits,
   the permitted WIP-tip amendment, main-directed squash integration, and
   local deletion. Remote mutations require separate user authorization.
4. The first branch commit records `In progress`, date, and expected gate.
   Commit each coherent vertical slice after focused checks and staged-diff
   inspection.
5. At most one `wip(<id>): ...` commit may exist, only at the tip. Amend it
   into a semantic commit before another slice, review, or verification.
   Never rewrite completed or reviewed commits; remediation uses new commits.
6. Handoffs report clean status, branch, base, tip, ordered `BASE..TIP`
   commits, changed paths, slice checks, failures/findings, and next action.

### Review, gate, and integration

Reviewers reject WIP tips and inspect complete `BASE..TIP` plus full status.
The final verifier requires a clean committed non-WIP tip, records commit and
tree IDs before and after the gate, and rejects any change. Gate corrections
are new commits and repeat the full exact-tree gate.

After main accepts:

1. The writer commits permitted acceptance-only evidence/ledger wording.
   Focused documentation/schema/link/diff checks suffice only if no gate input
   changed; otherwise repeat the full gate.
2. Record final branch tip and accepted commit/tree; confirm clean status and
   unchanged baseline `main`.
3. At explicit main direction, squash onto local `main` as
   `milestone(<id>): complete <ledger title>`, with the pre-squash tip and
   accepted commit/tree in the body.
4. Prove branch/main tree identity, run the envelope's exact post-integration
   commands, and confirm clean status.
5. Only then may main direct forced deletion of the exact local branch. A
   mismatch or failed check retains it. Never delete a remote branch here.

## Milestone exit

Before acceptance:

1. Trigger `explorer` to reconcile the entire checklist, normative and
   archived/local gates, code, tests, docs, benchmark deltas, and cleanup
   evidence. Reuse only a still-valid reconciliation.
2. Use critical routing for remaining correctness- or gate-sensitive work.
3. Run applicable owner perspectives: core packet/ownership/mutation,
   concurrency/QSBR, adapter/FFI, language/security, and/or performance.
4. Close blocking findings and any required fresh review, then verify the final
   exact tree with Debug, ReleaseSafe, ReleaseFast, and every required fuzz,
   model, adapter, docs, schema, benchmark, and cross-target check.
5. Accept only with a passing gate, no blocking finding, complete artifacts,
   and an accurate progress ledger.

Synthetic or virtual evidence never becomes physical acceptance or production
capacity evidence. M0-H, M4, and later physical gates require their stated
hardware, permissions, and user decisions.

## Findings and records

Lane 1 has no register. Lane 2 records only material actionable findings in
`evidence/process/REVIEW.md` as `PROC-<PERSPECTIVE>-NNN`. Lane 3 records them
in `evidence/<milestone>/REVIEW.md` as
`M<milestone>-<PERSPECTIVE>-NNN`.

Each entry contains status (`open`, `addressed`, `closed`), severity,
requirement/invariant/gate, discoverer, assigned writer, concrete evidence,
expected and observed behavior, reproduction and seed/trace where applicable,
failing layer, bounded remediation/rechecks, addressing evidence, and closure
result. The writer alone declares `addressed`; the discovering reviewer or
verifier alone declares `closed` after rerunning its checks. The writer records
reported status at main direction but gains no closure authority. The verifier
never fixes failures.

Keep milestone starts, blocked/reopened states, material gate changes, and
final acceptance in `planning/IMPLEMENTATION_PROGRESS.md`. Put detailed
findings, chronology, logs, and seeds in the relevant register.

## Specification maintenance

`planning/specification/` is frozen during milestone implementation. Actual
normative edits occur only in a separately activated spec-maintenance session
on `spec/<slug>`, never while a milestone branch is active. They are Lane 3
even when documentation-only.

Main must first prove `spec_editor` and `spec_reviewer` routing with the role
smoke, reconcile source authority and downstream migration impact, and record
the branch/base/checks. `spec_editor` is the sole writer; `spec_reviewer` and
`gate_verifier` independently review and verify the exact tree. No role-routing
proof means no delegated specification edit; stop for a supported surface or
explicit user direction. Specification maintenance cannot silently change
milestone facts, waive gates, or overlap product implementation.

Specification findings use `evidence/spec/<slug>/REVIEW.md` and stable
`SPEC-<PERSPECTIVE>-NNN` IDs. Ordinary Lane 3 remediation authority applies:
the sole spec editor declares a finding `addressed`, its discovering reviewer
or verifier alone declares it `closed` after focused recheck, and the main
session alone accepts the specification gate. Any corrective tree change after
an exact-tree gate requires a new commit and repetition of that gate.

Specification branches use their own integration contract, not the milestone
squash lifecycle. Verification requires a clean, committed, non-WIP
`spec/<slug>` tip. After acceptance, the sole spec editor confirms local `main`
still equals the recorded baseline, switches to local `main`, and fast-forwards
it with `git merge --ff-only spec/<slug>`. The editor proves the resulting
`main` tree equals the accepted spec-branch tree, runs the recorded
post-integration checks, and deletes the exact local spec branch only on
main-session direction. Any advanced `main`, mismatch, or failed check stops
and retains the branch. Specification maintenance does not squash or mutate
remotes without separate user authorization.

## Process reviewer and retrospective

The main session activates `process_reviewer` only for:

- repeated friction;
- authority ambiguity that caused a finding;
- an orchestration-caused gate rerun;
- a genuine need for `fork_turns="all"`;
- role-routing failure;
- milestone closure.

The evidence packet names the subject contract, observable messages/handoff,
commands/failures/diff/commits/artifacts, exact process question, and
exclusions from product review, tracked edits, finding closure, gate
acceptance, milestone decisions, orchestration, delegation, or hidden/unseen
reasoning. Inspect after the subject yields; if necessary, first obtain a
factual status packet or interrupt safely.

The process reviewer returns either `no supported inefficiency` or evidence,
likely process cause, bounded correction, expected benefit/tradeoff, and
suggested lane. It has no other authority. `hard_implementer`, `reviewer`, and
`gate_verifier` may each report at most one directly encountered,
evidence-backed friction observation. No role supplies mandatory empty
retrospective fields; explorer, fast, standard, and specification roles remain
task-only.

Every completed, interrupted, or blocked implementation run ends with
main-session synthesis after verification. Planning and read-only answers do
not. If no correction is supported, report exactly:
`Process retrospective: no actionable process correction identified.`
Otherwise report only actionable evidence, inefficiency, bounded correction,
benefit/risk, and proposed lane. Efficiency proposals are non-blocking and
final-report-only until separately authorized and reclassified.
