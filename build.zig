const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const xml = b.dependency("xml", .{
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

const build_file = @This();

pub const Scanner = struct {
    build: *std.Build,
    run: *std.Build.Step.Run,
    result: std.Build.LazyPath,

    const Dependencies = struct {
        glib: *std.Build.Module,
        gobject: *std.Build.Module,
        gio: *std.Build.Module,
    };

    pub fn init(b: *std.Build) *Scanner {
        const self = b.dependencyFromBuildZig(build_file, .{});
        const exe = self.artifact("gdbus-codegen");
        const run = self.builder.addRunArtifact(exe);

        run.addArg("-o");
        const result = run.addOutputDirectoryArg("gdbus");

        const scanner = b.allocator.create(Scanner) catch @panic("Out of memory");
        scanner.* = .{
            .build = b,
            .run = run,
            .result = result,
        };
        return scanner;
    }

    pub fn createModule(scanner: *@This(), dependencies: Dependencies) *std.Build.Module {
        return scanner.build.createModule(.{
            .root_source_file = scanner.result.path(scanner.build, "root.zig"),
            .imports = &.{
                .{ .name = "glib", .module = dependencies.glib },
                .{ .name = "gobject", .module = dependencies.gobject },
                .{ .name = "gio", .module = dependencies.gio },
            },
        });
    }

    pub fn addProtocol(scanner: *@This(), sub_path: []const u8) void {
        const path = scanner.build.path(sub_path);
        scanner.run.addFileArg(path);
    }
};
