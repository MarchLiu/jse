const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zigjse", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // Unit tests from root module
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_mod_tests.step);

    // Integration tests
    const test_files = &[_][]const u8{
        "tests/basic_test.zig",
        "tests/logic_test.zig",
        "tests/query_test.zig",
    };

    for (test_files) |test_file| {
        const test_mod = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigjse", .module = mod },
            },
        });
        const it = b.addTest(.{
            .root_module = test_mod,
        });
        test_step.dependOn(&b.addRunArtifact(it).step);
    }
}
