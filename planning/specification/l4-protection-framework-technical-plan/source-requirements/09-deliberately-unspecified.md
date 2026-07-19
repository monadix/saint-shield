# 9. Deliberately Unspecified Decisions

The following choices are intentionally not fixed by this specification because they are implementation details, deployment choices, or future product decisions.

## 9.1 Packet I/O technology

The specification does not mandate a particular packet I/O library, driver model, operating system, kernel-bypass mechanism, or virtualization environment.

An implementation may provide one or more backends, provided public packet and batch semantics remain valid.

## 9.2 Internal threading and scheduling

The specification does not mandate:

- one thread per queue;
- number of queues per worker;
- polling strategy;
- cooperative scheduling;
- interrupt use;
- processor fusion;
- stage-per-core execution.

Implementations must merely satisfy the public lifecycle and packet-path constraints they claim.

## 9.3 Memory representation

The specification does not mandate:

- packet-buffer type;
- allocator;
- memory pool;
- zero-copy strategy;
- metadata layout;
- batch-mask representation;
- generation reclamation algorithm.

## 9.4 Processor dispatch

The specification does not mandate compile-time composition, runtime vtables, generated pipelines, inlining, code generation, or dynamic loading.

Static Zig composition is expected to be a natural baseline, but it is not an externally observable requirement beyond the Zig library product requirement.

## 9.5 Policy syntax

The policy module requirements define semantics, not concrete grammar.

The implementation may choose a syntax inspired by existing filter languages or define a new syntax, provided it satisfies the required capabilities and avoids ambiguous behavior.

## 9.6 Policy compilation

The specification does not mandate interpretation, bytecode, native code generation, decision trees, tables, vectorization, or JIT compilation.

## 9.7 State data structures

The specification does not mandate particular hash tables, prefix structures, eviction algorithms, or timer mechanisms.

## 9.8 Separate processes

The specification neither requires nor forbids separating local management/update functionality from packet processing.

A separate process is an application deployment option, not a core framework requirement.

## 9.9 Remote controller protocol

The framework exposes local artifact and update APIs. Any network protocol used by an external controller is outside scope.

## 9.10 Metrics protocol

The framework exposes snapshots and event streams. It does not mandate Prometheus, OpenTelemetry, a telemetry socket, JSON, or another protocol.

## 9.11 Dynamic native plugins

A runtime-loaded ABI is optional and should only be standardized after concrete use cases justify its compatibility and lifecycle cost.

## 9.12 Universal flow model

The framework does not impose a single flow key or state machine on all processors.

Reusable stateful modules may expose default L4 flow models, but applications and processors must remain able to define other identities where required.
