const std = @import("std");
const xml = @import("xml");

const translator = @import("translator.zig");
const generator = @import("generator.zig");

pub fn main() !void {
    std.debug.print("gdbus-codegen init.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer std.debug.assert(gpa.deinit() == .ok);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.InvalidArguments;
    }

    const output_dir = "bindings";

    var output_files = std.ArrayList([]const u8).init(allocator);
    defer output_files.deinit();

    for (args[1..]) |arg| {
        std.debug.print("arg: {s}\n", .{arg});

        const node = try xml.loadFromPath(allocator, arg);
        defer node.destroy(allocator);
        const interface = try translator.newFromNode(allocator, node);
        defer interface.deinit();
        try generator.start(allocator, interface, output_dir);
        try output_files.append(try allocator.dupe(u8, interface.name));
    }

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
