# Module: Optional Standard Policy Processor

## Responsibility

Parse and validate a human-authored declarative L4 language; resolve registered fields/functions/actions; compile immutable prepared policy; evaluate batches with absent-aware semantics; execute actions; and explain test packets. It is an optional normal processor.

## Concrete syntax strategy

Define a small purpose-built textual grammar in Phase 3. Do not use YAML as the semantic language: YAML adds scalar/type ambiguities and still requires a policy grammar in data form. Do not expose the internal AST as the compatibility contract.

The grammar includes imports only after artifact bundling/provenance semantics exist. Initial artifacts are self-contained UTF-8 with comments, named sets, named predicates, ACLs, rulesets, actions, and explicit defaults. Publish EBNF and a formatter. Unknown syntax is an error; no implicit truthiness or string-to-IP coercion.

## Compiler pipeline

```text
bytes -> tokens+spans -> syntax AST -> name graph -> typed AST
      -> normalized typed IR -> cost/resource plan -> executable blocks
```

Preparation caps bytes, tokens, nesting, declarations, expanded references, set entries, rule count, action count, and total instruction steps. Predicate cycles are rejected by graph analysis. All diagnostics retain stable codes and source spans.

## Types and availability

Built-ins cover bool, unsigned integers, IPv4/IPv6 address and prefix, port/range, protocol, length, TCP flags, duration, and bounded bytes. Fields evaluate to `Value(T) | Unavailable`, never a sentinel value.

Boolean evaluation implements a specified three-valued algebra. A top-level rule matches only `true`. In particular `not Unavailable` remains `Unavailable`, preventing a non-TCP packet from matching `tcp.dst_port != 80`. Truth tables are published and executable as conformance fixtures.

## IR and evaluator

The normalized IR is immutable, typed, and uses numeric handles. Initial executable blocks are bounded operations such as load-field, constant, compare, membership, three-valued not/and/or with semantic short-circuit, branch, rule-hit, and action. Preparation computes maximum steps per packet or rejects the artifact.

The production evaluator writes no trace. A separate reference evaluator walks typed IR and records fields, availability, predicate/ACL decisions, rule/default, actions, and disposition. Every optimized evaluator is continuously compared with it.

## Set representations

Preparation chooses by type/content:

- small sets: sorted flat array/binary or linear search based on measured crossover;
- exact integers/addresses: immutable fixed hash table;
- port ranges: merged sorted disjoint intervals or dense bitset when density justifies it;
- IP prefixes: compressed binary/radix trie with longest/membership semantics explicitly selected;
- ACL N-tuples eligible for optional DPDK ACL lowering later.

The representation is recorded in diagnostics and resource estimates, not exposed in policy semantics.

## Actions and extensions

The application supplies comptime registries of field providers, pure functions, and actions. Preparation resolves names/signatures to handles and stores typed arguments. Match operations cannot invoke action/state/metric/event effects. Actions declare terminal/non-terminal behavior, mutation/state capabilities, and bounded cost.

## Optimization sequence

1. Correct reference evaluator.
2. Compact typed blocks, constant folding, dead predicate elimination, set specialization.
3. Extract common fields once per packet/batch.
4. Batch classification/vectorization where profiles show benefit.
5. Optional DPDK ACL/table lowering for provably eligible subgraphs.
6. JIT only if all prior steps miss an accepted performance gate and W^X/security/deployment review approves it.

## Tests

- Parser golden/error/recovery and fuzz corpus.
- Every type rule and availability truth table.
- Named set/predicate and ACL ordering/default/cycle scenarios.
- Reference versus optimized evaluator over generated policies/packets.
- Canonical semantic hash stability.
- Resource-limit/cancellation/diagnostic truncation.
- Action capability and terminal-continuation validation.
- Explanation contains required facts without affecting production result.
- Shadow comparison of generations with bounded event output.

## Requirement ownership

All PL-EXP, PL-SET, PL-PRED, PL-ACT requirements; ruleset/ACL/type/availability/compiler prose; AC-PL-001..008.

