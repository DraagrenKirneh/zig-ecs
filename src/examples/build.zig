const std = @import("std");

pub const Package = struct {
    ecs: *std.Build.Module,

    pub fn build(b: *std.Build) Package {
        const ecs = b.createModule(.{
            .source_file = .{ .path = thisDir() ++ "/../ecs.zig" },
        });

        return .{
            .ecs = ecs,
        };
    }
};

inline fn thisDir() []const u8 {
    return comptime std.fs.path.dirname(@src().file) orelse ".";
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const tests = buildTests(b, optimize, target);

    const test_step = b.step("test", "Run zig-ecs tests");
    test_step.dependOn(&tests.step);
}

pub fn buildTests(
    b: *std.Build,
    optimize: std.builtin.Mode,
    target: std.zig.CrossTarget,
) *std.Build.CompileStep {
    const ecs_module = Package.build(b).ecs;
    const tests = b.addTest(.{
        .root_source_file = .{ .path = thisDir() ++ "/query.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addModule("ecs", ecs_module);
    return tests;
}
