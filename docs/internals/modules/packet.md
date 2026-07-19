# Module: packet

## Responsibility

`packet` defines backend-neutral input/output identities, input origin,
adapter-token ownership states, receive-order slots, validated packet segments,
read-only `PacketView`, ordered `PacketBatch`, and lifetime cookies. It does not
receive or transmit packets, allocate payload storage, parse protocol headers,
mutate packets, or choose final dispositions.

## Requirements and invariants

M1 maps FR-PKT-002/003/006/011/012 and the batch formation/time/resource prose
needed by later pipeline work. Exact tracker transitions and shutdown
reconciliation enforce INV-PKT-001. Address-stable batches invalidate a cookie
at processing-call end to enforce INV-PKT-002 in safe code and tests.

## Public contract

`PacketSlot.init` validates at most 16 untrusted segment descriptors with
checked total-length arithmetic. `PacketView.contiguous` is the zero-copy fast
path; `read` explicitly copies a requested range; `segments` iterates at most
16 borrowed pieces. All byte ranges are bounds/overflow checked. A batch holds
at most 64 slots, preserves strictly increasing receive order, permits empty or
partial lengths, and must remain address-stable while views exist.

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
storage. `PacketBatch.invalidate` ends the processing borrow; stale views return
`StaleView`. The tracker and payload must outlive slots, and the batch object
must outlive any attempted stale-view check. Escaping those backing pointers by
unsafe casts is outside the safe contract.

## Concurrency

Tracker, slot, and batch mutation is single-worker-owned. There are no atomics,
locks, waits, or cross-worker aliases in M1.

## Allocation and work bounds

Only `TokenTracker.init` allocates one fixed state array. Slot construction,
views, range access, iteration, transitions, and batch construction allocate
nothing. View work is O(segments), bounded by 16; shutdown verification is
O(registered tokens).

## Failure behavior

Malformed totals, oversized segment sets, descriptor/range arithmetic
overflow, range bounds, stale borrows, invalid transitions, double completion,
and missing completion are distinct bounded errors. Rejected transitions leave
ownership unchanged.

## Security boundary

Segment lengths and declared totals are untrusted adapter inputs. Construction
checks the sum before slicing and rejects declarations larger than backing
storage. Every public byte range checks both addition and final bounds.

## Performance budget

Ordinary receive-to-output traversal borrows the adapter payload and records
zero packet-path payload copies. Explicit `read` is a caller-requested copy and
is not used by the forwarding traversal. M1 results are synthetic regression
evidence, not production capacity claims.

## Tests and evidence

Tests exhaust the six-state/action transition matrix, double/missing
completion, allocation failure, malformed and overflowing descriptors, every
range across every split of an eight-byte packet, zero-copy segment iteration,
receive-order rejection, and stale-cookie behavior. Synthetic integration tests
cover every size through its configured maximum.

## Alternatives and evolution

M2 adds selection, parsing, dispositions, mutation, and retention-lease pool
semantics without exposing the internal segment array. A fixed word array may
replace later selection storage before public stabilization.

## Open questions

None for the M1 read-only surface.
