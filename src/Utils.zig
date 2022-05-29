const Zigshot = @import("Zigshot.zig");

const builtin = @import("builtin");
const os = std.os;
const std = @import("std");
const wl = @import("wayland").client.wl;

pub fn create_shm_fd() !os.fd_t {
    switch (builtin.target.os.tag) {
        .linux => {
            const name = try generate_random_name();
            return os.memfd_create(name, os.linux.MFD_CLOEXEC);
        },
        else => @compileError("Target OS not supported yet."),
    }
}

fn generate_random_name() ![]const u8 {
    const random = std.rand.Pcg.init(@truncate(u64, @bitCast(u128, std.time.nanoTimestamp()))).random();
    const number = random.uintLessThan(u32, 999999);
    return try std.fmt.allocPrint(Zigshot.allocator, "/zigshot-{d}", .{number});
}

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
