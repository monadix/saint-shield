# 0. Product Definition

## 0.1 Product identity

The product is a **Zig framework for building low-level Layer 4 network protection tools**.

It is a reusable library and set of public contracts, not a mandatory ready-made firewall, distributed controller, appliance image, or fleet-management product.

An application using the framework composes packet-processing extensions, configuration sources, update behavior, state facilities, and observability outputs into a concrete protection tool.

## 0.2 Primary users

The primary users are developers building tools such as:

- stateless and stateful L4 firewalls;
- DDoS mitigation components;
- packet filters and normalizers;
- SYN protection mechanisms;
- traffic classifiers and redirectors;
- rate limiters;
- custom L4 gateways or enforcement points;
- specialized packet inspection and mutation tools.

## 0.3 Product goals

The framework MUST:

1. make high-throughput packet processing a first-class use case;
2. allow applications to compose native Zig packet processors;
3. allow processor configuration to be loaded and replaced without coupling packet workers to configuration I/O;
4. support local metrics and event collection without blocking packet processing;
5. define stable packet, batch, lifecycle, update, and extension semantics;
6. permit optional standard extensions such as expression rules, table-based execution, BPF execution, or WebAssembly execution without making any of them fundamental framework concepts;
7. keep deployment topology under application control;
8. preserve deterministic and explainable behavior where the chosen processor supports it;
9. make resource usage and failure behavior explicit;
10. support incremental construction of increasingly capable protection products.

## 0.4 Product non-goals

The framework MUST NOT require or attempt to provide:

- a fleet-wide control plane;
- distributed policy coordination;
- leader election or consensus;
- operator authentication and authorization;
- persistent policy storage;
- global metrics storage or dashboards;
- service discovery;
- a mandatory policy language;
- a mandatory virtual machine or bytecode executor;
- a mandatory process split;
- a mandatory network protocol between configuration and packet processing;
- arbitrary remote calls in the per-packet path;
- transparent portability across every packet I/O environment at the cost of weakening packet-path guarantees.

## 0.5 Product principles

### P-01: Library before appliance

The framework exposes reusable components and contracts. A complete executable is an application built with the framework.

### P-02: Native extension model first

The fundamental extension mechanism is a native Zig processor contract. Other execution technologies are modules built on top of that contract.

### P-03: Logical separation, not forced deployment separation

Packet processing, update preparation, and observability have different execution constraints, but MAY coexist in one process and one machine.

### P-04: Packet path remains local

Packets MUST be processed from locally available policy and state. External communication MUST NOT be required to decide every packet.

### P-05: Stable semantics over maximum genericity

The framework MUST define stable packet ownership, batch behavior, update publication, and disposition semantics. It SHOULD avoid universal abstractions that erase behavior critical to performance or correctness.

### P-06: Optional features remain optional

The core framework MUST remain usable without an expression engine, BPF runtime, WebAssembly runtime, stateful flow tracker, remote configuration source, or a particular exporter.
