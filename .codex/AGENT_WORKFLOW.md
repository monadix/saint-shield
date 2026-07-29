# Saint Shield Multi-Agent Workflow

The user-controlled main session is the sole orchestrator. It owns task
decomposition, agent activation, handoffs, user decisions, gate acceptance,
and decisions about final progress-ledger content. These are decision
authorities, not authority for routine tracked-file edits: the selected sole
writer makes those edits at the main session's direction. No custom
orchestrator agent exists, and project subagents must not spawn descendants.

## Required task envelope

Every delegated task names:

- the authorized target: this Saint Shield repository;
- the defensive or engineering outcome;
- the root-selected change-classification lane;
- the active milestone and applicable requirement, invariant, or gate;
- the permitted synthetic, virtual, or hardware boundary;
- the exact in-scope question or change and explicit exclusions;
- whether the role is read-only, validation-only, or the sole writer;
- the expected evidence and output format;
- the lane-required focused checks and, for Lane 3, the final exact-tree gate
  commands.

Security-adjacent tasks must also state that external targeting, broad
scanning, credential access, exploitation, exfiltration, malware deployment,
and destructive actions are out of scope unless a separately authorized
defensive task genuinely requires a narrower action.

## Roles and routing

| Role | Model | Authority | Use |
| --- | --- | --- | --- |
| `explorer` | GPT-5.6 Terra, medium | Read-only | Establish requirements, current code paths, risks, task slices, and verification before edits. |
| `fast_implementer` | GPT-5.6 Luna, medium | Sole writer | Lane 1/2 documentation and separately bounded low-risk Lane 3 documentation, fixture, test, evidence-formatting, or mechanical internal changes. |
| `hard_implementer` | GPT-5.6 Sol, xhigh | Sole writer | Public contracts, ownership, cleanup, untrusted inputs, concurrency, FFI/adapters, pins, policy/state semantics, performance, and cross-module work. |
| `reviewer` | GPT-5.6 Sol, high | Read-only | Independent owner review against requirements, invariants, tests, and the assigned specialist perspective. |
| `gate_verifier` | GPT-5.6 Terra, high | Validation-only | Re-run canonical checks, audit evidence, and classify the exact failing layer without tracked edits. |

Within Lane 3, use `hard_implementer` if writer classification is uncertain.
Do not silently substitute a different model when a pinned model is
unavailable.

## Change classification and routing

The main session records the lane before delegation and alone may reclassify
it. Classify by the highest semantic effect, never by file extension, diff
size, or file count.

| Lane | Boundary | Required routing |
| --- | --- | --- |
| 1 - mechanical docs | Spelling, formatting, or equivalent link correction with no normative, product, API, authority, gate, evidence, milestone, build, or security meaning change. | Main-session reconnaissance; one `fast_implementer`; focused documentation/link/diff checks. No explorer, reviewer, verifier, or register. |
| 2 - governance/semantic docs | Agent rules, execution plans, CI instructions, evidence claims, milestone records, security guidance, or other semantic docs without product/runtime behavior. These protected surfaces are Lane 2 minimum. | Main-session reconciliation or one `explorer`; one `fast_implementer`; one independent governance/authority `reviewer`; focused validation. Mandatory verifier for the triggers defined below. |
| 3 - product/milestone | Runtime/API/test/build/schema/tooling behavior, executable CI wiring, milestone implementation or evidence generation, requirements-mapping behavior, correctness/performance gates, or mixed work containing any of these. | Full Lane 3 workflow. |

Doubt escalates upward; silent downgrade is prohibited. Mixed work takes the
highest lane unless the main session creates genuinely independent envelopes.
Do not split work to evade review. A writer that discovers behavior outside its
recorded lane stops, preserves the current diff, and reports the overflow for
root reclassification.

Exactly one physical writer and no descendant delegation apply in every lane.
The discovering reviewer or verifier exclusively decides and declares finding
closure. The main session exclusively controls classification/reclassification,
orchestration, process or milestone acceptance, completion, and progression.
Every security-adjacent delegation still requires the complete defensive task
envelope and explicit exclusions.

### Lane 1 workflow

1. The main session performs targeted read-only reconnaissance and records
   Lane 1 before delegation.
2. One `fast_implementer` makes only the bounded mechanical edit.
3. Run affected documentation, local-link, and diff checks. On any doubt or
   expanded meaning, stop and escalate to Lane 2 or Lane 3.

Lane 1 has no explorer, reviewer, verifier, or findings register.

### Lane 2 workflow

1. The main session records Lane 2 and either reconciles the affected
   governance surfaces itself or activates one read-only `explorer`.
2. One `fast_implementer` makes the bounded semantic-documentation change and
   runs focused validation.
3. One independent `reviewer` checks governance, authority, semantic
   consistency, and classification bypass risk.
4. A `gate_verifier` is mandatory if the diff changes governance/process-only
   authority boundaries, documentary workflow gate definitions or commands,
   acceptance-evidence statements, or milestone acceptance facts; normally
   omit it otherwise.
5. Return material actionable findings to the same writer. After the
   discovering role reports closure, the main session accepts the process
   change and directs the selected writer to record any closure status.

Clean reviews and non-material hygiene observations do not create registered
findings. Lane 2 findings are governed by the process register below.
Lane 2 may document process routing and checks, but it cannot change product
or milestone correctness or performance gates, acceptance criteria, required
milestone command sets, or executable wiring. Any such change is Lane 3.

## Lane 3 adversarial contract review

Before writer activation for correctness-sensitive work, the main session and
explorer record an adversarial contract matrix in the task envelope or
milestone evidence. Cover every applicable boundary:

- ownership, lifetime, aliasing, stale reuse, exhaustion, and cleanup;
- untrusted parsing, truncation, malformed values, and checked arithmetic;
- mutation, finalization, partial failure, and invalid-output prevention;
- concurrency, ordering, publication, cancellation, and shutdown;
- FFI/adapters, representation, provenance, and backend token transfer;
- policy/state semantics, capability denial, defaults, and bounded resources;
- quantitative gates, instrumentation validity, negative controls, and
  artifact binding.

Mark non-applicable boundaries explicitly. Before the writer starts, the main
session also selects the independent reviewer perspectives and records the
focused preflight and final gate commands. Public behavior that remains
unspecified returns to the user; it is not resolved by the writer.

## Lane 3 product and milestone workflow

1. The main session performs the mandatory `AGENTS.md` startup checks and
   states the active milestone, exit gate, and intended verification.
2. Spawn at least one `explorer` for a new feature or milestone envelope.
   Multiple explorers are allowed only for independent, bounded read-only
   questions. One activation remains valid for focused remediation within an
   unchanged envelope; do not respawn solely because review found a defect.
   Re-explore when scope, requirements, public behavior, architecture, or
   relevant repository state changes materially, or when milestone-exit
   reconciliation has not occurred.
3. The main session resolves genuinely unspecified public behavior with the
   user, completes the adversarial contract review when applicable, preselects
   reviewer perspectives, and creates a bounded implementation handoff with
   focused preflight and final exact-tree gate commands.
4. Spawn exactly one implementer as the sole tracked-file writer. The writer
   keeps code, tests, documentation, mappings, cleanup paths, and relevant
   benchmark deltas together and runs narrow checks while iterating.
5. Stop the writer after it reports a stable diff. Spawn the selected
   `reviewer` instances and `gate_verifier` independently; they may run
   concurrently. The verifier runs only the focused affected preflight at this
   stage.
6. Record actionable findings in the milestone evidence closure register and
   return them to the same implementer thread. The discovering reviewer or
   verifier closes its own findings after focused remediation checks pass.
7. For a correctness-sensitive milestone exit that produced a Critical or High
   finding, run a fresh unanchored full-diff review after those findings close.
   Give that reviewer the requirements, task envelope, and complete diff, not a
   remediation checklist.
8. After every blocking finding is closed, have `gate_verifier` run one final
   exact-tree full gate. If it fails and the tree changes to correct the
   failure, repeat the full gate on the corrected exact tree.
9. The main session accepts the gate, then directs the selected sole writer to
   record compact status and evidence. This recording task gives the writer no
   gate-acceptance authority. A feature does not complete its milestone unless
   every milestone condition passes.

Do not run `fast_implementer` and `hard_implementer` as writers concurrently.
A writer handoff requires the current writer to stop and report changed paths,
verification already run, unresolved findings, and pending work.

## Lane 3 milestone-exit workflow

Before accepting a milestone exit:

1. Ensure an `explorer` has reconciled the entire milestone checklist,
   normative requirements, archived exit gate, local additions, code, tests,
   documentation, benchmark deltas, and cleanup evidence. Reuse a still-valid
   reconciliation for an unchanged envelope.
2. Use `hard_implementer` for any remaining correctness- or gate-sensitive
   remediation.
3. Run one or more `reviewer` instances with the preselected perspectives:
   core packet ownership/mutation, concurrency/QSBR, adapter/FFI,
   language/security, or performance methodology.
4. Close blocking findings, including any required fresh unanchored review,
   then run `gate_verifier` on the final exact tree. The command set includes
   Debug, ReleaseSafe, ReleaseFast, and every required fuzz, model, adapter,
   documentation, schema, benchmark, or cross-target check.
5. Accept the gate only when verification passes, no blocking review finding
   remains, artifacts exist, and `planning/IMPLEMENTATION_PROGRESS.md`
   accurately reports the evidence.

Later-milestone work may run only as an explicitly labelled bounded spike. Its
code and measurements do not satisfy the later gate or advance the ledger.

## Finding and remediation contract

Lane 1 has no findings register.

### Lane 2 process register

Record only material actionable findings that require remediation in
`evidence/process/REVIEW.md`, using stable
`PROC-<PERSPECTIVE>-NNN` identifiers. Record status, severity, discovering
role, assigned implementer, affected workflow, observed issue, bounded
remediation, required focused checks, addressing evidence, and closure result.
A clean review creates no entry; non-material hygiene may be retained only as
a short unnumbered audit note.

### Lane 3 milestone register

In Lane 3, record each review and verification finding under
`evidence/<milestone>/REVIEW.md` with a stable
`M<milestone>-<perspective>-NNN` identifier, such as `M2-CORE-001`. Each entry
reports:

- status: `open`, `addressed`, or `closed`;
- severity and affected requirement, invariant, or gate;
- discovering role and assigned implementer;
- file, symbol, command, or artifact evidence;
- expected versus observed behavior;
- reproduction steps and randomized seed or minimized trace when applicable;
- the precise failing layer;
- a bounded remediation and the checks that must be repeated;
- the addressing diff/evidence and closure result.

### Finding authority

Only the implementer may declare `addressed`; only the reviewer or verifier
that discovered the finding may declare `closed` after rerunning its required
checks. Those read-only roles report closure without editing tracked files; the
selected sole writer records the reported status at the main session's
direction. Recording a status gives the writer neither closure nor acceptance
authority. The verifier never fixes failures. The main session routes findings
to the same implementer unless the failure proves that the task was
misclassified.

For Lane 3, intermediate diffs receive only narrow affected checks and focused
preflight. Run the expensive cumulative gate once, after blocking findings
close. A failed full gate must be repeated after any corrective tree change.
If a passing full gate is followed only by acceptance wording in evidence or
the progress ledger, rerun affected documentation, schema, link, and diff
checks; rerun the full gate if executable code, test inputs, build wiring,
schemas consumed by the gate, or other gate inputs changed.

## Progress records

`planning/IMPLEMENTATION_PROGRESS.md` contains milestone starts, blocked or
reopened states, material gate changes, and final acceptance. Store
per-finding and remediation chronology, repeated command results, seeds, and
full logs in the applicable milestone or process closure register instead of
adding a ledger row for every review cycle.

## Hardware boundary

M0-H, M4, and later physical acceptance require their documented hardware,
testbed, permissions, and user decisions. Explorers and verifiers must report
missing resources precisely. Virtual PMD, synthetic, loopback, or local
benchmark evidence cannot be relabelled as physical acceptance or production
capacity evidence.

## Current Lane 3 activation example: M2

M2 is the next predecessor-gated milestone and remains `Not started` until the
main session activates it. Its implementation packet must cover active
selection, dispositions and output grouping, lazy L2/L3/L4 parsing and
fragment semantics, structured mutation and the trusted raw-editor capability
boundary, mutation journaling and failure-atomic checksum/length finalization,
and bounded retention leases. Its exit gate is AC-001, AC-002, AC-010, and all
packet-related invariants, with proof that injected mutation failure cannot
transmit a corrupted packet.

Preselect these M2 reviewer perspectives before writer activation:

- core packet ownership, selection, dispositions, mutation, and finalization;
- language/security for untrusted parsing and raw-editor boundaries;
- performance methodology for parser/no-op baselines and instrumentation;
- adapter/FFI only if that boundary changes;
- concurrency only if shared ownership or synchronization is introduced.

The ordinary routing is:

1. `explorer` reconciles the M2 checklist, contracts, relevant M1 boundaries,
   and required evidence, and the main session records the adversarial matrix.
2. `hard_implementer` owns the M2 public contracts and implementation;
   `fast_implementer` is limited to a separately bounded low-risk follow-up.
3. Intermediate preflight is `nix develop --command zig build test` plus the
   explicitly named affected M2 property, differential, benchmark, and
   documentation steps introduced in the task envelope.
4. After blocking findings close, `gate_verifier` runs
   `nix develop --command zig build ci` on the exact final tree. That cumulative
   gate must cover Debug, ReleaseSafe, ReleaseFast, AArch64, truncation and
   fragment cases, Scapy differential checks, failure atomicity, lease
   exhaustion/leak checks, requirement mappings, documentation, schemas, and
   parser/no-op baselines for batches 1/4/8/16/32/64.
