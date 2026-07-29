# Saint Shield Multi-Agent Workflow

The user-controlled main session is the sole orchestrator. It owns task
decomposition, agent activation, handoffs, user decisions, gate acceptance,
and final progress-ledger updates. No custom orchestrator agent exists, and
project subagents must not spawn descendants.

## Required task envelope

Every delegated task names:

- the authorized target: this Saint Shield repository;
- the defensive or engineering outcome;
- the active milestone and applicable requirement, invariant, or gate;
- the permitted synthetic, virtual, or hardware boundary;
- the exact in-scope question or change and explicit exclusions;
- whether the role is read-only, validation-only, or the sole writer;
- the expected evidence and output format.

Security-adjacent tasks must also state that external targeting, broad
scanning, credential access, exploitation, exfiltration, malware deployment,
and destructive actions are out of scope unless a separately authorized
defensive task genuinely requires a narrower action.

## Roles and routing

| Role | Model | Authority | Use |
| --- | --- | --- | --- |
| `explorer` | GPT-5.6 Terra, medium | Read-only | Establish requirements, current code paths, risks, task slices, and verification before edits. |
| `fast_implementer` | GPT-5.6 Luna, medium | Sole writer | Small, explicit, low-risk documentation, fixture, test, evidence-formatting, or mechanical internal changes. |
| `hard_implementer` | GPT-5.6 Sol, xhigh | Sole writer | Public contracts, ownership, cleanup, untrusted inputs, concurrency, FFI/adapters, pins, policy/state semantics, performance, and cross-module work. |
| `reviewer` | GPT-5.6 Sol, high | Read-only | Independent owner review against requirements, invariants, tests, and the assigned specialist perspective. |
| `gate_verifier` | GPT-5.6 Terra, high | Validation-only | Re-run canonical checks, audit evidence, and classify the exact failing layer without tracked edits. |

If implementer classification is uncertain, use `hard_implementer`. Do not
silently substitute a different model when a pinned model is unavailable.

## Feature workflow

1. The main session performs the mandatory `AGENTS.md` startup checks and
   states the active milestone, exit gate, and intended verification.
2. Spawn at least one `explorer`. Multiple explorers are allowed only for
   independent, bounded read-only questions.
3. The main session resolves any genuinely unspecified public behavior with
   the user and creates a bounded implementation handoff.
4. Spawn exactly one implementer as the sole tracked-file writer. The writer
   keeps code, tests, documentation, mappings, cleanup paths, and relevant
   benchmark deltas together and runs narrow checks while iterating.
5. Stop the writer after it reports a stable diff. Spawn `reviewer` and
   `gate_verifier` independently; they may run concurrently.
6. Return actionable findings to the same implementer thread. Repeat focused
   review and verification after remediation.
7. The main session records the achieved status and evidence. A feature does
   not complete its milestone unless every milestone condition passes.

Do not run `fast_implementer` and `hard_implementer` as writers concurrently.
A writer handoff requires the current writer to stop and report changed paths,
verification already run, unresolved findings, and pending work.

## Milestone-exit workflow

Before accepting a milestone exit:

1. Have `explorer` reconcile the entire milestone checklist, normative
   requirements, archived exit gate, local additions, code, tests,
   documentation, benchmark deltas, and cleanup evidence.
2. Use `hard_implementer` for any remaining correctness- or gate-sensitive
   remediation.
3. Run `gate_verifier` on the full milestone command set, including Debug,
   ReleaseSafe, ReleaseFast, and every required fuzz, model, adapter,
   documentation, schema, benchmark, or cross-target check.
4. Run one or more `reviewer` instances with the required perspectives:
   core packet ownership/mutation, concurrency/QSBR, adapter/FFI,
   language/security, or performance methodology.
5. Accept the gate only when verification passes, no blocking review finding
   remains, artifacts exist, and `planning/IMPLEMENTATION_PROGRESS.md`
   accurately reports the evidence.

Later-milestone work may run only as an explicitly labelled bounded spike. Its
code and measurements do not satisfy the later gate or advance the ledger.

## Failure and remediation contract

Review and verification findings report:

- severity and affected requirement, invariant, or gate;
- file, symbol, command, or artifact evidence;
- expected versus observed behavior;
- reproduction steps and randomized seed or minimized trace when applicable;
- the precise failing layer;
- a bounded remediation and the checks that must be repeated.

The verifier never fixes failures. The main session routes them to the same
implementer unless the failure proves that the task was misclassified.

## Hardware boundary

M0-H, M4, and later physical acceptance require their documented hardware,
testbed, permissions, and user decisions. Explorers and verifiers must report
missing resources precisely. Virtual PMD, synthetic, loopback, or local
benchmark evidence cannot be relabelled as physical acceptance or production
capacity evidence.

## Current activation example: M1

M1 is the active predecessor-gated milestone. Its implementation packet must
cover INV-PKT-001 and INV-PKT-002, exact token completion, stale-view and
ownership enforcement, all ranges and segment boundaries, malformed
descriptors, allocation failure for every constructor, bounded classic-PCAP
fuzzing, and unchanged zero-payload-copy traversal through the configured
maximum.

The ordinary routing is:

1. `explorer` reconciles the remaining M1 checklist and evidence gaps.
2. `hard_implementer` owns packet ownership, lifetime, parser, allocator, or
   cross-module remediation; `fast_implementer` is limited to a separately
   bounded low-risk follow-up.
3. `reviewer` uses the core packet ownership perspective.
4. `gate_verifier` runs the narrow affected tests and then the full M1 gate in
   Debug, ReleaseSafe, and ReleaseFast, including the PCAP fuzz smoke,
   documentation, mappings, and zero-copy evidence.
