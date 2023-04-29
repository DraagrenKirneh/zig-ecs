const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("ecs", .{ .source_file = .{ .path = "src/ecs.zig" } });

    const test_step = b.step("test", "Run zig-ecs tests");
    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/ecs.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
