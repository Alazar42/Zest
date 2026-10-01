const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 1. Primary exported package module: `b.dependency("zest", ...).module("zest")`
    const zest_mod = b.addModule("zest", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zest_mod.link_libc = true;
    zest_mod.linkSystemLibrary("sqlite3", .{});
    zest_mod.linkSystemLibrary("pq", .{});

    // Alias uppercase "Zest" for case-insensitive compatibility
    const zest_mod_upper = b.addModule("Zest", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    zest_mod_upper.link_libc = true;
    zest_mod_upper.linkSystemLibrary("sqlite3", .{});
    zest_mod_upper.linkSystemLibrary("pq", .{});

    // 2. Library unit tests: `zig build test`
    const mod_tests = b.addTest(.{
        .root_module = zest_mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run all Zest library unit and integration tests");
    test_step.dependOn(&run_mod_tests.step);

    // 3. Example application runner: `zig build run`
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("example/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "zest", .module = zest_mod },
            .{ .name = "Zest", .module = zest_mod },
        },
    });
    exe_mod.linkSystemLibrary("sqlite3", .{});
    exe_mod.linkSystemLibrary("pq", .{});

    const exe = b.addExecutable(.{
        .name = "zest-example",
        .root_module = exe_mod,
    });

    const run_step = b.step("run", "Run the example server application");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
