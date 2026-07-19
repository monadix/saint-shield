# L4 Protection Framework Specification

This archive defines the product requirements and abstract public APIs for a Zig framework used to build low-level Layer 4 traffic-protection tools.

The specification is requirements-first. It intentionally does not prescribe a concrete packet I/O library, process topology, scheduling model, memory layout, policy VM, compiler strategy, or internal module graph.

## Normative language

The terms **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** are normative.

- **MUST / MUST NOT**: required for conformance.
- **SHOULD / SHOULD NOT**: expected unless a documented reason justifies deviation.
- **MAY**: optional behavior.

## Document map

1. `00-product-definition.md` — product identity, users, goals, and non-goals.
2. `01-concepts-and-boundaries.md` — framework boundaries and responsibility split.
3. `02-functional-requirements.md` — normative product requirements.
4. `03-abstract-api-contracts.md` — required public abstractions and lifecycle contracts.
5. `04-policy-module-requirements.md` — requirements for the optional standard policy-language module.
6. `05-runtime-and-update-semantics.md` — packet batches, updates, concurrency, and failure behavior.
7. `06-observability-requirements.md` — metrics and event interfaces.
8. `07-delivery-phases.md` — staged feature subsets and dependency order.
9. `08-conformance-and-acceptance.md` — acceptance criteria and conformance rules.
10. `09-deliberately-unspecified.md` — implementation choices intentionally left open.
11. `requirements.yaml` — machine-readable requirement catalogue.
12. `SPECIFICATION.md` — consolidated human-readable specification.

## Intended use

The archive can serve as:

- a product requirements document;
- an API design baseline;
- an implementation-planning input;
- a review checklist;
- a conformance and acceptance-test source.
