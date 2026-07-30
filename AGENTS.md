# Saint Shield Agent Instructions

These instructions apply to the entire workspace.

## Start every implementation session here

Before changing code:

1. Read `planning/LOCAL_EXECUTION_PLAN.md`.
2. Read `planning/IMPLEMENTATION_PROGRESS.md` and identify the first incomplete
   predecessor-gated milestone.
3. Read the specification and technical-plan files required by the execution
   plan. Do not rely on a prior chat summary instead of the checked-in sources.
4. Verify the unpacked archive if its contents changed:

   ```sh
   cd planning/specification/l4-protection-framework-technical-plan
   sha256sum -c MANIFEST.sha256
   cd source-requirements
   sha256sum -c MANIFEST.sha256
   ```

5. State the active milestone, applicable exit gate, and intended verification
   before implementation.

## Requirement authority and change control

- Normative product requirements under `source-requirements/` outrank every
  implementation document.
- The unpacked technical plan is the accepted architecture baseline. Treat the
  entire `planning/specification/` tree as immutable source material.
- `planning/LOCAL_EXECUTION_PLAN.md` contains accepted local decisions,
  including the M0-V/M0-H split, Nix workflow, and x86-first support policy.
- `planning/IMPLEMENTATION_PROGRESS.md` records facts and evidence only.
- Do not weaken an invariant, acceptance criterion, quantitative gate, version
  pin, or scope boundary to make a test pass.
- If an accepted technical decision must change, write an ADR with the
  required correctness/benchmark evidence and migration impact. Put ADRs under
  `docs/adr/` once the M0 scaffold exists.
- If product intent is genuinely unspecified and the choice affects public
  behavior, stop and ask the user. Do not invent policy syntax, failure modes,
  state semantics, hardware targets, or remote protocols.
- A technical implementation detail may be resolved by a bounded spike when
  the plan identifies a provisional decision. Preserve the experiment and ADR.

## Milestone and progress discipline

- Work in dependency order: M0-V, M1, M2, M3. M0-H is independently deferred
  but is mandatory before M4 acceptance.
- Before starting a milestone, set it to `In progress`, add the date, and name
  the expected gate in `planning/IMPLEMENTATION_PROGRESS.md`.
- During work, keep requirement/test mappings, documentation, cleanup paths,
  and benchmark deltas alongside code. They are not end-of-project cleanup.
- Mark a checklist item only after its evidence exists.
- Mark a milestone `Complete` only after all archived and local exit conditions
  pass. Record exact commands and artifact paths in the progress ledger.
- If a gate fails, keep the milestone `In progress` while a safe corrective
  path remains. Use `Blocked` only for an external dependency or user decision
  that actually prevents progress, and record the precise unblock condition.
- Do not begin the main body of the next milestone until the predecessor gate
  passes. Clearly label later-risk work as a spike.
- Keep the progress ledger compact: record milestone starts, blocked or
  reopened states, material gate changes, and final acceptance. Keep individual
  findings, remediation chronology, and command output in the applicable
  milestone or process evidence closure register.

## Build and dependency workflow

- Use the workspace Nix flake and enter it with `nix develop` once M0-V creates
  it. Keep `zig build` as the canonical interface within that environment.
- Pin Zig 0.16.0 exactly.
- Build DPDK 25.11.2 from the pinned workspace derivation; never silently use
  the current Nixpkgs DPDK 26.03 package.
- Do not install global packages or change `/etc/nixos` for M0-V through M3.
- Virtual DPDK tests must use a no-hugepage/virtual-PMD configuration and must
  not require VFIO, NIC rebinding, or permanent privilege changes.
- Request scoped approval for dependency downloads or privileged experiments.
  Do not work around sandbox or network policy.
- Treat Scapy, fuzzers, TLA+, Prometheus fixtures, and benchmark generators as
  test/tooling dependencies unless the architecture explicitly assigns them to
  an optional module. They are not core runtime dependencies.

## Change classification

Before delegation, the main session records one lane from the highest semantic
effect of the proposed work. File extension, diff size, and file count never
lower classification.

- **Lane 1 - mechanical documentation:** spelling, formatting, or an equivalent
  link correction only, with no change to normative, product, API, authority,
  gate, evidence, milestone, build, or security meaning. The main session
  performs focused reconnaissance, selects exactly one `fast_implementer`, and
  requires only affected documentation, link, and diff checks. Do not activate
  an explorer, reviewer, verifier, or findings register.
- **Lane 2 - governance or semantic documentation:** agent rules, execution
  plans, CI instructions, evidence claims, milestone records, security
  guidance, or other semantic documentation that does not change
  product/runtime behavior. These protected surfaces are Lane 2 minimum even
  for a tiny diff. Use main-session reconciliation or one `explorer`, exactly
  one `fast_implementer`, one independent governance/authority `reviewer`, and
  focused validation. A `gate_verifier` is mandatory when the diff changes
  governance/process-only authority boundaries, documentary workflow gate
  definitions or commands, acceptance-evidence statements, or milestone
  acceptance facts; normally omit it otherwise. Lane 2 may document process
  routing and checks, but it cannot change product or milestone correctness or
  performance gates, acceptance criteria, required milestone command sets, or
  executable wiring. Any such change is Lane 3. Record only material
  actionable findings that require remediation as
  `PROC-<PERSPECTIVE>-NNN` in `evidence/process/REVIEW.md`.
- **Lane 3 - product or milestone:** runtime, API, test, build, schema, or
  tooling behavior; executable CI wiring; milestone implementation or evidence
  generation; requirements-mapping behavior; correctness/performance gates; or
  any mixed change containing these. Use the full workflow below.

Only the main session classifies or reclassifies work. Doubt escalates upward;
there is no silent downgrade. Mixed work takes its highest lane unless split
into genuinely independent envelopes, never to evade review. A writer that
discovers scope outside its lane stops and reports it. Exactly one physical
writer, no descendant delegation, and the security-adjacent task-envelope
rules apply in every lane. The discovering reviewer or verifier exclusively
decides and declares finding closure. The main session exclusively controls
classification/reclassification, orchestration, process or milestone
acceptance, completion, and progression.

## Multi-agent implementation workflow

- The user-controlled main session is the only orchestrator. Do not create or
  use a custom orchestration agent, and delegated agents must not delegate
  further.
- Follow `.codex/AGENT_WORKFLOW.md` for role selection, task envelopes,
  handoffs, review perspectives, and gate acceptance.
- Begin every Lane 3 feature or milestone envelope with the read-only
  `explorer`. One activation covers focused remediation while that bounded
  envelope remains unchanged; re-explore after a material scope, requirement,
  public-behavior, architecture, or relevant repository-state change, or when
  milestone-exit reconciliation has not occurred.
- Before activating the Lane 3 writer for correctness-sensitive work, the main
  session must record an adversarial contract review, select the applicable
  independent reviewer perspectives, and name both the focused preflight and
  final exact-tree gate commands.
- Select exactly one tracked-file writer according to the recorded lane.
  Within Lane 3, use `fast_implementer` for small, explicit, low-risk changes
  or `hard_implementer` for the main body of a milestone and every
  correctness-, architecture-, or performance-sensitive change. When
  uncertain, use `hard_implementer`.
- Never run both implementers as writers concurrently. A writer handoff
  requires the current writer to stop and report changed paths and pending
  work.
- After a Lane 3 writer yields a stable diff, run `reviewer` and
  `gate_verifier` independently. Intermediate verification uses focused
  affected checks; run the full exact-tree gate after all blocking findings
  close.
- Give every registered Lane 2 or Lane 3 finding a stable ID and return it to
  the same implementer for remediation. The implementer declares it
  `addressed`; the reviewer or verifier that discovered it reruns the required
  checks and alone may declare it `closed`. These read-only roles report
  status; they do not edit tracked files.
- Only the main session may decide to accept a milestone gate, decide that a
  milestone is complete, or begin the next milestone. It directs the selected
  sole writer to record those decisions; this does not grant the writer closure
  or acceptance authority or make the main session a second writer.

### Incremental Git discipline for Lane 3 milestones

- Implement each unfinished Lane 3 milestone on one local branch named
  `milestone/<lowercase-id>`, based on the accepted predecessor state on local
  `main`. Only one milestone branch may be active. Resume an existing exact-name
  branch; do not create an alternate. A deferred milestone or later-risk spike
  gets a separate branch only after explicit main-session activation.
- The task envelope records the concrete local `main` baseline hash, milestone
  branch, clean status, allowed paths, focused checks for each slice, and final
  exact-tree gate, plus the exact envelope-specific post-integration commands
  selected by the main session. Before branch creation, resumption, switching,
  or integration, inspect all tracked and untracked status. If it is dirty, or
  an existing branch does not have the recorded `main` base, stop for user
  direction; never auto-stash, reset, or absorb unrelated work.
- The selected sole writer exclusively creates or switches branches, stages
  explicit paths, commits or performs the permitted WIP-tip amendment, and,
  when directed by the main session, squash-integrates and deletes the local
  branch. No agent pushes, force-pushes, deletes a remote branch, or otherwise
  mutates a remote without separate user authorization.
- The first milestone-branch commit records `In progress`, its date, and the
  expected gate. Commit every coherent vertical slice with its tests, mappings,
  documentation, cleanup paths, and applicable evidence after focused checks
  pass and the staged diff is reviewed. A single `wip(<id>): ...` commit may be
  the branch tip across sessions, but it must be amended into a finished
  semantic commit before another slice, review, or verification.
- Reviewers inspect the complete declared `BASE..TIP` and worktree status.
  Completed or reviewed commits are not rewritten; remediation uses new
  commits. The final gate runs only on a clean, committed, non-WIP tip and is
  bound to its commit and tree hashes. A corrective tree change requires a new
  commit and a repeated full gate.
- After gate acceptance, the writer commits permitted acceptance-only evidence
  and ledger wording under the existing post-gate rules. It then confirms
  local `main` is still the recorded baseline, squash-integrates to
  `milestone(<id>): complete <ledger title>`, records the final branch tip and
  gated commit/tree in the commit body, proves branch/main tree identity, runs
  the recorded exact post-integration commands, and confirms clean status. Only
  then, and only on main-session direction, may it force-delete the exact local
  branch because a squash is not ancestral. Any mismatch, advanced `main`, or
  check failure leaves the branch intact and returns the decision to the user.

Ordinary Lane 1 and Lane 2 maintenance does not use milestone branches.

## Cybersecurity safety and precise task framing

These rules apply to every agent working in this workspace, including any
delegated agent. Saint Shield is an authorized defensive packet-processing
project, but its low-level networking and protection work is inherently
dual-use and may receive additional automated review.

- Do not attempt to evade, suppress, probe, or reverse-engineer a safety
  classifier. Do not use euphemisms, keyword substitution, encoding, prompt
  fragmentation, omitted intent, or another agent to disguise a request.
- Describe work truthfully and precisely. When security context is material,
  state the authorized local target, the defensive outcome, the current
  milestone or requirement, and the applicable sandbox or test boundary.
- Keep requests and responses limited to the context and technical detail
  needed to identify, prevent, test, or remediate the issue. Do not add
  operational exploit instructions, chained exploitation, credential access,
  data exfiltration, malware deployment, destructive actions, broad scanning,
  or third-party targeting when they are unnecessary to the defensive result.
- Prefer repository-owned code, synthetic packets, deterministic fixtures,
  virtual PMDs, loopback or isolated test environments, and minimal
  reproductions. Never imply authorization for an external system, account,
  network, or dataset merely because it is reachable.
- Use ordinary engineering terminology where it is accurate. Do not
  mischaracterize packet parsing, fuzzing, malformed-input tests, or benchmark
  generation as offensive activity; equally, do not relabel offensive work as
  testing or research.
- When delegating security-adjacent work, include the defensive objective,
  authorized target, required evidence, and explicit out-of-scope actions in
  the task. The receiving agent must preserve these constraints in its own
  requests and output.
- If an additional safety check interrupts allowed work, do not repeatedly
  reword the same request to get around it. Narrow the task to the minimum
  necessary defensive outcome without hiding material intent. If it remains
  blocked, record the exact notice, product/model, date and time zone, request
  ID when available, and a brief redacted task description; then use
  `/feedback` or OpenAI Support. Consider Trusted Access for Cyber when
  legitimate high-risk defensive research routinely requires it.

OpenAI publicly describes the relevant safeguards as a topical classifier over
both prompts and generations followed by a safety reasoner for harmful or
high-risk dual-use content. The system is intentionally optimized for high
recall, so false positives can occur; wording alone neither changes whether a
request is allowed nor guarantees delivery. Reference:

- <https://help.openai.com/en/articles/20001326-additional-safety-checks-for-biological-and-cybersecurity-requests-in-chatgpt-codex-and-the-api>
- <https://openai.com/index/trusted-access-for-cyber/>
- <https://openai.com/policies/usage-policies/>
- <https://cdn.openai.com/pdf/23eca107-a9b1-4d2c-b156-7deb4fbc697c/GPT-5-3-Codex-System-Card-02.pdf>

## Verification and handoff

- For Lane 3, run the narrowest relevant tests while iterating, then one final
  exact-tree full milestone gate after blocking findings close. Repeat that
  full gate after any corrective tree change caused by a gate failure.
- Acceptance-only evidence or ledger edits after a passing gate require only
  the affected documentation, schema, link, and diff checks unless executable
  or gate inputs changed.
- Test Debug and ReleaseSafe semantics continuously; include ReleaseFast at the
  M0-V and milestone exit gates.
- Randomized tests must print a reproducible seed and minimized trace.
- Constructor/preparation paths require allocation-failure and cleanup
  accounting where specified.
- Performance results from this local virtual/synthetic environment are
  regression evidence only, never production capacity claims.
- Preserve unrelated user changes. Do not destructively reset or delete work.
- End each implementation run with the achieved milestone status, changed
  paths, verification evidence, unresolved limitations, and the next gated
  action. Ensure `planning/IMPLEMENTATION_PROGRESS.md` matches that report.
