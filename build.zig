const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Root module for library
    const zmcp_mod = b.addModule("zmcp", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // 2. Unit & Integration Tests using root_module
    const unit_tests = b.addTest(.{
        .root_module = zmcp_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run zmcp unit & integration tests");
    test_step.dependOn(&run_unit_tests.step);

    // 3. Example MCP Server Executable
    const example_mod = b.createModule(.{
        .root_source_file = b.path("examples/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    example_mod.addImport("zmcp", zmcp_mod);

    const example_exe = b.addExecutable(.{
        .name = "zmcp-server",
        .root_module = example_mod,
    });

    const run_example = b.addRunArtifact(example_exe);
    const example_step = b.step("run-example", "Run example zmcp server");
    example_step.dependOn(&run_example.step);

    // 4. Benchmarks (ReleaseFast)
    const bench_mod = b.createModule(.{
        .root_source_file = b.path("tests/benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_mod.addImport("zmcp", zmcp_mod);

    const bench_exe = b.addExecutable(.{
        .name = "zmcp-bench",
        .root_module = bench_mod,
    });

    const run_bench = b.addRunArtifact(bench_exe);
    const bench_step = b.step("bench", "Run zmcp performance benchmark suite");
    bench_step.dependOn(&run_bench.step);
}
