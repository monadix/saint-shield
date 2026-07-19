# 4. Optional Standard Policy-Language Module

This section specifies an optional standard processor module. It is not part of the irreducible core framework.

## 4.1 Purpose

The module provides a declarative policy language for matching packets and local flow or metadata context, then applying actions.

The language SHOULD provide functionality comparable to rich Boolean packet filters and ordered address-control lists without copying the ambiguities of any particular existing syntax.

## 4.2 Expression model

**PL-EXP-001** A match expression MUST support Boolean composition using conjunction, disjunction, negation, and grouping.

**PL-EXP-002** A match expression MUST support typed comparisons.

**PL-EXP-003** A match expression MUST support membership in typed sets.

**PL-EXP-004** A match expression SHOULD support ranges where meaningful.

**PL-EXP-005** A match expression MUST support named predicates.

**PL-EXP-006** A match expression MAY call registered pure functions.

**PL-EXP-007** Match expressions MUST be side-effect free.

**PL-EXP-008** The module MUST define short-circuit behavior or explicitly permit equivalent optimized evaluation.

**PL-EXP-009** Optimization MUST NOT change observable match semantics.

Example capability:

```text
ip.source in trusted_networks
and (
    tcp.destination_port in web_ports
    or udp.destination_port == 443
)
and not ip.source in blocked_networks
```

## 4.3 Type system

The module SHOULD support at least:

- Boolean values;
- unsigned integers;
- IP addresses;
- IP prefixes;
- ports and port ranges;
- protocol identifiers;
- packet lengths;
- TCP flag sets;
- durations;
- bounded byte strings;
- named typed sets;
- registered application-defined types where supported.

Type errors MUST be reported during preparation, not packet execution.

## 4.4 Field availability

Protocol-specific and optional fields may be unavailable for a packet.

The module MUST define absent-aware semantics such that a comparison against an unavailable field does not accidentally match merely because the comparison is negated.

A conforming default is three-valued internal evaluation:

- true;
- false;
- unavailable.

A rule matches only when its top-level expression evaluates to true.

The exact internal representation is unspecified, but externally observable behavior MUST be equivalent.

## 4.5 Named sets

**PL-SET-001** The language MUST support named typed sets.

**PL-SET-002** Sets MAY be embedded in a policy artifact or resolved from separately supplied artifacts.

**PL-SET-003** Set update and policy update consistency MUST be explicit.

**PL-SET-004** The language MUST specify membership semantics independently of the internal data structure.

**PL-SET-005** Implementations MAY compile sets into any suitable representation.

## 4.6 Named predicates

**PL-PRED-001** The language MUST support reusable named predicates.

**PL-PRED-002** Predicates MUST be pure expressions.

**PL-PRED-003** Recursive predicate definitions MUST be rejected unless the language explicitly defines bounded recursion.

**PL-PRED-004** Predicate expansion or compilation MUST preserve type and field-availability semantics.

## 4.7 Ordered ACLs

The module SHOULD provide an ordered ACL construct with:

- named ACLs;
- ordered entries;
- explicit allow and deny entries;
- nested inclusion of named ACLs;
- first-match behavior;
- explicit default behavior.

ACL behavior MUST be distinct from general Boolean expression behavior.

An ACL MUST NOT rely on implicit defaults that change by call site.

Example capability:

```text
acl trusted_sources {
    deny 192.0.2.13
    allow 192.0.2.0/24
    include office_networks
    default deny
}
```

## 4.8 Rulesets

A ruleset MUST associate match expressions with actions.

A rule SHOULD have:

- stable identity;
- optional human-readable name;
- match expression;
- ordered actions;
- continuation behavior;
- optional bounded observability identifiers.

A ruleset MUST define a default outcome when no rule terminates processing.

Example capability:

```text
ruleset ingress {
    rule drop_blocked {
        when ip.source in blocked
        then drop(reason = blocked_source)
    }

    rule normalize_web {
        when tcp.destination_port in web_ports
        then set(ip.dscp, 10)
        continue
    }

    default accept
}
```

The concrete syntax is deliberately unspecified.

## 4.9 Actions

**PL-ACT-001** The module MUST support action registration by native processors or application modules.

**PL-ACT-002** Action argument types MUST be validated during preparation.

**PL-ACT-003** Actions MUST declare whether they are terminal, non-terminal, or selectable by policy syntax.

**PL-ACT-004** Terminal behavior SHOULD be explicit in the policy.

**PL-ACT-005** Effects such as packet mutation, metrics, events, state changes, rate limiting, or redirection MUST occur through actions, not match expressions.

**PL-ACT-006** An unknown action MUST cause preparation failure.

## 4.10 Field providers and pure functions

The module MUST permit native registration of additional fields and pure functions.

A field provider MUST declare:

- stable field name;
- value type;
- availability conditions;
- extraction requirements;
- whether extraction is packet-local or depends on configured state.

A pure function MUST declare:

- stable function name;
- argument types;
- result type;
- availability behavior;
- resource cost category where relevant.

## 4.11 Compilation and explanation

The module MAY compile expressions into tables, decision trees, native code, bytecode, vectorized evaluation, or other forms.

The module SHOULD provide:

- validation diagnostics tied to source locations;
- rule and predicate reference resolution;
- resource estimates;
- an explanation facility for a supplied packet and generation;
- deterministic policy hashing;
- optional shadow comparison of two prepared policies.

Internal compilation technology is not part of the public specification.
