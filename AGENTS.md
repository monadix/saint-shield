# Saint Shield Agent Instructions

These instructions apply to the entire workspace. The user-controlled main
session is the only orchestrator. Delegated agents never delegate.

## Start every implementation session here

Before changing tracked files:

1. Read `planning/LOCAL_EXECUTION_PLAN.md`.
2. Read `planning/IMPLEMENTATION_PROGRESS.md`; identify the first incomplete
   predecessor-gated milestone without changing its state.
3. Read the specification and technical-plan files required by the execution
   plan. Checked-in sources, not chat summaries, are authoritative.
4. If `planning/specification/` changed, verify both manifests:

   ```sh
   cd planning/specification/l4-protection-framework-technical-plan
   sha256sum -c MANIFEST.sha256
   cd source-requirements
   sha256sum -c MANIFEST.sha256
   ```

5. State the active milestone, applicable exit gate, intended verification,
   change lane, and delegation plan before implementation.

## Authority and change control

Authority descends in this order:

1. normative product requirements under
   `planning/specification/l4-protection-framework-technical-plan/source-requirements/`;
2. the accepted architecture under `planning/specification/`, frozen except
   during the separately activated specification-maintenance workflow;
3. accepted local decisions in `planning/LOCAL_EXECUTION_PLAN.md`;
4. implementation facts and evidence in
   `planning/IMPLEMENTATION_PROGRESS.md`.

Do not weaken an invariant, acceptance criterion, quantitative gate, version
pin, or scope boundary to make a check pass. An accepted technical change
requires an ADR with correctness or benchmark evidence and migration impact.
If unspecified product intent affects public behavior, stop for the user's
decision. A plan-designated provisional detail may use a bounded, preserved
spike and ADR.

The main session alone classifies or reclassifies work, activates milestones,
accepts process or milestone gates, records completion decisions, and permits
progression. The selected sole writer makes tracked-file and physical Git
changes at main-session direction. A reviewer or verifier alone closes its own
finding after rerunning the required checks.

## Milestones, builds, and evidence

- Work in predecessor order. M0-H is independently deferred but mandatory
  before M4 acceptance. Label later-risk work as a spike.
- Before production work starts, set its milestone to `In progress`, date it,
  and name the expected gate. Mark an item or milestone complete only after its
  evidence and every archived and local exit condition pass.
- Keep code, tests, requirement mappings, documentation, cleanup behavior, and
  benchmark deltas together. Put findings and command detail in the applicable
  evidence register; keep the progress ledger compact.
- Use the workspace Nix flake and canonical `zig build` interface. Zig remains
  exactly 0.16.0 and DPDK exactly 25.11.2 from the pinned derivation.
- M0-V through M3 require no global packages, `/etc/nixos` changes, VFIO, NIC
  rebinding, huge pages, or permanent privileges. Use synthetic inputs and
  no-hugepage virtual PMDs; request scoped approval for downloads or privileged
  experiments.
- Scapy, fuzzers, TLA+, Prometheus fixtures, and benchmark generators are
  tooling dependencies unless the architecture assigns them otherwise.

## Change lanes

Classify by the highest semantic effect, never by extension, diff size, or file
count. Mixed work takes its highest lane. Do not split work to evade review.

- **Lane 1 — mechanical documentation:** spelling, formatting, or equivalent
  link repair only, with no normative, product, API, authority, gate, evidence,
  milestone, build, or security meaning. The main session edits directly and
  runs focused documentation/link/diff checks. No delegation or register.
- **Lane 2 — governance or semantic documentation:** agent rules, execution
  plans, evidence claims, milestone records, security guidance, and repo-local
  role instructions or wiring without product/runtime or executable project
  tooling effect. Use one sole writer and one independent governance/authority
  reviewer. Add `gate_verifier` when changing process authority, documentary
  workflow gate definitions or commands, acceptance-evidence statements, or
  milestone acceptance facts. Record only material actionable findings as
  `PROC-<PERSPECTIVE>-NNN` in `evidence/process/REVIEW.md`.
- **Lane 3 — product or milestone:** runtime, API, tests, build, schema,
  executable CI/delivery tooling, milestone implementation/evidence,
  requirements mappings, correctness/performance gates, or any mixed change
  containing them. The standard tier uses one standard writer, independent
  review, and exact-tree verification. The critical tier also uses exploration
  and the hard writer. `.codex/AGENT_WORKFLOW.md` defines tiers and triggers.

Lane 2 cannot alter product or milestone acceptance criteria, required command
sets, correctness/performance gates, or executable project wiring. Doubt and
scope expansion escalate upward; the writer stops instead of self-reclassifying.
Exactly one physical writer applies in every lane.

For High/Critical Lane 3 ownership or lifetime remediations that change
authority-return behavior, follow the mandatory pre-artifact inventory and
review acknowledgment in `.codex/AGENT_WORKFLOW.md`.

## Delegation summary

Follow `.codex/AGENT_WORKFLOW.md` as the canonical runbook for the delegation
test, task envelopes, role and tier selection, fork policy, review,
verification, finding closure, specification maintenance, milestone Git
lifecycle, and retrospective.

Before every spawn, the main session must show why delegation has measurable
parallelism, substantial context isolation, independent assurance, or a
mandatory gate, and why main-session work is not cheaper. Do not spawn for tiny
sequential checks, duplicate exploration, routine status, or an unresolved
product decision. Ceilings are not quotas. Prefer a follow-up on an existing
role thread; new tasks default to `fork_turns="none"` with a self-contained
envelope.

Project role files use the legacy configuration schema accepted by local Codex
0.144.4. Their model and sandbox assignments are intended routing only until
the role-routing smoke in `.codex/AGENT_WORKFLOW.md` proves effective runtime
metadata. Never claim model-specific routing from a task label or role
self-report.

## Lane 3 Git summary

Implement each unfinished Lane 3 milestone on the sole local
`milestone/<lowercase-id>` branch based on the recorded accepted local `main`.
Before branch creation, resumption, switching, or integration, inspect all
tracked and untracked status. Dirtiness, a base mismatch, or advanced `main`
stops for user direction; never auto-stash, reset, clean, or absorb work.

The selected writer alone creates/switches branches, stages explicit paths,
commits coherent slices, amends the one permitted tip-only WIP commit, and
performs main-directed squash integration or exact local-branch deletion.
Reviewers inspect the declared complete `BASE..TIP`. The final gate binds a
clean committed non-WIP tip and tree; any corrective tree change requires a new
commit and repeated gate. After acceptance, prove branch/main tree identity and
run the envelope's exact post-integration commands before main may direct local
branch deletion. Remote mutation always requires separate user authorization.

## Cybersecurity safety

Saint Shield is an authorized defensive packet-processing project. Work only
inside the stated local repository and synthetic, virtual, loopback, isolated,
or explicitly authorized hardware boundary.

- Describe the defensive objective and security context truthfully. Never try
  to evade or reverse-engineer safety systems or disguise a request.
- Do not infer authorization for reachable third-party systems. Exclude broad
  scanning, credential access, exploitation, exfiltration, malware deployment,
  and destructive actions unless a separately authorized defensive task
  genuinely requires a narrower action.
- Prefer repository-owned code, deterministic fixtures, synthetic packets,
  virtual PMDs, and minimal reproductions.
- Use precise engineering terms for parsing, fuzzing, malformed-input tests,
  and benchmarks. Preserve the same boundary in every delegated envelope.
- If an additional safety check blocks allowed work, narrow only to the minimum
  truthful defensive outcome. If still blocked, record the notice, model,
  date/time zone, request ID if available, and a redacted description, then use
  `/feedback` or OpenAI Support. Trusted Access for Cyber may be appropriate
  for recurring legitimate high-risk defensive work.

References:

- <https://help.openai.com/en/articles/20001326-additional-safety-checks-for-biological-and-cybersecurity-requests-in-chatgpt-codex-and-the-api>
- <https://openai.com/index/trusted-access-for-cyber/>
- <https://openai.com/policies/usage-policies/>
- <https://cdn.openai.com/pdf/23eca107-a9b1-4d2c-b156-7deb4fbc697c/GPT-5-3-Codex-System-Card-02.pdf>

## Verification and handoff

Use focused affected checks while iterating. Lane 3 runs one final exact-tree
full milestone gate after blocking findings close and repeats it after any
corrective tree change. Acceptance-only wording after a passing gate needs
focused documentation/schema/link/diff checks unless a gate input changed.
For an independent final Lane 3 exact-tree verification, the main-selected
envelope is the immutable, exact ordered command sequence, including working
directories and arguments. Once verification begins, the verifier may not
add, omit, replace, reorder, or semantically alter a command; any change
requires a new envelope and clean restart. Commands remain
milestone/envelope-specific. The envelope must preserve ordinary clean status
and no new non-ignored state; only declared ignored caches or temporary files
may change, with ignored status recorded before and after. A verifier reports
any ordinary status change and never repairs it. Supplemental diagnostics are
labeled non-gate, provably read-only, immediately bracketed by commit/tree and
ordinary/ignored status, and cannot substitute for the selected commands.
Only the recognized Nix sandbox/user-cache fetcher-lock exception permits a
retry of the identical command with narrow cache authorization and recorded
first failure; other wrappers, arguments, targets, or semantic failures stop
for main direction.
Continuously cover Debug and ReleaseSafe; milestone exits also cover
ReleaseFast. Randomized failures print a seed and minimized trace;
constructor/preparation paths include allocation-failure and cleanup evidence.
Local synthetic/virtual performance is regression evidence, never production
capacity.

Preserve unrelated work. End an implementation run with milestone status,
changed paths, verification, limitations, next gated action, and the canonical
retrospective result. The progress ledger must agree.
