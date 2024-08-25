const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .os_tag = .windows,
    });
    const optimize = b.standardOptimizeOption(.{});

    const zigwin = b.dependency("zigwin32", .{});

    const exe = b.addExecutable(.{
        .name = "zig-template",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zigwin32", zigwin.module("zigwin32"));

    exe.addLibraryPath(std.Build.LazyPath{
        .cwd_relative = "../../../../../../mnt/c/Windows/System32",
    });

    b.installBinFile("shaders.hlsl", "shaders.hlsl");

    exe.linkSystemLibrary("gdi32");
    exe.linkSystemLibrary("dwmapi");
    exe.linkSystemLibrary("d3d11");
    exe.linkSystemLibrary("d3dcompiler_47");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
