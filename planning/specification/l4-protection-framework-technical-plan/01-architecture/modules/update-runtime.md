# Module: Artifacts and Update Runtime

## Responsibility

Represent versioned artifacts; serialize activations; prepare candidate processor parts; validate compatibility/resources; publish complete generations; track worker adoption; retain/retire/reclaim generations; and perform compatible rollback. Sources are separate adapters.

## Artifact identity

```text
Artifact {
  source_id?, revision, content_type, payload,
  received_monotonic_time, provenance, semantic_digest?
}
```

`revision` is opaque to the framework except through an application-selected ordering policy. Equality, ordering, deduplication, and stale rejection are not inferred from strings. Payload ownership transfers to or is copied into the update session according to an explicit constructor.

## Session API behavior

- `beginUpdate(base?)` captures the expected base and resource policy.
- `prepareProcessor` is idempotent only when the processor documents it; the session tracks one final part per binding.
- `validate` checks every binding, cross-dependency, state transition, resource, output, schema, and registered identifier.
- `activate` is serialized and uses compare-with-base if requested.
- `abort` may run from Created through Validated and is idempotent.
- `rollback(target)` internally builds/validates a new candidate.

Sessions are not thread-safe unless wrapped by the application. Prepared artifacts are not visible to workers.

## Resource controls

Budgets cover candidate bytes, per-worker bytes, retained-generation bytes/count, preparation wall/CPU time, parser diagnostic count, state migration work, and optional shadow validation. If retaining the new plus previous generation exceeds the hard limit, validation fails before publication.

## State transition compatibility

Every stateful processor returns a transition plan: retain-compatible, lazy revalidate, eager migrate, flush, or unsupported. Cross-worker eager migration must happen off-path into candidate state; activation cannot pause workers for unbounded migration.

## Source adapters

Static and direct submission come first, watched-file later. A source emits an artifact and source-local status. It never opens a session or decides grouping. A remote stream must authenticate/authorize outside core, apply bounded message sizes, document ordering/retry, and support cancellation.

## Tests and model

- Exact source requirements AC-004..007 and AC-011..012.
- Candidate failure at every allocation/construction step.
- Publication under continuous deterministic load with generation-stamped outputs.
- Worker stall/online/offline/unregister/shutdown at every QSBR step.
- Repeated update/rollback cycles with leak accounting.
- Base-generation compare conflict and stale/duplicate/out-of-order application policies.
- TLA+ model is a required predecessor, not post-hoc documentation.

## Requirement ownership

FR-SRC-001..006, FR-UPD-001..010, FR-STATE-005..006, AC-004..007, AC-011..012.

