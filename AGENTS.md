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

## Verification and handoff

- Run the narrowest relevant tests while iterating, then the full milestone
  gate before completion.
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
