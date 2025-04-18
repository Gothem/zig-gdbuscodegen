const std = @import("std");
const xml = @import("xml");

pub const Interface = struct {
    arena: *std.heap.ArenaAllocator,
    name: []const u8,
    service_name: []const u8,
    methods: std.ArrayList(Method),
    properties: std.ArrayList(Property),
    signals: std.ArrayList(Signal),

    pub fn deinit(self: *@This()) void {
        const allocator = self.arena.child_allocator;
        self.arena.deinit();
        allocator.destroy(self.arena);
    }
};
const Arg = struct {
    signature: []const u8,
    zig_type: []const u8,
};
const Method = struct {
    name: []const u8,
    in_args: std.StringArrayHashMap(Arg),
    out_args: std.StringArrayHashMap(Arg),
    //annotations: anyopaque, TODO
};
pub const Access = enum { read, write, readwrite };
pub const Property = struct {
    name: []const u8,
    nick: []const u8,
    signature: []const u8,
    zig_type: []const u8,
    function_name: []const u8,
    access: Access,
    //annotations: anyopaque, TODO
};
const Signal = struct {
    name: []const u8,
    nick: []const u8,
    args: std.ArrayList(Arg),
    //annotations: anyopaque, TODO
};

pub fn newFromNode(gpa: std.mem.Allocator, node: *xml.Node) !*Interface {
    if (std.mem.eql(u8, node.name, "node")) {
        for (node.childrens.items) |child| {
            return try newFromNode(gpa, child);
        }
    }
    if (!std.mem.eql(u8, node.name, "interface")) return error.NoInterfaceDetected;

    const arena = try gpa.create(std.heap.ArenaAllocator);
    errdefer gpa.destroy(arena);
    arena.* = std.heap.ArenaAllocator.init(gpa);
    errdefer arena.deinit();
    const allocator = arena.allocator();

    const interface = try allocator.create(Interface);
    interface.* = .{
        .service_name = (node.attributes.getEntry("name") orelse return error.NoInterfaceName).value_ptr.*,
        .name = interface.service_name[std.mem.lastIndexOfScalar(u8, interface.service_name, '.').? + 1 ..],
        .methods = std.ArrayList(Method).init(allocator),
        .properties = std.ArrayList(Property).init(allocator),
        .signals = std.ArrayList(Signal).init(allocator),
        .arena = arena,
    };
    const redundant_words = try getRedundantWords(allocator, interface.name);
    defer redundant_words.deinit();

    for (node.childrens.items) |child| {
        const child_name = child.attributes.getEntry("name").?.value_ptr.*;
        if (std.mem.eql(u8, child.name, "method")) {
            var in_args = std.StringArrayHashMap(Arg).init(allocator);
            var out_args = std.StringArrayHashMap(Arg).init(allocator);
            std.debug.print("{s}(", .{child_name});
            for (child.childrens.items) |arg| {
                const name = arg.attributes.getEntry("name").?.value_ptr.*;
                const signature = arg.attributes.getEntry("type").?.value_ptr.*;
                const zig_type = signatureToZigType(signature);
                const direction_attr = arg.attributes.getEntry("direction");
                const direction = if (direction_attr) |dir| dir.value_ptr.* else "in"; // for methods default to in

                if (std.mem.eql(u8, "in", direction)) {
                    std.debug.print("{s}: {s}, ", .{ name, zig_type });
                    try in_args.put(name, .{
                        .signature = signature,
                        .zig_type = zig_type,
                    });
                }
                if (std.mem.eql(u8, "out", direction)) {
                    try out_args.put(name, .{
                        .signature = signature,
                        .zig_type = zig_type,
                    });
                }
            }
            std.debug.print(")\n", .{});

            try interface.methods.append(.{
                .name = child_name,
                .in_args = in_args,
                .out_args = out_args,
            });
        }
        if (std.mem.eql(u8, child.name, "signal")) {
            const nick = try removeRedundantWords(allocator, child_name, redundant_words.items, true);
            var args = std.ArrayList(Arg).init(allocator);
            for (child.childrens.items) |arg| {
                const signature = arg.attributes.getEntry("type").?.value_ptr.*;
                const zig_type = signatureToZigType(signature);

                try args.append(.{
                    .signature = signature,
                    .zig_type = zig_type,
                });
            }

            try interface.signals.append(.{
                .name = child_name,
                .nick = nick,
                .args = args,
            });
        }
        if (std.mem.eql(u8, child.name, "property")) {
            var repeated = false;
            var nick = try removeRedundantWords(allocator, child_name, redundant_words.items, true);
            // Check if already exists
            for (interface.properties.items) |property| {
                if (std.mem.eql(u8, nick, property.nick)) {
                    nick = try removeRedundantWords(allocator, child_name, &.{}, true);
                    repeated = true;
                }
            }

            const signature = child.attributes.getEntry("type").?.value_ptr.*;
            const zig_type = signatureToZigType(signature);
            const function_name = try removeRedundantWords(allocator, child_name, if (repeated) &.{} else redundant_words.items, false);
            const access_str = child.attributes.getEntry("access").?.value_ptr.*;
            var access: Access = undefined;

            if (std.mem.eql(u8, access_str, "read")) {
                access = Access.read;
            } else if (std.mem.eql(u8, access_str, "write")) {
                access = Access.write;
            } else {
                access = Access.readwrite;
            }

            try interface.properties.append(.{
                .name = child_name,
                .nick = nick,
                .signature = signature,
                .zig_type = zig_type,
                .function_name = function_name,
                .access = access,
            });
        }
        if (std.mem.eql(u8, child.name, "annotation")) {
            std.debug.print("Create annotation code\n", .{});
        }
    }

    return interface;
}

fn signatureToZigType(signature: []const u8) []const u8 {
    if (std.mem.eql(u8, signature, "as")) return "[*:null]?[*:0]const u8";
    if (signature.len > 1) return "*glib.Variant";

    switch (signature[0]) {
        'b' => return "bool",
        'y' => return "u8",
        'n' => return "i16",
        'q' => return "u16",
        'i', 'h' => return "i32",
        'u' => return "u32",
        'x' => return "i64",
        't' => return "u64",
        'd' => return "f64",
        'o', 'g', 's' => return "[*:0]const u8",
        else => return "*glib.Variant",
    }
}

fn getRedundantWords(allocator: std.mem.Allocator, values: []const u8) !std.ArrayList([]const u8) {
    var words = std.ArrayList([]const u8).init(allocator);
    try words.append("Is");

    const lowered_values = try std.ascii.allocLowerString(allocator, values);
    defer allocator.free(lowered_values);

    var start: usize = 0;
    var end: usize = values.len;
    while (start < values.len) {
        const diff = std.mem.indexOfDiff(u8, values[start + 1 ..], lowered_values[start + 1 ..]);
        end = if (diff) |idx| idx + start + 1 else values.len;
        try words.append(values[start..end]);
        start = end;
    }

    return words;
}

fn removeRedundantWords(allocator: std.mem.Allocator, input: []const u8, words: [][]const u8, snake_case: bool) ![]const u8 {
    var input_idx: usize = 0;
    var output_idx: usize = 0;
    var end: usize = input.len;
    var block_remove: bool = false; // Fix for StatusNotifierItem.NewStatus

    // Find output size
    outer: while (output_idx < end) {
        for (words) |word| {
            if (std.mem.startsWith(u8, input[input_idx..], word)) {
                input_idx += word.len;
                end -= word.len;
                continue :outer;
            }
        }

        if (snake_case and std.ascii.isUpper(input[input_idx]) and output_idx > 0) {
            end += 1;
            output_idx += 1;
        }
        output_idx += 1;
        input_idx += 1;
    }

    if (end == 0) return if (snake_case) std.ascii.allocLowerString(allocator, input) else input;
    if (output_idx < input_idx and std.mem.eql(u8, input[0..output_idx], "New")) {
        block_remove = true;
        end = input_idx + 1;
    }

    // Proceed to remove redundant words
    var output: []u8 = try allocator.alloc(u8, end);
    input_idx = 0;
    output_idx = 0;
    outer: while (output_idx < end) {
        if (!block_remove) {
            for (words) |word| {
                if (std.mem.startsWith(u8, input[input_idx..], word)) {
                    input_idx += word.len;
                    continue :outer;
                }
            }
        }
        if (snake_case and std.ascii.isUpper(input[input_idx]) and output_idx > 0) {
            output[output_idx] = '_';
            output_idx += 1;
        }
        output[output_idx] = if (snake_case) std.ascii.toLower(input[input_idx]) else input[input_idx];
        output_idx += 1;
        input_idx += 1;
    }
    return output;
}
