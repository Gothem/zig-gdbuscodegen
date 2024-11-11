const std = @import("std");
const translator = @import("translator.zig");

const Interface = translator.Interface;
const Access = translator.Access;

pub fn start(allocator: std.mem.Allocator, interface: *Interface) !void {
    try std.fs.cwd().makePath("bindings");
    const out_path = try std.mem.concat(allocator, u8, &.{ "bindings/", interface.name, ".zig" });
    var out_file = try std.fs.cwd().createFile(out_path, .{});
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
            \\        @constCast(&.{{
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
                \\                @constCast(&.{{
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
            \\            .f_out_args = null,
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
            \\        @constCast(&.{{
            \\            .f_ref_count = -1,
            \\            .f_name = @constCast("{s}"),
            \\            .f_args = @constCast(&[_:null]?*gio.DBusArgInfo{{
        , .{signal.name});

        for (signal.args.items) |arg| {
            try writer.print(
                \\
                \\                @constCast(&.{{
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
            \\        @constCast(&.{{
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
    try writeProperties(writer, interface, true);

    _ = try writer.write(
        \\    pub const Parent = gio.DBusInterfaceSkeleton;
        \\
        \\    pub const getGObjectType = gobject.ext.defineClass(Skeleton, .{
        \\        .classInit = &Class.init,
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
        \\    pub fn get_vtable(_: *Skeleton) callconv(.C) *gio.DBusInterfaceVTable {
        \\        var zero: u8 = 0;
        \\        return @constCast(&.{
        \\            .method_call = &methodCall,
        \\            .get_property = &getProperty,
        \\            .set_property = null,
        \\            .padding = [_]*anyopaque{@ptrCast(&zero)} ** 8,
        \\        });
        \\    }
        \\
        \\    pub fn get_info(_: *Skeleton) callconv(.C) *gio.DBusInterfaceInfo {
        \\        return getInfo();
        \\    }
        \\
    );

    try writeMethodCall(writer, interface);
    try writeGetProperty(writer, interface);
    try writeSignals(writer, interface, true);
    try writeClass(writer, interface, true);
    _ = try writer.write("};\n");
}

fn printType(isSkeleton: bool) []const u8 {
    if (isSkeleton) return "Skeleton" else return "Proxy";
}

fn writeMethods(writer: std.fs.File.Writer, interface: *Interface) !void {
    for (interface.methods.items) |method| {
        try writer.print("    {s}: ?*const fn (interface: *Skeleton, invocation: *gio.DBusMethodInvocation, ", .{method.name});
        var iter = method.in_args.iterator();
        var idx: u8 = 1;
        while (iter.next()) |arg| {
            try writer.print("{s}: {s}{s}", .{
                arg.key_ptr.*,
                if (getVariantFunctionByType(arg.value_ptr.zig_type).len == 0) "*glib.Variant" else arg.value_ptr.zig_type,
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
            if (!is_skeleton and (std.mem.indexOfScalar(u8, "b", property.signature[0]) == null)) "?" else "",
            property.zig_type,
        });
    }
    _ = try writer.write("\n");
}

fn writeMethodCall(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\
        \\    fn methodCall(p_connection: *gio.DBusConnection, p_sender: [*:0]const u8, p_object_path: [*:0]const u8, p_interface_name: [*:0]const u8, p_method_name: [*:0]const u8, p_parameters: *glib.Variant, p_invocation: *gio.DBusMethodInvocation, p_user_data: ?*anyopaque) callconv(.C) void {
        \\        _ = p_connection;
        \\        _ = p_method_name;
        \\        _ = p_interface_name;
        \\        _ = p_object_path;
        \\        _ = p_sender;
        \\
        \\        const interface: *Skeleton = @ptrCast(@alignCast(p_user_data));
        \\        const info = p_invocation.getMethodInfo() orelse return;
        \\        var iter = p_parameters.iterNew();
        \\
        \\
    );

    for (interface.methods.items, 0..) |method, idx| {
        try writer.print("        if (info == dbus_info.methods.?[{d}] and interface.{s} != null) return interface.{s}.?(interface, p_invocation, ", .{ idx, method.name, method.name });
        var arg_idx: u8 = 1;
        for (method.in_args.values()) |arg| {
            const is_end = if (arg_idx == method.in_args.count()) "" else ", ";
            try writer.print("iter.nextValue().?{s}{s}", .{ getVariantFunctionByType(arg.zig_type), is_end });
            arg_idx += 1;
        }
        _ = try writer.write(");\n");
    }
    _ = try writer.write("    }\n");
}

fn writeGetProperty(writer: std.fs.File.Writer, interface: *Interface) !void {
    _ = try writer.write(
        \\
        \\    fn getProperty(p_connection: *gio.DBusConnection, p_sender: [*:0]const u8, p_object_path: [*:0]const u8, p_interface_name: [*:0]const u8, p_property_name: [*:0]const u8, p_error: **glib.Error, p_user_data: ?*anyopaque) callconv(.C) ?*glib.Variant {
        \\        _ = p_connection;
        \\        _ = p_sender;
        \\        _ = p_object_path;
        \\        _ = p_interface_name;
        \\
        \\        const interface: *Skeleton = @ptrCast(@alignCast(p_user_data));
        \\        const info = dbus_info.lookupProperty(p_property_name) orelse {
        \\            glib.setError(p_error, gio.DBusError.quark(), @intFromEnum(gio.DBusError.invalid_args), "No property with name %s", p_property_name);
        \\            return null;
        \\        };
        \\
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
            try writer.print("{s:12}return glib.Variant.newStrv(interface.{s}, -1);\n", .{ "", property.nick });
        } else {
            try writer.print("{s:12}return glib.Variant.new(info.signature.?, interface.{s});\n", .{ "", property.nick });
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
        \\        pub const Instance = {s};
        \\        parent_class: Parent.Class,
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
            \\
        , .{ "", "" });
    }

    _ = try writer.write(
        \\        }
        \\    };
        \\
    );
}

fn getVariantFunctionByType(zig_type: []const u8) []const u8 {
    if (std.mem.eql(u8, zig_type, "[*:null]const ?[*:0]const u8")) {
        return ".getStrv(null)";
    } else if (std.mem.eql(u8, zig_type, "[*:0]const u8")) {
        return ".getString(null)";
    } else if (std.mem.eql(u8, zig_type, "i32")) {
        return ".getInt32()";
    } else if (std.mem.eql(u8, zig_type, "u32")) {
        return ".getUint32()";
    } else {
        std.debug.print("Type not found: {s}\n", .{zig_type});
        return "";
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
                if (getVariantFunctionByType(arg.value_ptr.zig_type).len == 0) "*glib.Variant" else arg.value_ptr.zig_type,
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
    try writer.print(
        \\
        \\{s:4}fn onPropertyChanged(proxy: *Proxy, p_changed_properties: *glib.Variant, _: *const [*:0]const u8) callconv(.C) void {{
        \\{s:8}updateProperties(proxy, p_changed_properties);
        \\{s:4}}}
        \\
    , .{ "", "", "" });

    try writer.print(
        \\
        \\    fn onSignal(proxy: *Proxy, _: [*:0]const u8, p_signal_name: [*:0]const u8, v_parameters: *glib.Variant) callconv(.C) void {{
        \\{s:8}const result = proxy.as(gio.DBusProxy).callSync(
        \\{s:12}"org.freedesktop.DBus.Properties.GetAll",
        \\{s:12}glib.ext.Variant.newFrom(.{{getInfo().f_name.?}}),
        \\{s:12}.{{}},
        \\{s:12}-1,
        \\{s:12}null,
        \\{s:12}null,
        \\{s:8}).?;
        \\{s:8}defer result.unref();
        \\{s:8}const v_properties = result.getChildValue(0);
        \\{s:8}defer v_properties.unref();
        \\{s:8}updateProperties(proxy, v_properties);
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
    , .{""} ** 20);

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
                getVariantFunctionByType(arg.zig_type),
                if (arg_idx == signal.args.items.len - 1) "" else ", ",
            });
        }

        try writer.print("}},null);\n", .{});

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
        \\            const info = getInfo().lookupProperty(key);
        \\            if (info == null) continue;
        \\
    );

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
            try writer.print("{s:16}proxy.{s} = variant{s};\n", .{ "", property.nick, getVariantFunctionByType(property.zig_type) });
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
        \\    });
        \\
        \\    pub fn as(interface: *Proxy, comptime T: type) *T {
        \\        return gobject.ext.as(T, interface);
        \\    }
        \\
        \\    pub fn new(p_connection: *gio.DBusConnection, flags: gio.DBusProxyFlags, p_name: ?[*:0]const u8, p_object_path: [*:0]const u8, p_cancellable: ?*gio.Cancellable, p_callback: ?gio.AsyncReadyCallback, p_user_data: ?*anyopaque) void {
        \\        gio.AsyncInitable.newAsync(Proxy.getGObjectType(), glib.PRIORITY_DEFAULT, p_cancellable, p_callback, p_user_data, "g-flags", @as(c_uint, @bitCast(flags)), "g-name", p_name, "g-connection", p_connection, "g-object-path", p_object_path, "g-interface-name", getInfo().f_name);
        \\    }
        \\
        \\    pub fn newSync(p_connection: *gio.DBusConnection, flags: gio.DBusProxyFlags, p_name: ?[*:0]const u8, p_object_path: [*:0]const u8, p_cancellable: ?*gio.Cancellable, p_error: ?**glib.Error) ?*Proxy {
        \\        return @ptrCast(@alignCast(gio.Initable.new(Proxy.getGObjectType(), p_cancellable, p_error, "g-flags", @as(c_uint, @bitCast(flags)), "g-name", p_name, "g-connection", p_connection, "g-object-path", p_object_path, "g-interface-name", getInfo().f_name.?)));
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
        \\
    );

    try writeVirtualMethods(writer, interface);
    try writeSignals(writer, interface, false);
    try writeClass(writer, interface, false);
    try writeDBusSignals(writer, interface);
    try writeUpdateProperties(writer, interface);

    _ = try writer.write("};\n");
}
