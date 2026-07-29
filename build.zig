// SPDX-License-Identifier: Apache-2.0
const std = @import("std");

/// Defines the canonical hardware-free build, test, documentation, and quality
/// steps. It performs configuration only and does not execute packet-path code.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const saint_module = b.addModule("saint_shield", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const library = b.addLibrary(.{
        .name = "saint_shield",
        .linkage = .static,
        .root_module = saint_module,
    });
    b.installArtifact(library);

    const root_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_root_tests = b.addRunArtifact(root_tests);
    const test_step = b.step("test", "Run unit and M0-V scaffold tests");
    test_step.dependOn(&run_root_tests.step);

    const example_module = b.createModule(.{
        .root_source_file = b.path("examples/static_filter/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_module.addImport("saint_shield", saint_module);
    const example = b.addExecutable(.{
        .name = "saint-shield-static-filter",
        .root_module = example_module,
    });
    b.installArtifact(example);

    const run_example = b.addRunArtifact(example);
    const example_step = b.step("example", "Build and run the hardware-free example");
    example_step.dependOn(&run_example.step);

    const bench_module = b.createModule(.{
        .root_source_file = b.path("bench/micro/m0v_smoke.zig"),
        .target = target,
        .optimize = optimize,
    });
    bench_module.addImport("saint_shield", saint_module);
    const bench = b.addExecutable(.{
        .name = "m0v-bench-smoke",
        .root_module = bench_module,
    });
    const run_bench = b.addRunArtifact(bench);
    const bench_step = b.step("bench", "Run the synthetic M0-V benchmark smoke");
    bench_step.dependOn(&run_bench.step);

    const m1_bench_module = b.createModule(.{
        .root_source_file = b.path("bench/micro/m1_regression.zig"),
        .target = target,
        .optimize = optimize,
    });
    m1_bench_module.addImport("saint_shield", saint_module);
    m1_bench_module.addAnonymousImport("benchmark_m1_json", .{
        .root_source_file = b.path("bench/examples/benchmark.m1.json"),
    });
    const m1_bench = b.addExecutable(.{
        .name = "m1-synthetic-regression",
        .root_module = m1_bench_module,
    });
    const run_m1_bench = b.addRunArtifact(m1_bench);
    const m1_bench_step = b.step(
        "m1-bench",
        "Run M1 synthetic zero-copy regression evidence (not capacity)",
    );
    m1_bench_step.dependOn(&run_m1_bench.step);

    const docs = library.getEmittedDocs();
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs,
        .install_dir = .prefix,
        .install_subdir = "docs/zig",
    });
    const docs_step = b.step("docs", "Generate Zig API documentation");
    docs_step.dependOn(&install_docs.step);

    const aarch64_target = b.resolveTargetQuery(.{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .gnu,
    });
    const aarch64_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = aarch64_target,
        .optimize = optimize,
    });
    const aarch64_library = b.addLibrary(.{
        .name = "saint_shield-aarch64-linux",
        .linkage = .static,
        .root_module = aarch64_module,
    });
    const install_aarch64 = b.addInstallArtifact(aarch64_library, .{});
    const aarch64_step = b.step("cross-aarch64", "Cross-compile the public library for Linux AArch64");
    aarch64_step.dependOn(&install_aarch64.step);

    addCommandStep(b, "fmt-check", "Check canonical Zig formatting", &.{
        "zig", "fmt", "--check", "build.zig", "src", "examples", "test", "bench",
    });
    addCommandStep(b, "schemas", "Validate benchmark and environment JSON examples", &.{
        "sh", "tools/m0/validate-schemas.sh",
    });
    addCommandStep(b, "fuzz-smoke", "Run the deterministic AFL++ M0-V workflow", &.{
        "sh", "tools/m0/fuzz-smoke.sh",
    });
    addCommandStep(b, "pcap-fuzz-smoke", "Run bounded PCAP replay and AFL++ smoke", &.{
        "sh", "tools/m1/pcap-fuzz-smoke.sh",
    });
    addCommandStep(b, "dpdk-smoke", "Run DPDK ABI and virtual ring-PMD token checks", &.{
        "sh", "tools/m0/dpdk-smoke.sh",
    });
    addCommandStep(b, "integrity", "Verify pinned dependency and license metadata", &.{
        "sh", "tools/m0/verify-integrity.sh",
    });
    addCommandStep(b, "docs-check", "Validate authored documentation links", &.{
        "sh", "tools/m0/docs-check.sh",
    });
    addCommandStep(b, "coverage", "Validate the M1 requirement and evidence map", &.{
        "python3", "tools/m1/validate-coverage.py",
    });
    addCommandStep(b, "coverage-self-test", "Run M1 coverage validator negative controls", &.{
        "python3", "tools/m1/validate-coverage.py", "--self-test",
    });
    addCommandStep(b, "version-consistency", "Validate the exact M1 package/API/coverage version", &.{
        "python3", "tools/m1/validate-version.py",
    });
    addCommandStep(b, "ci-m0-v", "Run the independently invocable M0-V CI gate", &.{
        "sh", "tools/m0/ci.sh",
    });
    addCommandStep(b, "ci", "Run the complete cumulative hardware-free M1 CI gate", &.{
        "sh", "tools/m1/ci.sh",
    });
}

fn addCommandStep(b: *std.Build, name: []const u8, description: []const u8, argv: []const []const u8) void {
    const command = b.addSystemCommand(argv);
    const step = b.step(name, description);
    step.dependOn(&command.step);
}
