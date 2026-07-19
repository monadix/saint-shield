# Module design: M0-V virtual foundation

## Responsibility

Provide the reproducible toolchain, public package/module skeleton, canonical
build entries, private DPDK compatibility spike, D-012 workflow, evidence
schemas, dependency integrity, and clean developer documentation.

It does not implement packet ownership, parsing, mutation, processors, update
publication, observability, policy, state, AF_XDP, or physical DPDK operation.

## Dependencies and boundary

`foundation` has no framework dependency. Public core modules never import an
adapter. The DPDK shim is private to `io/dpdk`; the pure public library therefore
cross-compiles without libc or DPDK.

## Lifecycle and ownership

The private context owns EAL, one mempool, RX/TX rings, one virtual port, and
its prepared token. A batch RX call transfers one ring token to Zig; an
accepted TX prefix transfers it back to the TX ring. Zig releases a rejected or
locally failed token. The single destruction path drains both rings, releases
any still-prepared token, closes/frees resources in reverse order, and verifies
allocation/completion and initial/final mempool counts. This is spike evidence
for the later adapter, not the M1 ownership implementation.

## Allocation, blocking, and failure

All DPDK work is setup/test code and may allocate. The virtual burst itself is
bounded to one token. Injection covers cleanup after pool/ring/port creation,
after RX enqueue, after TX rejection, and after TX acceptance before
completion. Fuzzing and documentation run off-path under explicit outer bounds.
Any ABI, token, schema, hash, version, sanitizer, or link failure makes its
canonical command non-zero.

## Performance and evolution

The imported mbuf view uses direct field operations with no accessor calls.
M4 may change internal adapter representation only with the required benchmark
and ABI review. Synthetic timings are never production claims.
