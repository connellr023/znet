const std = @import("std");

pub fn build(bld: *std.Build) void {
    const target = bld.standardTargetOptions(.{});
    const optimize = bld.standardOptimizeOption(.{});

    const mod = bld.addModule("znet", .{
        .root_source_file = bld.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const lib = bld.addLibrary(.{
        .name = "znet",
        .root_module = mod,
    });
    const c_enet_dep = bld.dependency("c_enet", .{
        .target = target,
        .optimize = optimize,
    });

    lib.addCSourceFiles(.{
        .root = c_enet_dep.path("."),
        .files = &.{
            "host.c",
            "list.c",
            "peer.c",
            "unix.c",
            "win32.c",
            "packet.c",
            "compress.c",
            "protocol.c",
            "callbacks.c",
        },
    });
    lib.addIncludePath(c_enet_dep.path("include"));
    lib.linkLibC();

    bld.installArtifact(lib);

    const test_mod = bld.addModule("tests", .{
        .root_source_file = bld.path("src/tests.zig"),
        .imports = &.{
            .{ .name = "znet", .module = mod },
        },
        .target = target,
        .optimize = optimize,
    });
    const lib_tests = bld.addTest(.{
        .root_module = test_mod,
    });
    const run_lib_tests = bld.addRunArtifact(lib_tests);
    const test_step = bld.step("test", "Run unit tests");

    test_step.dependOn(&lib_tests.step);
    test_step.dependOn(&run_lib_tests.step);
}
