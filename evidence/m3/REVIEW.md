# M3 review closure register

Date opened: 2026-08-13

Milestone status: Complete

Scope: hardware-free M3 native processor contract, static pipeline, public
synthetic harness, and deterministic example

The review scope is the complete committed tree from baseline
`8da41e27b385fd07f703a9f03c2de2ae38b0e696` through the declared M3 tip.
Independent public-API and resource/performance review reported the findings
below. The writer may mark them addressed after implementation and focused
checks; only the discovering reviewer or its named successor may close them.

## Mandatory authority-return inventory (writer checkpoint)

This inventory supersedes the first remediation inventory. A later change to
any listed authority surface invalidates its acknowledgment. M3 rejects
retention declarations unconditionally and mints no retention lease, token, or
other transferable packet authority.

Acknowledgment status: acknowledged by `m3_api_review` after auditing this
complete renewed inventory at exact clean source commit
`1dd66147c8102de034bb4f9ee9930c05db973aec`, tree
`11d25fb9d49beee8fc2c0df73503c59536087f8c`. The result was supplied by the
main session together with M3-FINAL-001 closure and no additional material
finding. Current-source artifact refresh is unlocked; this acknowledgment does
not transfer milestone acceptance to the writer.

| Surface issued to callback/caller | Issuer and exact binding | Raw storage survival and revocability | Return/transfer/completion/invalidation/reuse behavior | Enforcement, failure atomicity, and evidence |
| --- | --- | --- | --- | --- |
| `ProcessContext(P.descriptor)` enum cookie | The package-internal `src/internal/processor_invocation.zig` bridge atomically mints one process-wide monotonic nonzero identity, then installs one thread-local active record bound to that identity and the address identity of a private mutable static marker generated for the exact context type. Pipeline assembly also installs a fixed pointer-free per-stage capability record: packet access and dispositions are intersected with the exact descriptor, trusted raw edit and time require both descriptor declaration and application authority, output IDs are the exact descriptor set already admitted by the application, and metadata rights are exact private key-type identities. The marker, bridge, counter, mint, reset, and capability installation are absent from `src/root.zig` and `saint.processor`; external-import compile failures enforce the public absences. | The numeric cookie can be copied, retyped, or transferred across threads, but carries no marker, owner, packet pointer, slice, writer, callback, allocator, index, lease, or token. Only the exact active thread-local record holds raw storage. A caller can name public context types but cannot read, mint, install, or independently select the private marker. The process-wide counter is never reset or decremented; checked exhaustion remains permanently at `maxInt(u64)` and rejects before installing state rather than wrapping or reusing any identity. | Valid only during the exact direct callback on the thread holding the matching active record and exact generated context-type marker. A fabricated descriptor that collided under the removed public `u64` binding produces a different marker and fails before receiving state. Unminted/new identities, stale post-return cookies, cross-thread transferred cookies, and every previously issued identity after completion also fail before access. External callers cannot install an invocation or effective capabilities. There is no retain/transfer/completion path; process-lifetime identity exhaustion fails closed as `InvocationExhausted`, surfaced by the pipeline as `InvocationFailure`, before a callback begins. | Every context operation authenticates the globally unique identity and exact private context marker before returning thread-local state, then checks its installed stage rights for packet access, disposition, raw edit, time, exact output ID, or exact metadata key type as applicable. Capability-intersection, provenance, collision, cross-thread, stale, and exhaustion failures return without packet or metadata effects. Exact deterministic `0x629b8ddd51712b5d` descriptor-binding collisions reject read/edit/raw/disposition/output and metadata substitution; two stages under broad application authority prove narrow/broad rights stay isolated. The synchronized two-thread same-descriptor regression, new/stale tests, permanent exhaustion checks, and external public-bridge/capability/identity compile failures preserve the remaining reachability and reuse boundaries. |
| Processor `*Worker` process callback pointer | Pipeline resolves a live `WorkerHandle` by prepared-owner pointer, slot index, generation, and stored worker pointer before calling the statically installed processor with exactly its tuple element. | A processor can copy its own worker pointer, but it gains no framework owner or packet authority. The pointee remains owner-live until checked worker teardown; packet access still requires a current authenticated context. | Valid while that worker slot/generation is live. Worker deinit invalidates the registry slot before destroying worker state; stale and recycled handles fail without dereferencing released worker storage. | Owner live count/capacity blocks over-instantiation and prepared deinit. Partial construction rolls back in reverse. `prepared owner enforces capacity early-deinit stale recycle and repeated cleanup` covers exact capacity, early deinit, copied stale handle, reuse, and repeated deinit. |
| Processor `*const Prepared` instantiate pointer | The prepared owner passes the exact corresponding prepared tuple element to the exact processor worker constructor. The worker may retain it as declared processor state. | Raw prepared storage intentionally survives worker construction. It is not revocable while workers are live, so prepared destruction is rejected rather than invalidating a retained pointer. | Valid through that worker's lifetime. All workers must complete owner-mediated cleanup before prepared cleanup; no live worker can survive successful prepared deinit. | Live-count/capacity enforcement and reverse cleanup preserve pointer validity. The lifecycle test includes multiple workers and stale/recycled worker generations; the static-filter worker retains prepared-derived state. |
| Prepared owner pointer returned by `prepare` | Root allocator creates one generated `PreparedPipeline` containing exact tuples, per-stage budgets, estimates, pointer-free installed capabilities, and a checked worker registry sized to admitted `worker_count`. | Storage survives until successful checked deinit. Early deinit is revocable only after `live_workers == 0`; a successful deinit invalidates the application pointer and frees registry/wrapper storage. | No ownership transfer. Failed early deinit is atomic and leaves all state live. Successful deinit performs exact reverse processor cleanup, frees the registry, then destroys the wrapper. Use after successful invalidation is outside the API contract. | `prepared owner enforces capacity early-deinit stale recycle and repeated cleanup`, exact-limit tests, and exhaustive allocation sweeps cover failure/cleanup boundaries. |
| `WorkerHandle` value returned by `instantiate` | Prepared owner mints pointer-free `{ owner_identity, slot, generation }` only after all stage workers construct and seal successfully. Every operation separately requires a live `*PreparedPipeline`, compares owner identity first, then validates index/generation and resolves the private registry pointer. | Handle bytes may survive or be copied after worker or prepared destruction, but contain no pointer, slice, callback, allocator, token, descriptor, or raw storage. Worker storage does not survive teardown: deinit clears the registry pointer before reverse cleanup and destruction. | Wrong live owner, forged identity/index/generation, original/copied stale handle, and stale handle after slot recycle all reject without a worker dereference. Capacity rejection and partial construction mint no handle. After successful prepared deinit, the scalar handle alone has no operation; supplying a freed owner pointer remains ordinary caller memory unsafety outside the contract. | `resolveWorker` authenticates the explicitly live owner identity before slot access, then generation, registry pointer, and worker back-binding. The lifecycle test covers wrong owner, forged components, capacity, early owner deinit, copied stale, repeated teardown, slot reuse, and post-owner scalar-only survival. |
| Prepared/worker construction `std.mem.Allocator` values | Each exact stage receives an address-stable `BudgetAllocator` limited to only that stage's admitted estimate; no aggregate allocator is shared. | The allocator value/vtable pointer can be retained by processor storage, but its phase changes monotonically from construction to sealed. Raw allocations remain owner-live; retained allocation/reallocation/free authority does not. | After constructor return, alloc/resize/remap and free attempts are denied. The owner opens cleanup phase only around the matching destructor, allowing exact frees but never new allocation, then reseals. There is no transfer to a runtime pool. | Denial happens before the child allocator. Per-stage limits prevent slack laundering; constructor failure cleanup is reverse and exact. Budget unit tests and `retained construction allocators are sealed on the packet path and cleanup remains exact` cover retained prepared/worker allocator copies and cleanup. |
| `ConfigurationArtifact.payload` input slice | Application supplies a versioned artifact; pipeline validates required presence/content type and passes the borrowed slice only to estimate/prepare. | Caller storage may outlive or end after preparation. The pipeline does not store the slice. A processor that needs bytes after return must copy them into its own stage-counted prepared allocation. | No return/transfer. Static-filter evidence copies the byte and frees the copy through owner cleanup. Invalid artifacts fail before or within preparation with no generated handle. | Artifact checks precede preparation; copied bytes are charged to the exact stage budget. Existing artifact and allocation-underestimate tests cover this path. |
| `ApplicationCapabilities.available_outputs` input slice and prepared output-ID copy | The application lends output IDs to public `prepare`; assembly validates the bounded unique nonzero list and every generated processor output before construction, then copies only IDs into fixed prepared-owner storage. | The caller slice and its raw storage are never retained. Only authority-free `OutputId` values survive in the prepared owner until its checked teardown. | No slice return or transfer. Missing, duplicate, zero, excessive, or processor-unavailable outputs reject before any constructor. Prepared cleanup destroys the copied values with the owner; a later caller slice mutation cannot change the installed set. | Public `processBatch` validates each configured output against the copied application set and each generated output against the config before callbacks. Invalid-config tests cover unknown/missing/default paths with zero callback calls and unchanged bytes. |
| Typed metadata input/output values | Application `InputMetadata.put` and generated context methods copy values into fixed `MetadataStore` slots bound by stable key ID/type fingerprint and per-packet validity. Reads require the exact descriptor input key; writes require the exact output key. | Only inline bytes survive. Recursive grammar rejects pointers, slices, functions, frames, allocator-bearing nested structs/unions, and other non-runtime authority. No storage pointer or slice is returned. | Values are copied by value per batch and invalidated when worker metadata is reset/overwritten. Partial validity returns `null`; no retain/transfer/completion path exists. | Compile-fail cases cover pointer, slice, function, nested pointer, allocator, and undeclared reads. `typed produced metadata records partial validity and fixed scratch accounting` covers present/absent packets and full fixed-store accounting. |
| Metric/event declarations | Descriptor supplies comptime tuples with stable `MetricId`/`EventId`, inline value/payload type, and nonzero finite series/record bound. Application supplies availability IDs only during preparation. | Type/schema data is comptime; no runtime handle, pointer, callback, sink, or allocator is installed or returned. Application ID slices are validated during prepare and are not retained; installed capabilities are pointer-free. | Duplicate/conflicting/unbounded or unavailable schemas reject before preparation. There is no M3 publish, transfer, completion, or reuse API. | Compile-fail duplicate/unbounded cases and `metric and event schemas require exact application availability before prepare` cover schema and availability enforcement. |
| Public `processBatch` error return over caller-supplied `PacketBatchOwner`/`PacketBatch` and pre-minted batch/view/editor/iterator/output/raw aliases | The caller supplies the exact live owner and generation-bound batch after prepared-owner/worker authentication. The pipeline lends callback authority only through the authenticated call-scoped context; no batch owner, handle, pointer, slice, token, iterator, descriptor, or callback is returned. | Revocable scalar aliases may survive as bytes but every operation revalidates owner identity/generation/index. A raw slice or adapter token previously extracted from a view/output is non-revocable; `requireRevocable` detects that state and rejects before callbacks. Processor contexts cannot mint either escaping raw surface. | Invalid config, metadata, worker, or non-revocable-borrow failures happen before callbacks and leave the batch live and packet bytes unchanged. After the first callback starts, every returned pipeline error invalidates the exact generation before return; pre-minted and newly requested scalar aliases then fail stale/released. The adapter token deliberately remains worker-owned for exactly one caller/harness reconciliation. Normal success returns copied result values and leaves the batch live for output/completion. A subsequent owner generation accepts only newly minted aliases; old aliases remain stale. | Structural config validation covers too many/duplicate/unknown outputs and missing/invalid default/Continue routing; prepared validation binds config to copied application outputs and all generated outputs. A single post-callback `errdefer` covers work overflow/breach, invocation end, error-policy disposition, group resolution, and final-disposition reads. `invalid disposition configurations reject before mutating processor callbacks`, `escaped raw batch authority rejects before processor callbacks`, and `post-callback work breach revokes batch aliases and caller completes token once` cover zero-call failure atomicity, raw survival rejection, mutation plus terminal disposition plus excess work, batch/view/editor/output invalidation, exact token completion, and recycled generation behavior. |
| `ProcessResult`, stage trace, aggregate estimates, and harness result copies | Processor returns only scalar visited/work counts. Pipeline/harness return copied dispositions/status/errors, checked numeric resource aggregates, and copied packet bytes. | No returned owner/token/writer/callback/allocator; result-owned byte copies have ordinary explicit `deinit`. | Excess work returns `WorkContractViolation` with no `ExecutionResult` after generation invalidation; the harness reconciles synthetic ownership exactly once. Normal result copies are caller-owned and do not extend packet authority. | Worst-case formula, estimate coverage, aggregate limit, visited/work runtime checks, terminal short-circuit, post-callback revocation, and public-harness failure sweeps cover accepted and rejected result paths. |

Pre-minted/new/stale/recycled summary: validation occurs before every dereference
or packet operation; external code cannot invoke the bridge or install
capabilities, process-wide identities never repeat or reset, exhaustion cannot
wrap, and unminted/new, stale, or cross-thread transferred context cookies fail.
Retyped cookies fail the exact private context marker, including the removed
binding's deterministic collisions; even a hypothetical identity misuse still
meets the installed exact per-stage right checks. Capacity and partial worker
failures mint nothing.
Every worker operation requires a distinct live owner; wrong-owner and forged
identity/index/generation values reject, copied completed handles fail, stale
handles contain no raw pointer after owner destruction, and recycled slots
require a new generation. Public pre-callback validation preserves a live batch
without effects; any post-callback error invalidates its generation, after which
new aliases reject until the owner begins a new generation and all old aliases
remain stale. Escaped non-revocable raw storage/token authority rejects before
callbacks. All constructor and capability/admission failures occur before
returning new authority. Successful context/worker completion revokes or
invalidates the corresponding record before storage cleanup. Retention remains
rejected with no new token authority.

## Writer addressing matrix

| Finding | Implemented remediation and focused evidence |
| --- | --- |
| M3-API-001 | Invocation minting and effective capabilities moved to a package-internal bridge absent from public `src/root.zig` and `saint.processor`. External-import compile failures reject direct invocation and capability installation; legitimate static-pipeline execution and runtime broader-retype/new/stale rejection pass. |
| M3-API-002 | Metadata reads require declared inputs and recursive inline-value validation rejects pointer, slice, function, frame, nested pointer, and allocator authority. Five type cases plus undeclared-read compile failures pass; partial-validity runtime coverage passes. |
| M3-API-003 | Assembly rejects every descriptor retention declaration regardless of application retention configuration; M3 adds no lease/token operation. Both application settings reject before preparation. |
| M3-API-004 | `WorkerHandle` is pointer-free owner identity/index/generation. Every process/resource/deinit operation supplies a live prepared owner and validates identity before slot/generation/pointer resolution. Wrong owner, forged fields, live-owner deinit rejection, copied stale, recycled, repeated, and post-owner scalar-only cases pass. |
| M3-API-005 | Aggregate estimates separately report processor/framework prepared and worker bytes; exact wrapper, tuple, budget, worker registry, and full fixed metadata storage are admitted under checked hard ceilings. Zero/exact/one-under/multiworker/overflow cases pass. |
| M3-API-006 | Descriptors use concrete comptime metric/event tuples with stable IDs, authority-free types, and explicit nonzero bounds. Duplicate/conflict/unbounded declarations fail; application availability is checked before prepare without runtime handles. |
| M3-RES-001 | Each construction allocator has construction/sealed/cleanup phases. Retained prepared/worker allocator copies cannot allocate, resize, remap, or free after return; owner cleanup reopens free-only authority. Unit and packet-path tests pass. |
| M3-RES-002 | `frameworkPreparedBytes`, `frameworkWorkerBytesEach`, aggregate category fields, checked registry multiplication, and exact `MetadataStore` accounting cover all framework storage. Exact and one-byte-under checks pass. |
| M3-RES-003 | `worker_count` sizes the owner registry and bounds simultaneous live handles. Pointer-free handles require the correct live owner; partial failure mints nothing, capacity+1, wrong/forged/stale/recycled access, early prepared teardown, and repeated cycles reject or clean exactly. |
| M3-RES-004 | Comptime validates checked `fixed + per_active * max_batch <= maximum_total`; estimates cover that worst case; aggregate work is admitted; runtime visited/work is bound to the active formula, descriptor maximum, and accepted estimate. Under/exact/partial/excess cases pass. |
| M3-RES-005 | Prepared and worker construction use one address-stable allocator per exact stage estimate; no stage can spend another stage's slack. The deliberate underestimator plus slack stage rejects. |
| M3-RES-006 | Allocation-index sweeps use two allocating stages and cover prepared wrapper/registry, every stage constructor and rollback, worker wrapper/stages, public synthetic setup/submission/output/result copies, ownership reconciliation, and teardown until the first non-induced run. Every prefix returns allocated bytes to freed bytes, cleanup prefixes are reverse, and complete lifecycle teardown repeats. |
| M3-PERF-001 | `tools/m3/benchmark-evidence.py` schema-checks and authenticates commit/tree/ancestry, complete source objects including the internal bridge, environment, raw text/hash, generation digest, each complete run/batch/sample order permutation, raw elapsed/cycle arithmetic, every median/stdev, ratio, and threshold flag. Ten forged negatives include duplicate order and inconsistent elapsed/cycles. |
| M3-PERF-002 | The reviewed clean-tree controller captured, generated, schema-validated, recomputed, and thresholded the retained current-source artifact in one gate. Cumulative CI consumed the same controller and then validated retained evidence. |
| M3-PERF-003 | Seven nonselective independent warmed launches retained five samples each for 35 samples per variant and both batches, with every per-run sample and aggregate preserved. |
| M3-PERF-004 | The canonical schema gate validated the current retained M3 artifact and rejected its deterministic malformed case; ten validator negatives also passed. |
| M3-PERF-005 | Monolith/vtable paths are explicitly classified `non-comparable-diagnostic-only`; structured evidence requires `used_for_acceptance=false` and `used_for_reversal_or_decision=false`. Documentation removes all decision inference while retaining raw diagnostics. |
| M3-PERF-006 | Four-stage terminal runtime evidence leaves the first empty stage `skipped_empty` and every later stage `not_run`. A terminal-heavy benchmark pipeline asserts three successor counters remain zero before and after measurement. |
| M3-FRESH-001 | Complete routing validation and raw-authority rejection occur before callbacks; one post-callback error defer invalidates the exact generation, and direct plus public-harness tests prove stale/recycled alias rejection and exact token reconciliation in all modes. |
| M3-FRESH-002 | Benchmark construction registers every ownership unwind immediately, reconciles transferred tokens on error, tears workers/prepared owners down in exact reverse order, and passes an every-index failing-allocation sweep in all modes. |
| M3-FINAL-001 | The public rolling descriptor binding is removed. Invocation authentication uses a package-private exact generated context-type marker, while fixed per-stage installed rights intersect the exact descriptor with application authority and every applicable method rechecks packet, disposition, raw/time, output, and metadata rights. Exact packet/output and solved metadata collision regressions, two-stage broad-application isolation, same/new/stale/cross-thread/exhaustion tests, and the expanded public-identity compile failure pass. |

Applicable second-remediation source checks and exact results are recorded in
`evidence/m3/VERIFICATION.md`. Closed findings retain their discoverer closure;
historical reviewer acknowledgments remain bound to their exact source
checkpoints below.
`m3_resource_review`, acting in the discovering performance perspective,
closed M3-PERF-002/003/004 at clean non-WIP tip `933128bccc1401fd994f81c2c50e1d4f74c9dab9`,
tree `90aeb35acb61605bd71bc31fd155b8dfb18b49ad`, with retained artifact SHA-256
`630b7434ed89b6cce70425214f0f8774caa97bacf0f65029b46ac103d63a9941`.
That retained artifact became stale after the fresh remediation, without
rewriting the historical performance closure. `m3_api_review` subsequently
closed M3-FRESH-001/002 and acknowledged the renewed inventory at exact clean
source `1839df61e63530ce30a1554a8a1c895f25932ce5`/tree
`8c367eacabe8e1b7f218a2fa1cad19613cce004a`; current-source artifact and writer
gate evidence are recorded in `evidence/m3/VERIFICATION.md`.

## M3-API-001: Forgeable process context can cross descriptor capabilities

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-004/009, FR-EXT-001/003, INV-PKT-001,
  and the rule that a processor receives only its declared effective
  capabilities.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: `ProcessContext(descriptor)` is represented only by a
  public enum cookie while public invocation machinery installs a record that
  is not bound to the descriptor or negotiated application capabilities.
- Expected behavior: every context operation authenticates the installed
  descriptor and effective application capabilities; invocation machinery is
  internal and a cookie cannot be retyped to gain read, disposition, raw-edit,
  metadata, or output authority.
- Observed behavior: a valid numeric cookie can be reinterpreted as another
  generated context type and its broader methods can reach the same invocation.
- Reproduction and seed/trace: construct two descriptor context types, begin an
  invocation for the narrow type, retype the cookie, and request broader access;
  deterministic, no random seed.
- Failing layer: processor/pipeline authority binding and public API boundary.
- Bounded remediation/rechecks: bind invocation to descriptor identity and
  effective capabilities, validate every operation, internalize machinery, and
  add adversarial retype/access/disposition/raw/stale/new tests in all modes.
- Addressing evidence: the internal bridge is absent from public exports; 27
  external compile failures include direct invocation/capability installation,
  and the legitimate static-pipeline path plus context retype/new/stale runtime
  cases pass.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-API-002: Metadata reads and value types bypass declaration/lifetime bounds

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-COMP-002, FR-PROC-002/004/008, INV-RES-001,
  and fixed typed call-scoped metadata.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: context metadata reads do not prove the key is in the
  descriptor input set, and metadata values accept pointer/slice/function or
  allocator-bearing types whose copied bytes can retain dangling authority.
- Expected behavior: reads require declared inputs and all metadata values pass
  a recursive pointer/slice/function/allocator-free inline-value grammar.
- Observed behavior: undeclared reads and shallow byte copies of authority- or
  lifetime-bearing values are representable.
- Reproduction and seed/trace: compile a processor reading an undeclared key
  and declarations using pointer, slice, function, nested pointer, and allocator
  values; deterministic compile-fail cases plus partial-validity runtime check.
- Failing layer: metadata schema validation and generated context authority.
- Bounded remediation/rechecks: enforce declared reads, recursive value grammar,
  duplicate/type/order validation, compile-fail cases, and runtime validity
  tests without introducing returned storage authority.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-API-003: Retention declaration negotiates an unavailable M3 capability

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: M3 scope boundary, FR-PROC-009, and explicit
  capability negotiation.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: the descriptor/application schemas contain retention
  booleans even though no M3 context operation can perform negotiated
  lease/token transfer.
- Expected behavior: the main decision is to reject every M3 retention
  declaration as unsupported; M3 must not add lease/token authority.
- Observed behavior: retention can participate in negotiation despite having no
  executable native-processor contract.
- Reproduction and seed/trace: assemble a processor declaring retention against
  applications with retention disabled and enabled; deterministic.
- Failing layer: capability schema and assembly validation.
- Bounded remediation/rechecks: reject retention unconditionally before
  preparation, document the M3 exclusion, and test both application settings;
  leave M2 unchanged.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-API-004: Prepared state may be destroyed while workers remain live

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-005..007, FR-STATE-001/004, AC-012,
  prepared/worker ownership and exact reverse cleanup.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: prepared and worker wrappers are independently
  deinitializable; no owner-mediated live-worker count prevents prepared
  destruction while worker state may retain prepared pointers.
- Expected behavior: checked owner-mediated lifecycle enforces configured
  worker capacity, live counts, worker-before-prepared cleanup, stale/recycled
  rejection, and repeated-call safety.
- Observed behavior: an application can deinitialize prepared state before a
  live worker and create dangling worker references or double lifecycle use.
- Reproduction and seed/trace: construct multiple workers including one that
  retains a prepared pointer; attempt early prepared deinit, over-capacity,
  stale/recycled and repeated deinit paths; deterministic.
- Failing layer: public prepared/worker lifecycle ownership.
- Bounded remediation/rechecks: introduce one checked lifecycle owner/generation
  with live/capacity accounting, rollback and exact reverse cleanup tests.
- Addressing evidence: pointer-free handles require an explicitly live owner;
  wrong-owner, forged identity/index/generation, live-owner deinit, copied stale,
  recycled, repeated, and post-owner scalar-only cases pass.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-API-005: Public resource limits omit framework-owned memory

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-002/008, INV-RES-001/002, AC-012.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: limits cover processor estimates but omit outer prepared
  and worker wrappers, tuple/budget state, and actual fixed metadata storage.
- Expected behavior: resource admission includes exact checked framework and
  processor memory at every configured worker count.
- Observed behavior: a configuration can pass limits while consuming omitted
  framework-owned bytes.
- Reproduction and seed/trace: compare reported totals to `@sizeOf` framework
  wrappers/tuples/metadata at zero, exact, under, max, large, overflow, and
  multiworker inputs; deterministic.
- Failing layer: public resource contract and assembly admission.
- Bounded remediation/rechecks: address with M3-RES-002/003/005 and validate
  exact accounting across the public harness.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-API-006: Metric and event declarations are unbounded booleans

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-PROC-002/008, FR-EXT-002, bounded declaration
  schemas while observability runtime remains deferred.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: service capability booleans advertise metrics/events
  without concrete stable IDs, types, or finite bounds.
- Expected behavior: descriptors contain concrete comptime metric/event tuples
  with stable identity, type and explicit bound; duplicates/conflicts and
  unavailable application support reject before preparation, without handles.
- Observed behavior: a boolean cannot validate declaration identity, type,
  cardinality, record size, or application availability.
- Reproduction and seed/trace: compile duplicate/conflicting/unbounded schemas
  and assemble a valid schema without application availability; deterministic.
- Failing layer: extension/service declaration schema.
- Bounded remediation/rechecks: add bounded declaration tuples, comptime and
  assembly validation, compile-fail/runtime tests, and document runtime deferral.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-RES-001: Construction allocators remain usable after construction

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: INV-RES-001/002, FR-PROC-003/006/008, and no
  undeclared packet-path allocation.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: prepared/worker values can retain the passed counted
  allocator and allocate later because the authority is not sealed by phase.
- Expected behavior: every reachable construction allocator is phase-limited
  and sealed after construction; later allocation/reallocation fails without a
  runtime pool or returned allocator authority.
- Observed behavior: retained allocator authority can spend construction budget
  during processing or after the lifecycle function returns.
- Reproduction and seed/trace: retain prepared and worker allocators, then try
  alloc/resize/remap/free after construction and during processing in all modes;
  deterministic.
- Failing layer: allocator authority lifetime.
- Bounded remediation/rechecks: seal address-stable counted allocators after
  each construction phase, instrument reachable paths, and test denial/cleanup.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-RES-002: Resource accounting omits exact framework allocations

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: INV-RES-001/002, FR-PROC-002/008, AC-012.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: admission does not charge outer `PreparedPipeline` and
  `WorkerPipeline`, inline tuples/budget state, or the full actual
  `MetadataStore` footprint.
- Expected behavior: checked hard limits include every framework byte exactly,
  with zero/exact/under/max/large/overflow/multiworker cases.
- Observed behavior: reported totals can be lower than the admitted framework
  footprint.
- Reproduction and seed/trace: derive exact `@sizeOf` values, compare admitted
  totals and one-byte-under rejection over multiple worker counts; deterministic.
- Failing layer: resource estimate aggregation and public reporting.
- Bounded remediation/rechecks: add exact framework categories/totals and tests
  while preserving checked overflow and deterministic cleanup.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-RES-003: Worker count is not an enforced lifecycle capacity

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-005..008, AC-012, prepared lifetime.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: `worker_count` multiplies estimates but prepared state does
  not enforce an exact maximum number of simultaneously live workers.
- Expected behavior: the prepared owner enforces configured capacity, exact and
  over-capacity behavior, rollback, worker-before-prepared teardown, and repeated
  start/stop safety.
- Observed behavior: callers can instantiate beyond the count used for
  admission and may destroy prepared state while workers remain.
- Reproduction and seed/trace: instantiate exact count plus one, inject partial
  worker failure, attempt early destroy, then repeat cycles; deterministic.
- Failing layer: prepared/worker lifecycle and resource contract.
- Bounded remediation/rechecks: combine with M3-API-004 using checked owner
  generation/live counts and exact reverse cleanup tests.
- Addressing evidence: pointer-free handles and owner-mediated operations enforce
  admitted capacity, wrong-owner/forgery/stale rejection, invalidation before
  cleanup, and exact slot-generation reuse.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-RES-004: Declared maximum work is not authoritative

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-002/008, INV-RES-001/002, AC-012.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: descriptor fixed/per-active work is not proved against its
  maximum, estimates need not cover the worst case, and runtime results are not
  bound to the accepted per-stage/application budget.
- Expected behavior: checked `fixed + per_active * max_batch <= maximum_total`,
  estimates cover it, aggregate admission is checked, and runtime rejects a
  stage result exceeding accepted work.
- Observed behavior: inconsistent declarations and excessive runtime work can
  pass validation/admission.
- Reproduction and seed/trace: under/exact/overflow/partial/aggregate declaration
  and runtime-result cases; deterministic.
- Failing layer: comptime work schema, resource admission, runtime enforcement.
- Bounded remediation/rechecks: make worst-case work authoritative and add
  compile-fail/runtime tests with failure-atomic packet behavior.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-RES-005: Aggregate budget allows per-stage slack laundering

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-003/006/008, INV-RES-002, AC-012.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: one aggregate prepared/worker allocator allows a stage
  that underestimated its own allocation to consume unused estimate from
  another stage.
- Expected behavior: every stage has an exact sub-budget in addition to checked
  aggregate totals; no stage can spend another stage's slack.
- Observed behavior: aggregate headroom can conceal stage-local
  underestimation.
- Reproduction and seed/trace: two stages with opposing over/under allocation
  whose aggregate remains within the limit; deterministic cleanup check.
- Failing layer: allocator/resource ownership and estimate enforcement.
- Bounded remediation/rechecks: create address-stable per-stage sealed budgets,
  preserve aggregate reporting, and test denial plus exact cleanup.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-RES-006: Allocation-failure coverage is not exhaustive across public flows

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-TEST-001, FR-PROC-005..008, INV-PKT-001,
  constructor/preparation allocation-failure and cleanup evidence.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: existing sweeps do not exhaust multistage prepare and
  instantiate plus harness init/submit/result/output allocation points.
- Expected behavior: each allocation point fails cleanly with full reverse
  cleanup, token reconciliation, live-byte baseline, output/backpressure, zero
  fixtures, and repeated start/stop coverage in all modes.
- Observed behavior: several public allocation paths are not swept.
- Reproduction and seed/trace: failing-allocator index sweep until success for
  each public flow; deterministic exact allocation index.
- Failing layer: public test harness and lifecycle failure evidence.
- Bounded remediation/rechecks: extend exhaustive sweeps and assert resource,
  token, ownership, output and cleanup baselines.
- Addressing evidence: the public harness sweep has two allocating stages and
  traverses induced failures through preparation, instantiation, synthetic
  submission, output, result copies, reconciliation, reverse cleanup, and the
  first non-induced success; complete teardown is repeated.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-PERF-001: Retained validator trusts derived benchmark fields

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: PERF-CORE-001 and source-bound artifact integrity.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: the M3 validator does not fully validate schema,
  commit/tree/ancestry, raw hash, generation digest/full inputs, or recompute all
  medians, dispersion, ratios and the threshold from retained samples.
- Expected behavior: every derived field and binding is recomputed, and forged
  artifacts fail deterministic negative controls.
- Observed behavior: selected stored summaries can be modified without an
  independent recomputation failure.
- Reproduction and seed/trace: mutate each binding/median/dispersion/ratio/pass
  field in an in-memory temporary artifact and run validator controls.
- Failing layer: benchmark evidence validator.
- Bounded remediation/rechecks: validate the full schema and bindings, recompute
  all statistics/thresholds, and add forged negative controls without
  regenerating the retained artifact before authority acknowledgment.
- Addressing evidence: validation now checks each complete order permutation and
  recomputes ns/packet, cycles/packet, and packet rate from raw elapsed/cycles,
  batch, and measurement iterations under recorded decimal-print tolerances.
  Ten negative controls include duplicate order and inconsistent elapsed/cycles.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-PERF-002: CI fresh benchmark is not consumed as current bound evidence

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: PERF-CORE-001 and same-gate current-source
  quantitative evidence.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: CI runs a fresh human-readable benchmark and separately
  validates a retained artifact; the fresh output is not captured, structured,
  thresholded, or bound to the same clean commit/tree/full inputs.
- Expected behavior: one gate captures fresh structured output, consumes it,
  enforces the threshold, and binds it to the current clean source identity.
- Observed behavior: fresh samples and retained pass can describe different
  runs/source trees.
- Reproduction and seed/trace: alter fresh output to fail while retained JSON
  remains passing; current CI validates only the latter.
- Failing layer: build/CI benchmark evidence flow.
- Bounded remediation/rechecks: wire capture/generate/validate as one clean-tree
  command after authority acknowledgment; implement tooling now but do not run
  artifact regeneration or cumulative CI in this checkpoint.
- Addressing evidence: the reviewed controller passed against acknowledged
  source `978cf09`/`5d98a71`, and cumulative CI passed its own clean-tree fresh
  controller plus retained validation without selective reruns.
- Closure result: closed by `m3_resource_review` at clean non-WIP tip
  `933128bccc1401fd994f81c2c50e1d4f74c9dab9`, tree
  `90aeb35acb61605bd71bc31fd155b8dfb18b49ad`. The controller performed all
  seven launches, raw capture, generation, schema/statistic/threshold
  validation in one invocation and rejected HEAD/status changes. Retained
  evidence bound source `978cf0937ab6cf93a060b5a18866c17260542e90`, tree
  `5d98a718451d516c2894aaf845265d1d1fda3acd`, raw SHA-256
  `f5460f94162d7ff77963538f88e76d90c61ac076283e915e64b72a3110b3dac2`,
  artifact commit `9e6ffd632c302dc17b8b4cd322489976f5d1dbbb`, tree
  `28c2ceacc4b903f0e9a4c7f2cbcc36bd24553be8`. Cumulative CI completed in
  478 seconds with fresh ratios 1.007751/0.996709.

## M3-PERF-003: Benchmark lacks independent warmed run aggregation

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: PERF-CORE-001 quantitative methodology.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: all samples are emitted by one process launch and the
  artifact reports one independent run.
- Expected behavior: at least seven independently launched warmed runs retain
  per-run samples with deterministic nonselective execution and a run-level
  aggregate.
- Observed behavior: process-level variation and selective rerun resistance are
  absent.
- Reproduction and seed/trace: inspect methodology and retained sample grouping;
  one launch/run is recorded.
- Failing layer: benchmark runner, artifact schema, and aggregation.
- Bounded remediation/rechecks: add >=7-run orchestration, per-run records,
  deterministic run order and aggregate recomputation; defer actual capture
  until acknowledgment.
- Addressing evidence: the retained artifact contains seven independent warmed
  launches, five samples per launch, 35 samples per variant, all variants at
  batches 32/64, complete order permutations, and per-run/combined aggregates.
- Closure result: closed by `m3_resource_review` at `933128b`/`90aeb35` after
  verifying launch IDs 1..7, 200 warmup iterations, five samples per run, 35
  samples per variant, batches 32/64, all eight variants in every
  run/batch/sample, 560 rows, and complete order permutations. Independently
  recomputed retained ratios were 1.005035695254069 and 0.9916261193325275,
  both at or above 0.95.

## M3-PERF-004: Canonical schema gate omits M3 negative coverage

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: benchmark schema validation and negative controls.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: `tools/m0/validate-schemas.sh` does not explicitly include
  the M3 artifact and an M3-specific malformed negative case.
- Expected behavior: the canonical schema gate validates the M3 artifact and
  rejects a deterministic M3 malformed example.
- Observed behavior: M3 relies on incidental glob/schema behavior without an
  explicit negative control.
- Reproduction and seed/trace: inspect the canonical script inputs and negative
  fixtures; deterministic.
- Failing layer: canonical schema gate.
- Bounded remediation/rechecks: add the narrowly authorized M3 positive and
  negative cases and run schema checks without regenerating the artifact.
- Addressing evidence: canonical `schemas`, current retained evidence, and all
  ten validator negative controls passed before the artifact commit; cumulative
  CI repeated schema and retained-evidence validation successfully.
- Closure result: closed by `m3_resource_review` at `933128b`/`90aeb35`. The
  independent outputs were `M3 retained benchmark evidence passed`, `M3
  benchmark validator negative controls passed: 10`, and
  `benchmark/environment examples and negative schema conditions passed`;
  canonical schema validation included M3 and rejected fewer than seven runs.
  PERF-001/005/006 were not regressed and no performance blocker remained at
  that reviewed tree.

## M3-PERF-005: Benchmark controls do not hold runtime plumbing constant

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: PERF-CORE-001 comparison validity and reversal
  trigger evidence.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: monolith/vtable controls bypass most pipeline plumbing and
  execute near-empty loops, making their rates incomparable to direct pipeline
  variants.
- Expected behavior: controls use the same batch ownership, disposition,
  metadata and loop plumbing, differing only in dispatch, or are labeled
  non-comparable and removed from reversal claims.
- Observed behavior: control results are orders of magnitude faster and can
  mislead the preserved alternative decision.
- Reproduction and seed/trace: compare the direct and control code paths and
  retained rates at batches 32/64.
- Failing layer: benchmark experimental design and documentation.
- Bounded remediation/rechecks: prefer comparable control runners that hold
  plumbing constant; update validation/documentation and defer fresh capture.
- Addressing evidence: schema, generator, validator, and documentation classify
  monolith/vtable as non-comparable diagnostic-only, explicitly exclude them
  from acceptance and architecture decisions, and make no reversal inference.
- Closure result: closed by the discovering reviewer at source commit
  `46c34eb06d43a35ddca295001cb0052f7df067cc`, tree
  `2ea1aa6dc5f6abef4d02c150f31bf2877c8ec8bd`; result relayed by the main
  session. The later test-only correction did not reopen this finding; renewed
  inventory acknowledgment is recorded above.

## M3-PERF-006: Deep execution does not prove terminal short-circuiting

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: FR-COMP-002, AC-003, static pipeline performance
  behavior.
- Discoverer: `m3_resource_review` (performance perspective)
- Assigned writer: `m3_writer`
- Concrete evidence: no deep counter scenario proves that a fully terminal
  selection prevents every later processor call; existing benchmark processors
  are no-ops.
- Expected behavior: a deep pipeline records exact per-stage calls and shows all
  later stages `not_run` after terminal completion, in tests and benchmark
  plumbing.
- Observed behavior: short-circuiting is covered only by shallower scenarios.
- Reproduction and seed/trace: terminalize all packets in an early stage of a
  deep pipeline and inspect later call counters/statuses; deterministic.
- Failing layer: runtime evidence and benchmark scenario coverage.
- Bounded remediation/rechecks: add deep terminal counter tests and a benchmark
  variant/control using actual pipeline status.
- Addressing evidence: implemented and rechecked as recorded in the writer addressing matrix and mandatory authority-return inventory above.
- Closure result: closed by the discovering reviewer; result relayed by the
  main session before this second remediation.

## M3-FRESH-001: Public pipeline errors expose a live partially processed batch

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-004, FR-PKT-014/015, AC-003/012,
  INV-PKT-001/002, failure atomicity, and the mandatory authority-return
  checkpoint.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: public pipeline callbacks can mutate packet bytes and set
  terminal dispositions before a later `WorkContractViolation` or
  `DispositionFailure`; the error path returns without a result while the
  caller's batch generation and pre-minted aliases remain live.
- Expected behavior: validate the complete disposition configuration before
  any callback; after a callback begins, no returned pipeline-detected error
  leaves a live partially processed batch. Non-revocable escaped authority
  must reject before callbacks, and adapter tokens must remain exactly once
  reconcilable by the caller/harness.
- Observed behavior: disposition table/default errors are detected during
  final resolution after callbacks, and work-contract failure returns the
  still-live generation.
- Reproduction and seed/trace: deterministic mutating processor sets a
  terminal disposition, overreports work, then probes its pre-minted batch,
  view, editor, and output aliases; deterministic invalid-config cases count
  callback invocations and inspect packet bytes.
- Failing layer: public pipeline entry validation and post-callback error
  revocation.
- Bounded remediation/rechecks: validate bounded unique routing against the
  copied application set, all generated outputs, default, and `Continue`
  policy before callbacks; reject pre-existing non-revocable raw authority;
  invalidate the exact generation on every later error; cover direct and
  harness token/error/stop behavior in all modes.
- Addressing evidence: disposition routing now validates without effects before
  callbacks; pre-existing non-revocable raw authority rejects before callback;
  a single post-callback error defer invalidates every revocable batch alias.
  Direct and public-harness scenarios passed in Debug, ReleaseSafe, and
  ReleaseFast, including invalid configurations with zero callbacks/unchanged
  bytes, mutation plus terminal disposition plus excess work, stale/recycled
  aliases, all error/stop policies, and exact token reconciliation. The renewed
  exact authority inventory above was audited at the clean committed source
  checkpoint.
- Closure result: closed by the discovering reviewer `m3_api_review` at exact
  clean source commit `1839df61e63530ce30a1554a8a1c895f25932ce5`,
  tree `8c367eacabe8e1b7f218a2fa1cad19613cce004a`; result relayed by the main
  session together with renewed authority-return acknowledgment.

## M3-FRESH-002: Benchmark constructor leaks partial ownership on failure

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: INV-RES-001/002, benchmark-only constructor
  cleanup, adapter-token reconciliation, and exact reverse teardown.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: `Bench.init` transfers receive tokens without an unwind
  reconciliation path, omits immediate worker `errdefer` registration for
  `w8` and the terminal worker, and tears prepared pipelines down out of exact
  reverse order.
- Expected behavior: every error after token transfer returns received tokens;
  every worker has cleanup registered before the next fallible operation;
  workers and prepared pipelines unwind and tear down in exact reverse; an
  every-index failing allocator sweep proves allocated equals freed, received
  equals completed, no panic, and ordered cleanup.
- Observed behavior: constructor failure after ownership transfer can leave
  tokens worker-owned and late worker/prepared resources live or out of order.
- Reproduction and seed/trace: deterministic `std.testing.FailingAllocator`
  sweep over `Bench.init`; no random seed.
- Failing layer: `bench/micro/m3_static_pipeline.zig` constructor/teardown.
- Bounded remediation/rechecks: add one exact token reconciliation helper,
  immediate `errdefer` per constructed worker, exact reverse worker/prepared
  teardown, and a benchmark-local constructor sweep wired into `m3-test`
  without executing benchmark samples.
- Addressing evidence: every transferred receive token now has an error unwind,
  every worker cleanup is registered before the next fallible instantiate, and
  both failure/success paths destroy workers then prepared pipelines in exact
  reverse order. The benchmark-local failing-allocator sweep passed in Debug,
  ReleaseSafe, and ReleaseFast through the first non-induced index with
  allocated bytes equal to freed bytes and received tokens equal to completed
  tokens; the ReleaseFast benchmark binary compiled without executing samples.
- Closure result: closed by the discovering reviewer `m3_api_review` at exact
  clean source commit `1839df61e63530ce30a1554a8a1c895f25932ce5`,
  tree `8c367eacabe8e1b7f218a2fa1cad19613cce004a`; result relayed by the main
  session together with renewed authority-return acknowledgment.

## M3-FRESH2-001: Thread-local invocation cookies collide across active threads

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-004/009, INV-PKT-001/002, exact
  descriptor/effective-capability provenance, call-scoped authority, and the
  mandatory authority-return checkpoint.
- Discoverer: `m3_resource_review`
- Assigned writer: `m3_writer`
- Concrete evidence: `src/internal/processor_invocation.zig` mints a copyable
  scalar `ProcessContext` cookie from thread-local `next_cookie`. The first
  same-descriptor invocation on threads A and B can therefore mint cookie `1`
  twice while B's invocation is active.
- Expected behavior: invocation identity is unique for the process lifetime,
  never wraps or repeats after escape, and authenticates only the exact active
  call, descriptor binding, and effective capabilities. Exhaustion rejects
  before installing state, with no public mint/reset/control surface.
- Observed behavior: A's escaped cookie can equal B's active cookie and
  authenticate against B's thread-local state when A probes during B's active
  invocation.
- Reproduction and seed/trace: deterministically synchronize A's completed
  first invocation with B's active first invocation of the same descriptor;
  compare identities, probe A's escaped context during B's callback, and prove
  no batch operation succeeds. No random seed.
- Failing layer: package-internal invocation identity provenance and
  cross-thread context authentication.
- Bounded remediation/rechecks: use a process-wide atomic checked monotonic
  identity allocator with permanent fail-closed exhaustion; retain thread-local
  active state, exact descriptor/effective-capability checks, and private
  bridge visibility; add local-counter exhaustion evidence plus the
  synchronized two-thread regression in all modes and AArch64 compile.
- Addressing evidence: the package-internal mint now uses one process-wide
  `std.atomic.Value(u64)` with a checked CAS increment. Identity zero is never
  issued; reaching `maxInt(u64)` permanently returns `InvocationExhausted`
  before active state is installed, with no production reset or reuse path.
  The thread-local record still binds the exact active identity, descriptor,
  effective capabilities, and packet state. A deterministic two-thread
  same-descriptor regression completes A's first invocation, begins B's first
  invocation, proves the identities differ, and proves A's escaped context
  returns `InvocationInactive` for both selection and packet access while B's
  exact context remains usable. A private local-counter test proves one final
  identity followed by repeated fail-closed exhaustion without changing the
  production counter. Root and M3 tests pass in Debug, ReleaseSafe, and
  ReleaseFast; the external suite passes one legitimate pipeline plus 27
  compile failures; the deterministic example, ReleaseSafe Linux AArch64
  compile, format, docs/links, 51-claim coverage, version consistency, both
  immutable manifests, and diff checks pass. No artifact, schema, benchmark,
  cumulative CI, integration, remote, or specification action ran.
- Closure result: closed by the discovering reviewer `m3_resource_review` at
  exact clean source commit `8828ab7460e8bddfd389692d090496b8d6da8f3d`,
  tree `ad390d93d8fd0af7dec1e8058d5387d5bf46a3d1`; result supplied by the main
  session together with renewed authority-return inventory acknowledgment.
  The reviewer confirmed process-wide checked monotonic CAS identities are
  unique and nonzero, fail permanently closed at exhaustion, preserve
  thread-local reentrancy rejection before allocation, and authenticate the
  exact identity, descriptor, and effective capabilities. The synchronized
  two-thread regression rejects A's completed selection and packet context
  during B's valid invocation, and the private exhaustion test proves the final
  identity plus repeated rejection. Reviewer-focused root/M3 all-mode,
  manifest, diff, and clean-status checks passed. The reviewer's additional
  contract/AArch64/docs rerun approval was disconnected; the writer-focused
  passing evidence for those checks remains recorded above and was not claimed
  as a reviewer rerun.

## M3-FINAL-001: Descriptor-binding collisions can substitute broader authority

- Status: `closed`
- Severity: High
- Requirement/invariant/gate: FR-PROC-004/009, FR-EXT-001/003,
  INV-PKT-001/002, exact stage capability provenance, and the mandatory
  authority-return checkpoint.
- Discoverer: `m3_api_review`
- Assigned writer: `m3_writer`
- Concrete evidence: public `ProcessContext.authority_binding` reduces a
  descriptor to an invertible rolling `u64`, the package-internal invocation
  record authenticates only that scalar, and pipeline preparation installs
  application-wide rather than per-stage effective capabilities. The narrow
  descriptor with processor ID 90, API 3, metadata-only access, no
  dispositions, and no outputs has binding `0x629b8ddd51712b5d`. A forged
  descriptor with the same ID/API, trusted raw edit, Accept, and output
  `0x80640c6b19736702` has the same binding.
- Expected behavior: one invocation authenticates an exact private generated
  context/processor identity that external processor code cannot mint or
  select by fabricating a descriptor. Every operation independently enforces
  the exact descriptor intersected with application authority for packet
  access, dispositions, raw edit, time, outputs, and metadata.
- Observed behavior: retyping the active scalar cookie as the colliding forged
  context can authenticate and receive the application-wide rights, allowing
  undeclared packet, disposition, raw-edit, output, or metadata operations
  when the application supplied them.
- Reproduction and seed/trace: deterministically invoke the narrow descriptor
  under broad application capabilities; retype its active cookie to the exact
  colliding descriptor above and attempt read, structured edit, trusted raw
  edit, disposition/output, metadata input, and metadata output operations.
  No random seed.
- Failing layer: public context identity, package-internal invocation
  authentication, and pipeline effective-capability installation.
- Bounded remediation/rechecks: replace the finite public descriptor binding
  with an unexported exact per-context/per-processor type identity; install
  fixed pointer-free per-stage rights intersected with the descriptor and
  application; validate those rights in every applicable context operation;
  add the exact collision and two-stage broad-application isolation
  regressions while preserving new/stale/cross-thread/exhaustion evidence.
- Addressing evidence: removed public `authority_binding`; the internal active
  record now authenticates an exact private generated context-type marker and
  retains the process-wide nonzero nonreusing invocation identity. Pipeline
  assembly installs fixed exact per-stage intersections, and context methods
  recheck packet access, disposition mask, descriptor-plus-application raw/time
  opt-in, exact output IDs, and exact metadata key identities. Deterministic
  tests preserve the supplied `0x629b8ddd51712b5d` / `0x80640c6b19736702`
  collision, construct a second exact metadata collision, reject every retyped
  attempt before effects, prove the narrow actual context's declared behavior,
  and isolate two stages under broad application authority. Focused root and M3
  tests passed in Debug, ReleaseSafe, and ReleaseFast; one external valid
  pipeline plus 28 compile-fail cases, the deterministic example, ReleaseSafe
  Linux AArch64 compile, both specification manifests, coverage, and version
  consistency passed. Formatting, documentation, diff, and clean-status checks
  bind the final checkpoint. The retained benchmark artifact remains stale and
  must not be regenerated or validated before discoverer closure and renewed
  inventory acknowledgment.
- Closure result: closed by the discovering reviewer `m3_api_review` at exact
  clean source commit `1dd66147c8102de034bb4f9ee9930c05db973aec`, tree
  `11d25fb9d49beee8fc2c0df73503c59536087f8c`; result supplied by the main
  session together with renewed authority-return inventory acknowledgment.
  The reviewer confirmed the private exact generated context-type identity,
  per-stage capability intersection and method-level enforcement, exact
  packet/output and metadata collision rejection before effects, broad
  application two-stage isolation, and preserved new/stale/cross-thread/
  exhaustion behavior. Reviewer-focused manifests, root and M3 tests in all
  modes, one valid plus 28 compile-fail cases, ReleaseSafe Linux AArch64
  compile, diff, and clean-status checks passed. No additional material finding
  was reported, and current-source artifact refresh is unlocked.

## M3-GATE-001: Verifier retained a fresh benchmark over the committed artifact

- Status: `closed`
- Severity: Medium
- Requirement/invariant/gate: final exact-tree verification must preserve the
  committed non-WIP tip/tree and finish with clean ordinary status; a verifier
  must not rewrite source-bound retained evidence outside the canonical gate.
- Discoverer: `m3_final_gate`
- Assigned writer: `m3_writer`
- Concrete evidence: the verifier began at exact clean committed tip
  `295e0d1bd93e7aceef56235d95db44c6221b744f`, tree
  `0f1de901526dd37a4c4fc84df62e51f4024da3ac`, then ran the extra command
  `nix develop --command python3 tools/m3/benchmark-gate.py --retain
  bench/examples/benchmark.m3.json`. The `--retain` option intentionally writes
  a newly sampled artifact and changed only that tracked file, from committed
  SHA-256 `6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`
  to uncommitted SHA-256
  `eee185adcdcd135ede98f4a0a693fdfa8c2b03314db78d159864da8e25da6a2a`.
- Expected behavior: the independent final verifier runs the canonical
  cumulative gate and read-only retained-evidence checks without retaining a
  second artifact. Commit, tree, and ordinary status remain unchanged and
  clean for the entire exact-tree proof.
- Observed behavior: the extra verifier-only `--retain` command dirtied the
  worktree after the committed artifact and writer evidence had already
  passed. This is a verifier command-selection and final-gate hygiene failure,
  not a canonical CI, product, schema, retained-artifact, or PERF-CORE-001
  failure. The first verifier attempt remains failed and is not reclassified as
  passing; a clean retry is required.
- Reproduction and seed/trace: execute the exact command above from the clean
  committed tip. Performance samples are intentionally nondeterministic, but
  the tracked-file mutation is deterministic whenever `--retain` names the
  repository artifact.
- Failing layer: independent final-gate command selection and clean-tree
  preservation.
- Bounded remediation/rechecks: with direct user authorization, restore only
  `bench/examples/benchmark.m3.json` byte-for-byte from committed `HEAD`, record
  this incident without changing source/tool/build/schema/authority state, and
  run immutable manifests, documentation/links, schemas, retained-artifact
  validation, ten negative controls, diff, and ordinary/ignored status checks.
  Do not regenerate the benchmark or rerun cumulative CI. Commit the incident
  alone, then return the clean new tip for a fresh `m3_final_gate` retry that
  omits the extra retaining command.
- Addressing evidence: the verifier-generated artifact was restored exactly to
  committed SHA-256
  `6437d1d35cf6f19603fbf6b54c5f8ff371e23a94ad8fdd5a06192639958b0cbf`;
  focused recovery checks and the clean evidence-only recovery commit are
  recorded by this finding. No benchmark generation or cumulative CI rerun is
  part of the recovery.
- Closure result: closed by the discovering verifier `m3_final_gate` after the
  clean independent retry passed at exact non-WIP tip
  `9c008e59243d148bcf4f85efcf8fd20f8d6ea4af`, tree
  `18d2c7d4246775e69573c2ed98c6824038d7b7cd`; result supplied by the main
  session together with acceptance of the M3 final gate. The retry omitted the
  extra retaining command, passed both immutable manifests and canonical
  cumulative `nix develop --command zig build ci`, passed the baseline-to-tip
  diff check, and proved unchanged commit/tree plus clean ordinary status. The
  first verifier attempt remains recorded above as failed; its recovery is not
  used to reclassify that attempt. No additional material finding was reported.
