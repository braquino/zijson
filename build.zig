// zig fmt: off
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod_zijson = b.addModule("zijson", .{
        .root_source_file = b.path("src/zijson.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_zijson = b.addStaticLibrary(.{ 
        .name = "zijson", 
        .root_source_file = mod_zijson.root_source_file, 
        .target = target, 
        .optimize = optimize 
    });
    const header = b.addInstallFile(b.path("c_header/zijson.h"), "include/zijson.h");
    //const header = b.addInstallFile(lib_zijson.getEmittedH(), "include/zijson.h");
    b.getInstallStep().dependOn(&header.step);
    b.installArtifact(lib_zijson);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/zijson.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    b.installArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
