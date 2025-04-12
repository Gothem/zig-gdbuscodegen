const std = @import("std");
const glib = @import("glib");
const gio = @import("gio");
const DBusTest = @import("gdbus").Test;
const log = std.log.scoped(.server);

var loop: *glib.MainLoop = undefined;

pub fn main() !void {
    log.debug("Hello from server.", .{});

    loop = glib.MainLoop.new(null, @intFromBool(false));
    defer loop.unref();

    const dbus = DBusTest.Skeleton.new();
    _ = gio.busOwnName(
        gio.BusType.session,
        "org.example.Test",
        .{},
        onBusAcquired,
        onNameAcquired,
        onNameLost,
        dbus,
        onUserDataDestroy,
    );

    dbus.Ping = ping;

    loop.run();

    log.debug("Ending server", .{});
}

fn ping(_: *DBusTest.Skeleton, o_invocation: ?*gio.DBusMethodInvocation, msg: [*:0]const u8) void {
    const invocation = o_invocation orelse return;
    log.debug("Ping = {s}", .{msg});

    const variant = glib.ext.Variant.newFrom(.{"Pong"});
    invocation.returnValue(variant);

    loop.quit();
}

fn onBusAcquired(bus: *gio.DBusConnection, _: [*:0]const u8, p_dbus: ?*anyopaque) callconv(.C) void {
    const dbus: *DBusTest.Skeleton = @ptrCast(@alignCast(p_dbus));
    log.debug("onBusAcquired", .{});

    var gliberror: ?*glib.Error = null;
    _ = dbus.as(gio.DBusInterfaceSkeleton).@"export"(bus, "/Test", &gliberror);
}

fn onNameAcquired(_: *gio.DBusConnection, name: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
    log.debug("onNameAcquired: {s}", .{name});
}

fn onNameLost(_: *gio.DBusConnection, name: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
    log.debug("onNameLost: {s}", .{name});
}

fn onUserDataDestroy(_: ?*anyopaque) callconv(.C) void {
    log.debug("onUserDataDestroy", .{});
}
