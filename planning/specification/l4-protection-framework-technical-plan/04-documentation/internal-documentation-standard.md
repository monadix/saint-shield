# Internal Technical Documentation Standard

The goal is to make a low-level decision locally understandable: what owns memory, who may call it, what can block, which invariant it preserves, and what evidence justified the shape. More prose is not automatically better.

## Required layers

### 1. Module design record

Every top-level source module has `docs/internals/modules/<name>.md` based on the template here. It states responsibility/non-responsibility, dependency direction, public/internal boundary, object lifecycles, concurrency/ownership, allocations, failure/overload behavior, invariants, performance budget, tests, and evolution points. Update it in the same change that changes those facts.

### 2. Zig documentation comments

- `//!` at each public module: purpose, central invariant, context restrictions, minimal example/reference.
- `///` on every public declaration: semantic contract, ownership/lifetime, error meanings, thread safety, packet-path safety, units/ranges, and capability prerequisites.
- Private declarations receive comments only for non-obvious why/invariant/algorithm facts.

Generated Zig documentation is a convenience and remains experimental in Zig 0.16, so a public module is not documented merely because its symbols appear in autodoc.

### 3. Local correctness comments

Use these searchable prefixes:

- `INVARIANT(INV-...)`: a stable system invariant relied upon here.
- `SAFETY`: why pointer cast, unchecked access, raw mutation, C layout, or lifetime operation is valid.
- `CONCURRENCY`: memory ordering, owner, or happens-before fact that is not obvious.
- `PERF(BENCH-...)`: a non-obvious optimization and its guarding benchmark.
- `COMPAT`: externally visible compatibility constraint.
- `SECURITY`: trust boundary/resource bound.

Every `SAFETY` comment answers provenance, lifetime, bounds/alignment, aliasing, and concurrent access as applicable. Every `PERF` comment names evidence and the simpler implementation it displaced.

### 4. ADR

Use an ADR for technology, public semantic, concurrency algorithm, dependency, persistent format, compatibility, or hard-to-reverse performance choice. The ADR records considered alternatives and objective reversal triggers. Cosmetic refactors do not need ADRs.

### 5. Formal/executable design

Concurrent protocols with non-local interleavings use TLA+/PlusCal plus a mapping note from model actions/variables/invariants to code/tests. Wire/artifact formats use grammar or schema plus golden examples. Packet state machines use transition tables. These are reviewed as code.

## Required function-level facts

For a hot-path public function, document:

```text
Context: packet worker / management / observability
Complexity: worst-case or configured bound
Allocation: none / bounded pool name / allocator parameter
Blocking: never / conditions off-path
Ownership: borrows/transfers/returns
Thread safety: owner or allowed callers
Errors: each category and packet/generation effect
```

This can be concise natural prose; do not paste a rigid block when the signature/type already proves a fact.

## Diagrams

Use Mermaid only for topology, state, ownership transitions, or event order with at least three meaningful nodes/states. Tables are preferred for mappings and contracts. A diagram must not be the only normative description.

## Review checklist

- Can a reviewer identify the owning allocator/backend for every pointer?
- Is every cross-thread field's atomic order and cache-line ownership documented?
- Is hot-path blocking/allocation status explicit?
- Do failure paths describe packet/generation state after failure?
- Are bounds and exhaustion outcomes named?
- Is an unsafe/FFI layout assertion tested?
- Does a performance trick have a benchmark and a simpler fallback?
- Did requirements/invariants/tests/docs change together?

