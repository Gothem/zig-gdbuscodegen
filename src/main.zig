const std = @import("std");
const xml = @import("xml");

const translator = @import("translator.zig");
const generator = @import("generator.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = init.minimal.args.iterate();

    if (args.inner.remaining.len < 2) {
        return error.InvalidArguments;
    }

    var o_output_dir: ?[]const u8 = null;

    var output_files: std.ArrayList([]const u8) = .empty;
    defer output_files.deinit(allocator);

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o")) {
            o_output_dir = args.next() orelse return error.MissingArg;
        } else {
            const output_dir = o_output_dir orelse "bindings";
            const node = try xml.loadFromPath(allocator, init.io, arg);
            defer node.destroy(allocator);
            const interface = try translator.newFromNode(allocator, node);
            defer interface.deinit();
            try generator.start(allocator, init.io, interface, output_dir);
            try output_files.append(allocator, try allocator.dupe(u8, interface.name));
        }
    }

    const output_dir = o_output_dir orelse "bindings";
    const out_path = try std.mem.concat(allocator, u8, &.{ output_dir, "/root.zig" });
    defer allocator.free(out_path);
    var out_file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{});
    defer out_file.close(init.io);
    var buffer: [4096]u8 = undefined;
    var file_writer = out_file.writer(init.io, &buffer);
    const writer = &file_writer.interface;
    for (output_files.items) |file| {
        try writer.print("pub const {s} = @import(\"{s}.zig\");\n", .{ file, file });
        defer allocator.free(file);
    }
    try writer.flush();
}
