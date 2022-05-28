const Zigshot = @import("Zigshot.zig");

const std = @import("std");
const time = std.time;
const rand = std.rand;
const wl = @import("wayland").client.wl;

const fcntl = @cImport(@cInclude("fcntl.h"));
const mman = @cImport(@cInclude("sys/mman.h"));
const unistd = @cImport(@cInclude("unistd.h"));

pub fn allocate_shm_file(size: u64) !isize {
    const fd = @bitCast(c_int, @truncate(c_int, try create_shm_fd()));
    while (true) {
        if (unistd.ftruncate(fd, @bitCast(c_long, size)) == 0) {
            return fd;
        }
        if (unistd.close(fd) != 0) {
            return error.FailedToFTruncateAndCloseFd;
        }
    }
}

fn create_shm_fd() !isize {
    while (true) {
        const shm_name = try generate_random_name();
        defer Zigshot.allocator.free(shm_name);
        const fd = mman.shm_open(shm_name.ptr, fcntl.O_RDWR | fcntl.O_CREAT | fcntl.O_EXCL, 0600);
        if (fd >= 0) {
            if (mman.shm_unlink(shm_name.ptr) == 0) {
                return fd;
            }
        }
    }
}

fn generate_random_name() ![]const u8 {
    const random = rand.Pcg.init(@truncate(u64, @bitCast(u128, time.nanoTimestamp()))).random();
    const number = random.uintLessThan(u32, 999999);
    const val = try std.fmt.allocPrintZ(Zigshot.allocator, "/zigshot-{d}", .{number});
    return val;
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
