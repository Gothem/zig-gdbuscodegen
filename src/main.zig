const std = @import("std");
const xml = @import("xml");

const translator = @import("translator.zig");
const generator = @import("generator.zig");

pub fn main() !void {
    std.debug.print("gdbus-codegen init.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    var args = try std.process.ArgIterator.initWithAllocator(allocator);
    defer args.deinit();

    if (args.inner.count < 2) {
        return error.InvalidArguments;
    }

    var o_output_dir: ?[]const u8 = null;

    var output_files = std.ArrayList([]const u8).init(allocator);
    defer output_files.deinit();

    _ = args.skip();
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-o")) {
            o_output_dir = args.next() orelse return error.MissingArg;
        } else {
            const output_dir = o_output_dir orelse "bindings";
            const node = try xml.loadFromPath(allocator, arg);
            defer node.destroy(allocator);
            const interface = try translator.newFromNode(allocator, node);
            defer interface.deinit();
            try generator.start(allocator, interface, output_dir);
            try output_files.append(try allocator.dupe(u8, interface.name));
        }
    }

    const output_dir = o_output_dir orelse "bindings";
    const out_path = try std.mem.concat(allocator, u8, &.{ output_dir, "/root.zig" });
    defer allocator.free(out_path);
    var out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    const writer = out_file.writer();
    for (output_files.items) |file| {
        try writer.print("pub const {s} = @import(\"{s}.zig\");\n", .{ file, file });
        defer allocator.free(file);
    }
}
