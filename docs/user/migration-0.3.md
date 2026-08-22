# Migrating from 0.2 M2 to 0.3 M3

The package and public source version is now `0.3.0-m3`. Existing M1/M2 packet
ownership, parsing, mutation, output, and retention APIs are preserved.

Applications may replace manual processor sequencing with a static
`saint_shield.pipeline.Pipeline`. Native processor types must implement the
complete descriptor and lifecycle contract, report checked resource estimates,
declare every packet/service/disposition/metadata capability, and choose an
explicit error policy. Stateful processors must declare supported update modes
and a supported default even though M3 does not perform live updates.

Raw packet edits now require both `.trusted_raw_edit` in the descriptor and
`trusted_raw_edit_opt_in` at assembly. Returned processor results cannot carry
packet authority. Use `ProcessorTestHarness` for deterministic synthetic
fixtures and check the migration with `zig build m3-compile-fail m3-test`.
