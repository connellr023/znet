const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("znet", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });
    const lib = b.addLibrary(.{
        .name = "znet",
        .root_module = mod,
    });
    const c_enet_dep = b.dependency("c_enet", .{
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

    b.installArtifact(lib);
}
