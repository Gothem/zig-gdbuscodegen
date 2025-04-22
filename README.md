# zig-gdbuscodegen

Zig bindings and protocol scanner for GDBus.

This repository provides Zig bindings for GDBus based on [Zig-GObject](https://github.com/ianprime0509/zig-gobject), along with a protocol scanner to facilitate communication with DBus services.

## Features

- Zig bindings for GDBus
- Protocol scanner for DBus communication
- Written in pure Zig (compatible with Zig 0.14+)

## Requirements

- Zig 0.14+ 
- [Zig-GObject](https://github.com/ianprime0509/zig-gobject)
- DBus interface definitions (e.g., `protocols/org.example.Test.xml`)

## Installation

To use `zig-gdbuscodegen`, include it in your Zig project as follows:

1. Generate the GObject bindings for your project with [Zig-GObject](https://github.com/ianprime0509/zig-gobject)
    
2. Run the following command in your zig project folder:
    ```sh
    zig fetch --save https://github.com/Gothem/zig-gdbuscodegen/archive/refs/tags/0.1.3.tar.gz
    ```
3. Add the DBus interface definitions to your project folder. (in the following example we assume you added it to 'protocols' folder)

4. In your `build.zig` file, include the following:
    ```zig
    const Scanner = @import("gdbuscodegen").Scanner;

    pub fn build(b: *std.build.Builder) void {
        // .........
    
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
    
        const exe = b.addExecutable(.{
          .name = "example-client",
          .root_source_file = b.path("client.zig"),
          .target = target,
          .optimize = optimize,
        });
        exe.root_module.addImport("glib", glib);
        exe.root_module.addImport("gobject", gobject);
        exe.root_module.addImport("gio", gio);
        exe.root_module.addImport("gdbus", gdbus);

        // .........
    }
    ```

## Usage

In the example folder you can find a Zig project that creates a server and client executables that shows how it works.
