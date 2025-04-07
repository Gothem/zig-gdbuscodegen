const std = @import("std");
const xml = @import("xml");

const translator = @import("translator.zig");
const generator = @import("generator.zig");

pub fn main() !void {
    std.debug.print("gdbus-codegen init.\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        return error.InvalidArguments;
    }

    for (args[1..]) |arg| {
        std.debug.print("arg: {s}\n", .{arg});

        const node = try xml.loadFromPath(allocator, arg);
        defer node.destroy(allocator);
        const interface = try translator.newFromNode(allocator, node);
        defer allocator.destroy(interface);
        try generator.start(allocator, interface);
    }
}
