const std = @import("std");

const Scanner = @import("gdbus").Scanner;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.init(b);
    scanner.addProtocol("protocols/org.example.Test.xml");

    const gbindings = b.dependency("gobject", .{});
    const glib = gbindings.module("glib2");
    const gobject = gbindings.module("gobject2");
    const gio = gbindings.module("gio2");
    const gdbus = scanner.createModule(.{
        .glib = glib,
        .gobject = gobject,
        .gio = gio,
    });
    const server_exe = b.addExecutable(.{
        .name = "example-server",
        .root_source_file = b.path("server.zig"),
        .target = target,
        .optimize = optimize,
    });

    server_exe.root_module.addImport("glib", glib);
    server_exe.root_module.addImport("gobject", gobject);
    server_exe.root_module.addImport("gio", gio);
    server_exe.root_module.addImport("gdbus", gdbus);

    const client_exe = b.addExecutable(.{
        .name = "example-client",
        .root_source_file = b.path("client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client_exe.root_module.addImport("glib", glib);
    client_exe.root_module.addImport("gobject", gobject);
    client_exe.root_module.addImport("gio", gio);
    client_exe.root_module.addImport("gdbus", gdbus);

    b.installArtifact(server_exe);
    b.installArtifact(client_exe);

    const run_server = b.addRunArtifact(server_exe);
    run_server.step.dependOn(b.getInstallStep());
    const run_server_step = b.step("run_server", "Run the server app");
    run_server_step.dependOn(&run_server.step);
    const run_client = b.addRunArtifact(client_exe);
    run_client.step.dependOn(b.getInstallStep());
    const run_client_step = b.step("run_client", "Run the client app");
    run_client_step.dependOn(&run_client.step);
}
