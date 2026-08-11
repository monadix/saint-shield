# Module: packet

## Responsibility

`packet` defines backend-neutral input/output identities, input origin,
adapter-token ownership states, receive-order slots, validated packet segments,
read-only `PacketView`, ordered `PacketBatch`, and address-stable processing
owners. M2 adds preallocated parse/mutation caches, explicit mutable
descriptors, selections, dispositions, editors/finalization, and bounded
retention. It does not receive or transmit packets or allocate payload storage.

## Requirements and invariants

M1 maps FR-PKT-002/003/006/011/012 and the batch formation/time/resource prose
needed by later pipeline work. Exact tracker transitions and shutdown
reconciliation enforce INV-PKT-001. One allocator-owned, address-stable
`PacketBatchOwner` controls monotonic generations across call frames to enforce
INV-PKT-002 in safe code and tests. A setup-only atomic allocator assigns every
owner a process-unique, monotonic non-pointer identity without reuse.
M2 maps the remaining FR-PKT-001..013 behavior plus FR-TEST-003 and enforces
INV-PKT-003..005. Detailed parser, mutation, finalization, disposition, and
retention rules are in [M2 packet-processing internals](m2-packet-processing.md).

## Public contract

`PacketSlot.init` validates at most 16 untrusted segment descriptors with
checked total-length arithmetic. `PacketView.contiguous` is the zero-copy fast
path; `read` explicitly copies a requested range; `segments` iterates at most
16 borrowed pieces. Non-empty zero-copy slices are scoped to `processBatch`;
issuing one prevents subsequent retention of that slot. All byte ranges are
bounds/overflow checked. A batch holds at most 64 slots, preserves strictly
increasing receive order, and permits empty or partial lengths. Public batch,
view, and adapter-output handles are fieldless numeric enums containing only
owner-identity/generation/index tags; no public scalar contains an owner pointer
or address. Every operation receives the valid opaque owner separately and
validates identity first, then generation/index and access state, before
indexing private storage. `PacketBatch.outputPacket` returns an opaque
`OutputPacket`, never a pointer to owner-held slot storage. Copying a handle
preserves the same tags and checks.

Token transitions are:

| From | Operation | To |
| --- | --- | --- |
| input-owned | receive | worker-owned |
| worker-owned | submit output | output-owned |
| worker-owned | return to input/pool | returned-to-input |
| worker-owned | retain | retained |
| output-owned | complete output | completed |
| retained | complete lease | completed |

Terminal states reject a second completion. Shutdown verification reports any
worker/output/retention obligation that remains live.

## Dependencies

`packet` depends only on `foundation` and the Zig standard library. It never
imports an adapter. Adapters construct slots and invoke token transitions.

## Object lifecycle and ownership

The adapter owns payload memory and `TokenTracker`. A slot and view borrow that
storage. Adapter/worker setup allocates an address-stable `PacketBatchOwner`;
construction also assigns a process-unique identity through a thread-safe
setup-only monotonic counter. The maximum identity is allocated once; later
construction returns `OwnerIdentityExhausted` without wrap or reuse. `begin`
copies bounded slot metadata but never payload and advances an owner-local
generation that is never reset or reused. `PacketBatch.invalidate` ends the
shared borrow for every batch copy. Stale batch operations return
`BatchReleased`; every view/iterator/output-handle operation returns
`StaleView`, including after a handle escapes a processing-call frame. Raw
slices and adapter tokens are not revocable values and must not escape
`processBatch`; the owner records when they are issued and rejects a later
retention transfer with `OutstandingBorrow`. `PacketView.read` copies and does
not create this barrier. The owner, tracker, and payload must outlive all
derived handles; owner destruction is allowed only after they are unreachable.
Zero, random, modified, and cross-owner public scalar tags are safe inputs when
paired with a valid owner and return bounded release/stale/bounds errors.
Forging the opaque owner pointer or backing payload pointers remains outside
the safe contract.

## Concurrency

Packet-path tracker, slot, batch, view, and iterator operations are
single-worker-owned and use no atomics, locks, or waits. Owner construction has
the only atomic activity: one setup-only monotonic identity allocation, with
CAS retry if constructors race. M1 creates no cross-worker packet aliases.

## Allocation and work bounds

`TokenTracker.init` allocates one fixed state array and
`PacketBatchOwner.init` allocates one fixed owner object. Slot construction,
`PacketBatchOwner.begin`, views, range access, iteration, and transitions
allocate nothing. View work is O(segments), bounded by 16; shutdown
verification is O(registered tokens). `PacketPathInstrumentation` records
adapter receive, output submit, borrowed segments, explicit `read` bytes, and
the centralized abstraction-copy path without allocating itself. Synthetic
queue allocation evidence comes from a wrapper around the real queue
allocators, not a manually incremented packet counter.

## Failure behavior

Malformed totals, oversized segment sets, descriptor/range arithmetic
overflow, range bounds, stale borrows, invalid transitions, double completion,
missing completion, and retention attempted after issuing nonrevocable raw
authority are distinct bounded errors. Forged handle tags and adversarial
iterator numeric state are revalidated on every operation. Iterator progress
is recomputed from descriptors with checked arithmetic. Rejected transitions
leave ownership and access state unchanged.

## Security boundary

Segment lengths and declared totals are untrusted adapter inputs. Construction
checks the sum before slicing and rejects declarations larger than backing
storage. Every public byte range checks both addition and final bounds.

## Performance budget

Ordinary receive-to-output traversal borrows the adapter payload. The regression
captures every queue-owned segment address and length before receive, compares
it through output submission, and checks zero abstraction-copy bytes plus zero
real allocator activity. Explicit `read` increments its counter at the actual
copy site and is not used by forwarding traversal. Intentional allocation and
centralized-copy controls must trip the corresponding guards. M1 results are
synthetic regression evidence, not production capacity claims.

## Tests and evidence

An independent state model drives every length-five sequence from the six token
actions through the real tracker and compares state, errors, receive/completion
counts, and shutdown reconciliation after each step. Other tests cover
double/missing completion, invalid tokens, allocation failure, malformed and
overflowing descriptors, all ranges over 1 through 16 segments including empty
boundaries, batch sizes 0 through 64 plus 65 rejection, receive-order rejection,
and stale behavior for all batch/view/iterator operations, caller-frame escape,
copied aliases, later-generation reuse resistance, generation exhaustion, and
a direct public-field audit. The same tests use zero, random, and modified
batch/view tags plus maximum and inverted iterator range/progress state, proving
bounded errors in all build modes. Two simultaneously live owners with
different origins and packet lengths reject cross-owner batch access,
invalidation, every view accessor, and iterator advancement without changing
either owner. A private local-counter test proves identity exhaustion does not
wrap or reuse. Synthetic integration covers linear and segmented payloads for
every size through the configured maximum.

## Alternatives and evolution

M2 uses the accepted opaque one-word selection baseline. A fixed word array may
replace it before public stabilization if a larger batch bound is accepted.

## Open questions

None for the M1 read-only or M2 packet-processing surface.
