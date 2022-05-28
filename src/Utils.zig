const Zigshot = @import("Zigshot.zig");

const std = @import("std");
const wl = @import("wayland").client.wl;

pub fn roundtrip(app: *Zigshot) !void {
    if (app.*.display.roundtrip() != .SUCCESS) return error.WaylandRoundtripFailed;
}

pub fn dispatch(app: *Zigshot) !void {
    if (app.*.display.dispatch() != .SUCCESS) return error.WaylandDispatchFailed;
}

pub fn findOutputItemByPointer(infos: *std.ArrayListUnmanaged(Zigshot.OutputInfo), output: *wl.Output) *Zigshot.OutputInfo {
    for (infos.items) |*item| {
        if (item.pointer == output) {
            return item;
        }
    }
    const ptr = infos.addOne(Zigshot.allocator) catch @panic("out of memory");
    ptr.* = Zigshot.OutputInfo{ .pointer = output };
    return ptr;
}

pub fn check_globals(app: *Zigshot) !void {
    if (app.*.screencopy_manager == null) {
        return error.ZwlrScreencopyUnstableNotAdvertised;
    }
    if (app.*.output_global == null) {
        return error.WlOutuptNotAdvertised;
    }
    if (app.*.valid_outputs.items.len == 0) {
        return error.NoValidOutputFound;
    }
    if (app.*.shm == null) {
        return error.FailedToFetchWlShm;
    }
    if (app.*.output_manager == null) {
        return error.XdgOutputManagerNotAdvertised;
    }
}
