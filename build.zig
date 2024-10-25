const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml = b.dependency("zig-xml", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "gdbus-codegen",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("xml", xml.module("xml"));

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);
}

pub fn generateBindingModule(b: *std.Build, dbus_file: []const u8, interface_name: []const u8) *std.Build.Module {
    const dependency = b.dependencyFromBuildZig(@This(), .{});
    const generator = dependency.artifact("gdbus-codegen");
    const run_exe = b.addRunArtifact(generator);
    run_exe.addArg(dbus_file);
    const path = b.fmt("bindings/{s}.zig", .{interface_name});
    _ = run_exe.captureStdOut();
    return b.createModule(.{
        .root_source_file = b.path(path),
    });
}
