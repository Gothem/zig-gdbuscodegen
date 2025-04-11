const std = @import("std");
const glib = @import("glib");
const gobject = @import("gobject");
const gio = @import("gio");
const DBusTest = @import("gdbus").Test;
const log = std.log.scoped(.client);

var loop: *glib.MainLoop = undefined;

pub fn main() !void {
    log.debug("Hello from client.", .{});

    loop = glib.MainLoop.new(null, @intFromBool(false));

    const connection = gio.busGetSync(gio.BusType.session, null, null) orelse @panic("No connection");
    const proxy = DBusTest.Proxy.newSync(connection, .{}, "org.example.Test", "/Test", null, null) orelse @panic("Proxy failed");

    const o_owner = proxy.as(gio.DBusProxy).getNameOwner();
    if (o_owner) |owner| {
        log.debug("Proxy created and connected to {s}", .{owner});
        callMethod(proxy);
    } else {
        log.debug("proxy created without owner, waiting server...", .{});
    }

    _ = gobject.Object.signals.notify.connect(proxy, ?*anyopaque, onOwnerChange, null, .{ .detail = "g-name-owner" });

    loop.run();

    log.debug("Ending client", .{});
}

fn onOwnerChange(proxy: *DBusTest.Proxy, _: *gobject.ParamSpec, _: ?*anyopaque) callconv(.C) void {
    const o_owner = proxy.as(gio.DBusProxy).getNameOwner();
    log.debug("proxy owner changed: {?s}", .{o_owner});

    if (o_owner != null) {
        callMethod(proxy);
    }
}

fn callMethod(proxy: *DBusTest.Proxy) void {
    const o_result = proxy.Ping("ping");
    var str: ?[*:0]const u8 = null;
    if (o_result) |result| {
        const child = result.getChildValue(0);
        defer child.unref();
        str = child.getString(null);
    }
    log.debug("proxy.Ping = {?s}", .{str});

    loop.quit();
}
