const std = @import("std");
const translator = @import("translator.zig");

const Interface = translator.Interface;
const Property = translator.Property;
const Access = translator.Access;

pub fn start(allocator: std.mem.Allocator, interface: *Interface, output_dir: []const u8) !void {
    try std.fs.cwd().makePath(output_dir);
    const out_path = try std.mem.concat(allocator, u8, &.{ output_dir, "/", interface.name, ".zig" });
    defer allocator.free(out_path);
    var out_file = try std.fs.cwd().createFile(out_path, .{});
    defer out_file.close();
    const writer = out_file.writer();
    try writeIncludes(writer);
    try writeDBusInfo(writer, interface);
    try writeSkeleton(writer, interface);
    _ = try writer.write("\n");
    try writeProxy(writer, interface);
}

fn writeIncludes(writer: std.fs.File.Writer) !void {
    _ = try writer.write(
        \\const glib = @import("glib");
        \\const gobject = @import("gobject");
        \\const gio = @import("gio");
        \\
    );
}

fn writeDBusInfo(writer: std.fs.File.Writer, interface: *Interface) !void {
    try writer.print(
        \\
        \\pub var dbus_info = gio.DBusInterfaceInfo{{
        \\    .f_ref_count = -1,
        \\    .f_name = @constCast("{s}"),
        \\    .f_methods = @constCast(&[_:null]?*gio.DBusMethodInfo{{
        \\
    , .{interface.service_name});

    // write dbus_info.methods
    for (interface.methods.items) |method| {
        try writer.print(
            \\        @constCast(&gio.DBusMethodInfo{{
            \\            .f_ref_count = -1,
            \\            .f_name = @constCast("{s}"),
            \\            .f_in_args = @constCast(&[_:null]?*gio.DBusArgInfo{{
            \\
        , .{method.name});

        var iter = method.in_args.iterator();
        while (iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const signature = entry.value_ptr.signature;

            try writer.print(
                \\                @constCast(&gio.DBusArgInfo{{
                \\                    .f_ref_count = -1,
                \\                    .f_name = @constCast("{s}"),
                \\                    .f_signature = @constCast("{s}"),
                \\                    .f_annotations = null,
                \\                }}),
                \\
            , .{ name, signature });
        }
        _ = try writer.print(
            \\{s:12}}}),
            \\{s:12}.f_out_args = @constCast(&[_:null]?*gio.DBusArgInfo{{
            \\
        , .{""} ** 2);

        var out_iter = method.out_args.iterator();
        while (out_iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const signature = entry.value_ptr.signature;

            try writer.print(
                \\                @constCast(&gio.DBusArgInfo{{
                \\                    .f_ref_count = -1,
                \\                    .f_name = @constCast("{s}"),
                \\                    .f_signature = @constCast("{s}"),
                \\                    .f_annotations = null,
                \\                }}),
                \\
            , .{ name, signature });
        }

        try writer.print(
            \\            }}),
            \\            .f_annotations = null,
            \\        }}),
            \\
        , .{});
    }

    _ = try writer.write(
        \\    }),
        \\    .f_signals = @constCast(&[_:null]?*gio.DBusSignalInfo{
        \\
    );

    // write dbus_signals
    for (interface.signals.items) |signal| {
        try writer.print(
            \\        @constCast(&gio.DBusSignalInfo{{
            \\            .f_ref_count = -1,
            \\            .f_name = @constCast("{s}"),
            \\            .f_args = @constCast(&[_:null]?*gio.DBusArgInfo{{
        , .{signal.name});

        for (signal.args.items) |arg| {
            try writer.print(
                \\
                \\                @constCast(&gio.DBusArgInfo{{
                \\                    .f_ref_count = -1,
                \\                    .f_name = null,
                \\                    .f_signature = @constCast("{s}"),
                \\                    .f_annotations = null,
                \\                }}),
            , .{arg.signature});
        }

        if (signal.args.items.len == 0) {
            _ = try writer.write("}),\n");
        } else {
            try writer.print("\n{s:12}}}),\n", .{""});
        }
        try writer.print(
            \\            .f_annotations = null,
            \\        }}),
            \\
        , .{});
    }

    _ = try writer.write(
        \\    }),
        \\    .f_properties = @constCast(&[_:null]?*gio.DBusPropertyInfo{
        \\
    );

    // write dbus_properties
    for (interface.properties.items) |property| {
        try writer.print(
            \\        @constCast(&gio.DBusPropertyInfo{{
            \\            .f_ref_count = -1,
            \\            .f_name = @constCast("{s}"),
            \\            .f_signature = @constCast("{s}"),
            \\            .f_flags = .{{
        , .{ property.name, property.signature });

        switch (property.access) {
            Access.readwrite => {
                _ = try writer.write(" .readable = true, .writable = true ");
            },
            Access.read => {
                _ = try writer.write(" .readable = true ");
            },
            Access.write => {
                _ = try writer.write(" .writable = true ");
            },
        }

        _ = try writer.write(
            \\},
            \\            .f_annotations = null,
            \\        }),
            \\
        );
    }

    _ = try writer.write(
        \\    }),
        \\    .f_annotations = null,
        \\};
        \\
        \\pub fn getInfo() *gio.DBusInterfaceInfo {
        \\    return &dbus_info;
        \\}
        \\
        \\
    );
}

fn writeSkeleton(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\pub const Skeleton = extern struct {
        \\    parent_instance: Parent,
        \\
        \\
    );

    try writeMethods(writer, interface);

    _ = try writer.write(
        \\    pub const Parent = gio.DBusInterfaceSkeleton;
        \\    var VTable = gio.DBusInterfaceVTable{
        \\        .f_get_property = &getProperty,
        \\        .f_method_call = &methodCall,
        \\        .f_set_property = null,
        \\        .f_padding = .{@as(*anyopaque, "")} ** 8,
        \\    };
        \\
    );

    try writePrivate(writer, interface);

    _ = try writer.write(
        \\    pub const getGObjectType = gobject.ext.defineClass(Skeleton, .{
        \\        .instanceInit = &init,
        \\        .classInit = &Class.init,
        \\        .private = .{ .Type = Private, .offset = &Private.offset },
        \\    });
        \\
        \\    pub fn new() *Skeleton {
        \\        return gobject.ext.newInstance(Skeleton, .{});
        \\    }
        \\
        \\    pub fn as(interface: *Skeleton, comptime T: type) *T {
        \\        return gobject.ext.as(T, interface);
        \\    }
        \\
        \\    pub fn init(interface: *Skeleton, _: *Class) callconv(.C) void {
        \\        const priv = interface.private();
        \\
        \\        priv.lock.init();
        \\
    );
    for (interface.properties.items) |property| {
        if (std.mem.eql(u8, property.signature, "as")) {
            try writer.print(
                \\        const strv_{s} = glib.StrvBuilder.new();
                \\        priv.{s} = @ptrCast(strv_{s}.unrefToStrv());
                \\
            , .{ property.nick, property.nick, property.nick });
        } else if (!std.mem.eql(u8, property.zig_type, "*glib.Variant")) {
            try writer.print("        priv.{s} = {s};\n", .{ property.nick, try getDefaultValue(property.signature[0]) });
        }
    }
    _ = try writer.write(
        \\    }
        \\
        \\    pub fn get_vtable(_: *Skeleton) callconv(.C) *gio.DBusInterfaceVTable {
        \\        return &VTable;
        \\    }
        \\
        \\    pub fn get_info(_: *Skeleton) callconv(.C) *gio.DBusInterfaceInfo {
        \\        return getInfo();
        \\    }
        \\
        \\    extern fn g_object_unref(p_self: *Skeleton) void;
        \\    pub const unref = g_object_unref;
        \\
        \\    fn emitChanges(self: *Skeleton, changed_fields: []const []const u8) void {
        \\        const connections = self.as(gio.DBusInterfaceSkeleton).getConnections();
        \\        defer connections.freeFull(@ptrCast(&gobject.Object.unref));
        \\        const object_path = self.as(gio.DBusInterfaceSkeleton).getObjectPath() orelse return;
        \\        const builder = glib.VariantBuilder.new(@ptrCast("a{sv}"));
        \\        defer builder.unref();
        \\        const invalid = glib.VariantBuilder.new(@ptrCast("as"));
        \\        defer invalid.unref();
        \\        for (changed_fields) |field| {
        \\            const info = dbus_info.lookupProperty(@ptrCast(field)) orelse continue;
        \\            const priv = self.private();
        \\            const variant: *glib.Variant = blk: {
        \\
    );
    for (interface.properties.items, 0..) |property, idx| {
        try writer.print(
            \\                if (info == dbus_info.f_properties.?[{d}]) {{
            \\
        , .{idx});
        if (std.mem.eql(u8, property.zig_type, "[*:null]?[*:0]const u8")) {
            try writer.print("{s:20}break :blk glib.Variant.newStrv(priv.{s},-1);\n", .{ "", property.nick });
        } else {
            try writer.print("{s:20}break :blk glib.ext.Variant.newFrom(priv.{s});\n", .{ "", property.nick });
        }
        _ = try writer.write(
            \\                }
            \\
        );
    }
    _ = try writer.write(
        \\                unreachable;
        \\            };
        \\            builder.add("{sv}", field.ptr, variant);
        \\        }
        \\        const v_signal_parameters = glib.Variant.new(
        \\            "(sa{sv}as)",
        \\            dbus_info.f_name,
        \\            builder,
        \\            invalid,
        \\        ).refSink();
        \\        defer v_signal_parameters.unref();
        \\        var it: ?*glib.List = connections;
        \\        while (it) |node| : (it = node.f_next) {
        \\            const connection: *gio.DBusConnection = @ptrCast(node.f_data);
        \\            _ = connection.emitSignal(
        \\                null,
        \\                object_path,
        \\                "org.freedesktop.DBus.Properties",
        \\                "PropertiesChanged",
        \\                v_signal_parameters,
        \\                null,
        \\            );
        \\        }
        \\    }
        \\
    );

    try writeMethodCall(writer, interface);
    try writeGetProperty(writer, interface);
    try writeSignals(writer, interface, true);

    _ = try writer.write(
        \\    fn private(self: *Skeleton) *Private {
        \\        return gobject.ext.impl_helpers.getPrivate(self, Private, Private.offset);
        \\    }
        \\
        \\
    );

    // Write accessors
    for (interface.properties.items) |property| {
        try writer.print(
            \\    pub fn set{s}(self: *Skeleton, value: {s}) void {{
            \\        const priv = self.private();
            \\        priv.lock.lock();
            \\        priv.{s} = value;
            \\        priv.lock.unlock();
            \\
            \\        self.emitChanges(&[_][]const u8{{"{s}"}});
            \\    }}
            \\
            \\    pub fn get{s}(self: *Skeleton) {s} {{
            \\        const priv = self.private();
            \\        priv.lock.lock();
            \\        defer priv.lock.unlock();
            \\        return priv.{s};
            \\    }}
            \\
            \\
        , .{ property.function_name, property.zig_type, property.nick, property.nick, property.function_name, property.zig_type, property.nick });
    }

    try writeClass(writer, interface, true);
    _ = try writer.write("};\n");
}

fn getDefaultValue(signature: u8) ![]const u8 {
    switch (signature) {
        'b' => return "false",
        'y', 'n', 'q', 'i', 'h', 'u', 'x', 't' => return "0",
        'd' => return "0.0",
        'o', 'g', 's' => return "\"\"",
        else => return error.SignatureNotMatched,
    }
}

fn printType(isSkeleton: bool) []const u8 {
    if (isSkeleton) return "Skeleton" else return "Proxy";
}

fn writePrivate(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\    const Private = struct {
        \\
    );
    for (interface.properties.items) |property| {
        try writer.print("        {s}: {s},\n", .{
            property.nick,
            property.zig_type,
        });
    }
    _ = try writer.write(
        \\        lock: glib.Mutex,
        \\
        \\        var offset: c_int = 0;
        \\    };
        \\
        \\
    );
}

fn writeMethods(writer: std.fs.File.Writer, interface: *Interface) !void {
    for (interface.methods.items) |method| {
        try writer.print("    {s}: ?*const fn (interface: *Skeleton, invocation: ?*gio.DBusMethodInvocation, ", .{method.name});
        var iter = method.in_args.iterator();
        var idx: u8 = 1;
        while (iter.next()) |arg| {
            try writer.print("{s}: {s}{s}", .{
                arg.key_ptr.*,
                if (getVariantFunctionByType(arg.value_ptr.zig_type, false).len == 0) "*glib.Variant" else arg.value_ptr.zig_type,
                if (idx == method.in_args.count()) "" else ", ",
            });
            idx += 1;
        }
        _ = try writer.write(") void,\n");
    }
    _ = try writer.write("\n");
}

fn writeProperties(writer: std.fs.File.Writer, interface: *Interface, is_skeleton: bool) !void {
    for (interface.properties.items) |property| {
        try writer.print("    {s}: {s}{s},\n", .{
            property.nick,
            if (!is_skeleton and (std.mem.indexOfScalar(u8, "bynqiuxt", property.signature[0]) == null)) "?" else "",
            property.zig_type,
        });
    }
    _ = try writer.write("\n");
}

fn writeMethodCall(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\
        \\    fn methodCall(_: *gio.DBusConnection, _: ?[*:0]const u8, _: [*:0]const u8, _: ?[*:0]const u8, _: [*:0]const u8, p_parameters: *glib.Variant, p_invocation: *gio.DBusMethodInvocation, p_user_data: ?*anyopaque) callconv(.C) void {
        \\        const interface: *Skeleton = @ptrCast(@alignCast(p_user_data));
        \\        const info = p_invocation.getMethodInfo() orelse return;
        \\        var iter = p_parameters.iterNew();
        \\        defer iter.free();
        \\
        \\
    );

    for (interface.methods.items, 0..) |method, idx| {
        try writer.print("        if (info == dbus_info.f_methods.?[{d}] and interface.{s} != null) {{\n", .{ idx, method.name });
        for (method.in_args.values(), 1..) |_, arg_idx| {
            try writer.print(
                \\            const v{d} = iter.nextValue() orelse return;
                \\            defer v{d}.unref();
                \\
            , .{ arg_idx, arg_idx });
        }
        try writer.print("            return interface.{s}.?(interface, p_invocation, ", .{method.name});
        for (method.in_args.values(), 1..) |arg, arg_idx| {
            const is_end = if (arg_idx == method.in_args.count()) "" else ", ";
            try writer.print("v{d}{s}{s}", .{ arg_idx, getVariantFunctionByType(arg.zig_type, false), is_end });
        }
        _ = try writer.write(
            \\);
            \\        }
            \\
        );
    }
    _ = try writer.write(
        \\    }
        \\
    );
}

fn writeGetProperty(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\
        \\    fn getProperty(_: *gio.DBusConnection, _: ?[*:0]const u8, _: [*:0]const u8, _: ?[*:0]const u8, p_property_name: [*:0]const u8, p_error: **glib.Error, p_user_data: ?*anyopaque) callconv(.C) ?*glib.Variant {
        \\        const interface: *Skeleton = @ptrCast(@alignCast(p_user_data));
        \\        const priv = interface.private();
        \\        const info = dbus_info.lookupProperty(p_property_name) orelse {
        \\            glib.setError(p_error, gio.DBusError.quark(), @intFromEnum(gio.DBusError.invalid_args), "No property with name %s", p_property_name);
        \\            return null;
        \\        };
        \\
        \\        priv.lock.lock();
        \\        defer priv.lock.unlock();
        \\
    );

    for (interface.properties.items, 0..) |property, idx| {
        if (idx == 0) {
            _ = try writer.write("       ");
        } else {
            _ = try writer.write(" else");
        }

        try writer.print(" if (info == dbus_info.f_properties.?[{d}]) {{\n", .{idx});
        if (std.mem.eql(u8, property.signature, "as")) {
            try writer.print("{s:12}return glib.Variant.newStrv(priv.{s}, -1);\n", .{ "", property.nick });
        } else {
            try writer.print("{s:12}return glib.Variant.new(info.f_signature.?, priv.{s});\n", .{ "", property.nick });
        }
        try writer.print("{s:8}}}", .{""});
    }
    _ = try writer.write(
        \\
        \\        unreachable;
        \\    }
        \\
        \\
    );
}

fn writeSignals(writer: std.fs.File.Writer, interface: *Interface, isSkeleton: bool) !void {
    _ = try writer.write("    pub const signals = struct {\n");

    for (interface.signals.items) |signal| {
        try writer.print(
            \\        pub const {s} = struct {{
            \\            pub const name = "{s}";
            \\            pub const impl = gobject.ext.defineSignal(name, {s}, &.{{
        , .{ signal.nick, signal.name, printType(isSkeleton) });

        for (signal.args.items, 1..) |arg, idx| {
            const is_end = if (idx == signal.args.items.len) "" else ", ";
            try writer.print("{s}{s}", .{ arg.zig_type, is_end });
        }
        _ = try writer.write(
            \\}, void);
            \\            pub const connect = impl.connect;
            \\        };
            \\
        );
    }

    _ = try writer.write("    };\n\n");
}

fn writeClass(writer: std.fs.File.Writer, interface: *Interface, isSkeleton: bool) !void {
    _ = try writer.print(
        \\    pub const Class = extern struct {{
        \\        parent_class: Parent.Class,
        \\
        \\        var parent: *Parent.Class = undefined;
        \\        pub const Instance = {s};
        \\
        \\        pub fn as(class: *Class, comptime T: type) *T {{
        \\            return gobject.ext.as(T, class);
        \\        }}
        \\
        \\        fn init(class: *Class) callconv(.C) void {{
        \\
    , .{printType(isSkeleton)});

    for (interface.signals.items) |signal| {
        try writer.print("            signals.{s}.impl.register(.{{}});\n", .{signal.nick});
    }

    if (isSkeleton) {
        _ = try writer.write(
            \\
            \\            gio.DBusInterfaceSkeleton.virtual_methods.get_vtable.implement(class, get_vtable);
            \\            gio.DBusInterfaceSkeleton.virtual_methods.get_info.implement(class, get_info);
            \\
        );
    } else {
        try writer.print(
            \\
            \\{s:12}gio.DBusProxy.virtual_methods.g_properties_changed.implement(class, onPropertyChanged);
            \\{s:12}gio.DBusProxy.virtual_methods.g_signal.implement(class, onSignal);
            \\{s:12}gobject.Object.virtual_methods.finalize.implement(class, finalize);
            \\
        , .{""} ** 3);
    }

    _ = try writer.write(
        \\        }
        \\    };
        \\
    );
}

fn getVariantFunctionByType(zig_type: []const u8, duplicate: bool) []const u8 {
    if (std.mem.eql(u8, zig_type, "[*:null]?[*:0]const u8")) {
        return if (duplicate) ".dupStrv(null)" else ".getStrv(null)";
    } else if (std.mem.eql(u8, zig_type, "[*:0]const u8")) {
        return if (duplicate) ".dupString(&size)" else ".getString(null)";
    } else if (std.mem.eql(u8, zig_type, "i32")) {
        return ".getInt32()";
    } else if (std.mem.eql(u8, zig_type, "u32")) {
        return ".getUint32()";
    } else if (std.mem.eql(u8, zig_type, "*glib.Variant")) {
        return if (duplicate) ".ref()" else "";
    } else {
        std.debug.print("Type not found: {s}\n", .{zig_type});
        return "";
    }
}

fn printFreeFunction(writer: std.fs.File.Writer, property: *const Property, spaces: u8) !void {
    if (std.mem.eql(u8, property.zig_type, "*glib.Variant")) {
        try writer.writeByteNTimes(' ', spaces);
        try writer.print("if (proxy.{s}) |prop| prop.unref();\n", .{property.nick});
    } else if (std.mem.eql(u8, property.zig_type, "[*:0]const u8")) {
        try writer.writeByteNTimes(' ', spaces);
        try writer.print("if (proxy.{s}) |prop| glib.free(@ptrCast(@constCast(prop)));\n", .{property.nick});
    } else if (std.mem.eql(u8, property.zig_type, "[*:null]?[*:0]const u8")) {
        try writer.writeByteNTimes(' ', spaces);
        try writer.print("if (proxy.{s}) |prop| glib.strfreev(@ptrCast(@constCast(prop)));\n", .{property.nick});
    }
}

fn writeVirtualMethods(writer: std.fs.File.Writer, interface: *Interface) !void {
    for (interface.methods.items) |method| {
        try writer.print("    pub fn {s}(interface: *Proxy{s}", .{
            method.name,
            if (method.in_args.count() > 0) ", " else "",
        });
        var iter = method.in_args.iterator();
        var idx: u8 = 1;
        var signatures = [_]u8{0} ** 128;
        var sig_idx: usize = 0;
        while (iter.next()) |arg| {
            try writer.print("{s}: {s}{s}", .{
                arg.key_ptr.*,
                if (getVariantFunctionByType(arg.value_ptr.zig_type, false).len == 0) "*glib.Variant" else arg.value_ptr.zig_type,
                if (idx == method.in_args.count()) "" else ", ",
            });
            if (std.mem.eql(u8, arg.value_ptr.signature, "as")) {
                signatures[sig_idx] = '^';
                sig_idx += 1;
            }
            std.mem.copyForwards(u8, signatures[sig_idx..], arg.value_ptr.signature);
            sig_idx += arg.value_ptr.signature.len;
            idx += 1;
        }
        _ = try writer.write(") ?*glib.Variant {\n");
        try writer.print("{s:8}return interface.as(gio.DBusProxy).callSync(\"{s}\", {s}", .{
            "",
            method.name,
            if (method.in_args.count() > 0) "glib.Variant.new(\"(" else "null",
        });

        if (method.in_args.count() > 0) {
            try writer.print("{s})\", ", .{signatures[0..sig_idx]});

            iter.index = 0;
            idx = 1;
            while (iter.next()) |arg| {
                try writer.print("{s}{s}", .{
                    arg.key_ptr.*,
                    if (idx == method.in_args.count()) ")" else ", ",
                });
                idx += 1;
            }
        }
        _ = try writer.write(", .{}, -1, null, null);\n");
        _ = try writer.write("    }\n\n");
    }
}

fn writeDBusSignals(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write("    fn finalize(proxy: *Proxy) callconv(.C) void {\n");
    for (interface.properties.items) |property| {
        try printFreeFunction(writer, &property, 8);
    }
    _ = try writer.write(
        \\        gobject.Object.virtual_methods.finalize.call(Class.parent, proxy.as(Parent));
        \\    }
        \\
    );

    try writer.print(
        \\
        \\{s:4}fn onPropertyChanged(proxy: *Proxy, p_changed_properties: *glib.Variant, _: *const [*:0]const u8) callconv(.C) void {{
        \\{s:8}updateProperties(proxy, p_changed_properties);
        \\{s:4}}}
        \\
    , .{""} ** 3);

    try writer.print(
        \\
        \\    fn onSignal(proxy: *Proxy, _: [*:0]const u8, p_signal_name: [*:0]const u8, v_parameters: *glib.Variant) callconv(.C) void {{
        \\{s:8}const o_result = proxy.as(gio.DBusProxy).callSync(
        \\{s:12}"org.freedesktop.DBus.Properties.GetAll",
        \\{s:12}glib.ext.Variant.newFrom(.{{getInfo().f_name.?}}),
        \\{s:12}.{{}},
        \\{s:12}-1,
        \\{s:12}null,
        \\{s:12}null,
        \\{s:8});
        \\
        \\{s:8}if (o_result) |result| {{
        \\{s:12}defer result.unref();
        \\{s:12}const v_properties = result.getChildValue(0);
        \\{s:12}defer v_properties.unref();
        \\{s:12}updateProperties(proxy, v_properties);
        \\{s:8}}}
        \\
        \\{s:8}var params: [64]*glib.Variant = undefined;
        \\{s:8}const iter = v_parameters.iterNew();
        \\{s:8}defer iter.free();
        \\{s:8}const max = v_parameters.nChildren();
        \\{s:8}for (0..max) |idx| {{
        \\{s:12}params[idx] = iter.nextValue() orelse break;
        \\{s:8}}}
        \\
        \\{s:8}const info = getInfo().lookupSignal(p_signal_name);
    , .{""} ** 22);

    for (interface.signals.items, 0..) |signal, idx| {
        if (idx == 0) {
            try writer.print("\n{s:7}", .{""});
        } else {
            _ = try writer.write(" else");
        }

        try writer.print(" if (info == dbus_info.f_signals.?[{d}]) {{\n", .{idx});
        try writer.print("{s:12}signals.{s}.impl.emit(proxy, null, .{{", .{ "", signal.nick });

        for (signal.args.items, 0..) |arg, arg_idx| {
            try writer.print("params[{d}]{s}{s}", .{
                arg_idx,
                getVariantFunctionByType(arg.zig_type, false),
                if (arg_idx == signal.args.items.len - 1) "" else ", ",
            });
        }

        try writer.print("}}, null);\n", .{});

        try writer.print("{s:8}}}", .{""});
    }

    try writer.print(
        \\
        \\
        \\{s:8}for (0..max) |idx| {{
        \\{s:12}params[idx].unref();
        \\{s:8}}}
    , .{""} ** 3);
    try writer.print("\n    }}\n", .{});
}

fn writeUpdateProperties(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\
        \\    fn updateProperties(proxy: *Proxy, v_properties: *glib.Variant) void {
        \\        const iter = v_properties.iterNew();
        \\        defer iter.free();
        \\
        \\        var key: [*:0]const u8 = undefined;
        \\        var variant: *glib.Variant = undefined;
        \\        while (iter.next("{&sv}", &key, &variant) != 0) {
        \\            defer variant.unref();
        \\            const info = getInfo().lookupProperty(key) orelse continue;
        \\
    );

    var printSize = false;
    for (interface.properties.items) |property| {
        if (std.mem.eql(u8, property.zig_type, "[*:0]const u8")) {
            printSize = true;
            break;
        }
    }
    if (printSize) try writer.print("\n{s:12}var size = variant.getSize();", .{""});

    for (interface.properties.items, 0..) |property, idx| {
        if (idx == 0) {
            try writer.print("\n{s:11}", .{""});
        } else {
            _ = try writer.write(" else");
        }

        try writer.print(" if (info == dbus_info.f_properties.?[{d}]) {{\n", .{idx});
        if (property.signature.len == 1 and property.signature[0] == 'b') {
            try writer.print("{s:16}proxy.{s} = (variant.getBoolean() == 1);\n", .{ "", property.nick });
        } else {
            try printFreeFunction(writer, &property, 16);
            if (std.mem.eql(u8, property.zig_type, "[*:null]?[*:0]const u8")) {
                try writer.print("{s:16}proxy.{s} = @ptrCast(variant{s});\n", .{ "", property.nick, getVariantFunctionByType(property.zig_type, true) });
            } else {
                try writer.print("{s:16}proxy.{s} = variant{s};\n", .{ "", property.nick, getVariantFunctionByType(property.zig_type, true) });
            }
        }
        try writer.print("{s:12}}}", .{""});
    }

    try writer.print("\n{s:8}}}\n", .{""});
    try writer.print("{s:4}}}\n", .{""});
}

fn writeProxy(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\pub const Proxy = extern struct {
        \\    parent_instance: Parent,
        \\
        \\
    );

    try writeProperties(writer, interface, false);

    _ = try writer.write(
        \\    pub const Parent = gio.DBusProxy;
        \\
        \\    pub const getGObjectType = gobject.ext.defineClass(Proxy, .{
    );
    try writer.print("\n{s:8}.name = \"{s}Proxy\",\n", .{ "", interface.name });
    _ = try writer.write(
        \\        .classInit = &Class.init,
        \\        .parent_class = &Class.parent,
        \\    });
        \\
        \\    pub fn as(interface: *Proxy, comptime T: type) *T {
        \\        return gobject.ext.as(T, interface);
        \\    }
        \\
        \\    pub fn new(p_connection: *gio.DBusConnection, flags: gio.DBusProxyFlags, p_name: ?[*:0]const u8, p_object_path: [*:0]const u8, p_cancellable: ?*gio.Cancellable, p_callback: ?gio.AsyncReadyCallback, p_user_data: ?*anyopaque) void {
        \\        gio.AsyncInitable.newAsync(Proxy.getGObjectType(), glib.PRIORITY_DEFAULT, p_cancellable, p_callback, p_user_data, "g-flags", @as(c_uint, @bitCast(flags)), "g-name", p_name, "g-connection", p_connection, "g-object-path", p_object_path, "g-interface-name", getInfo().f_name, @as(?[*:0]const u8, null));
        \\    }
        \\
        \\    pub fn newSync(p_connection: *gio.DBusConnection, flags: gio.DBusProxyFlags, p_name: ?[*:0]const u8, p_object_path: [*:0]const u8, p_cancellable: ?*gio.Cancellable, p_error: ?**glib.Error) ?*Proxy {
        \\        return @ptrCast(@alignCast(gio.Initable.new(Proxy.getGObjectType(), p_cancellable, p_error, "g-flags", @as(c_uint, @bitCast(flags)), "g-name", p_name, "g-connection", p_connection, "g-object-path", p_object_path, "g-interface-name", getInfo().f_name.?, @as(?[*:0]const u8, null))));
        \\    }
        \\
        \\    pub fn finish(p_res: *gio.AsyncResult, p_error: ?*?*glib.Error) ?*Proxy {
        \\        const object = gio.AsyncResult.getSourceObject(p_res).?;
        \\        const o_ret = gio.AsyncInitable.newFinish(@ptrCast(@alignCast(object)), p_res, p_error);
        \\        object.unref();
        \\        if (o_ret) |ret| return @ptrCast(@alignCast(ret));
        \\        return null;
        \\    }
        \\
        \\    extern fn g_object_unref(p_self: *Proxy) void;
        \\    pub const unref = g_object_unref;
        \\
        \\
    );

    try writeVirtualMethods(writer, interface);
    try writeSignals(writer, interface, false);
    try writeClass(writer, interface, false);
    try writeDBusSignals(writer, interface);
    try writeUpdateProperties(writer, interface);

    _ = try writer.write("};\n");
}
