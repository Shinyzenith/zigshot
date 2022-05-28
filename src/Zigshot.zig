pub const Zigshot = @This();
const Utils = @import("Utils.zig");
const Listeners = @import("Listeners.zig");

const std = @import("std");
pub const allocator = std.heap.c_allocator;

const mman = @cImport(@cInclude("sys/mman.h"));
const unistd = @cImport(@cInclude("unistd.h"));

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const zxdg = @import("wayland").client.zxdg;

pub const OutputInfo = struct {
    name: [*:0]const u8 = undefined,
    pointer: *wl.Output = undefined,

    scale: i32 = 1,
    transform: wl.Output.Transform = undefined,

    x: i32 = 0,
    y: i32 = 0,

    width: i32 = 0,
    height: i32 = 0,
};

pub const FrameData = struct {
    buffer_format: wl.Shm.Format = undefined,
    buffer_height: usize = undefined,
    buffer_stride: usize = undefined,
    buffer_width: usize = undefined,
};

display: *wl.Display,
shm: ?*wl.Shm = null,
screencopy_manager: ?*zwlr.ScreencopyManagerV1 = null,
output_manager: ?*zxdg.OutputManagerV1 = null,

output_global: ?*wl.Output = null,
valid_outputs: std.ArrayListUnmanaged(OutputInfo) = .{},

frame_buffer_done: bool = false,
frame_buffer_ready: bool = false,
frame_buffer_failed: bool = false,
frame_formats: std.ArrayListUnmanaged(FrameData) = .{},

pub fn main() !void {
    var zigshot: Zigshot = .{
        .display = try wl.Display.connect(null),
    };
    const registry = try zigshot.display.getRegistry();
    defer {
        registry.destroy();
        zigshot.display.disconnect();

        zigshot.valid_outputs.deinit(allocator);
        zigshot.frame_formats.deinit(allocator);
    }

    registry.setListener(*@TypeOf(zigshot), Listeners.registry_listener, &zigshot);
    try Utils.roundtrip(&zigshot);

    zigshot.output_global.?.setListener(*@TypeOf(zigshot.valid_outputs), Listeners.output_listener, &zigshot.valid_outputs);
    try Utils.dispatch(&zigshot);
    try Utils.check_globals(&zigshot);

    const frame = try zigshot.screencopy_manager.?.captureOutput(1, zigshot.valid_outputs.items[0].pointer);
    frame.setListener(*@TypeOf(zigshot), Listeners.frame_listener, &zigshot);
    while (!zigshot.frame_buffer_done) {
        try Utils.dispatch(&zigshot);
    }

    var supported_frame: ?FrameData = null;
    for (zigshot.frame_formats.items) |capture| {
        switch (capture.buffer_format) {
            .xbgr8888, .argb8888, .xrgb8888 => {
                supported_frame = capture;
                break;
            },
            else => {},
        }
    }
    if (supported_frame == null) {
        std.debug.print("No formats found that we officially support (xbgr8888, argb8888, xrgb8888). File a GitHub issue for feature requests.\n", .{});
        return;
    }

    const frame_bytes = supported_frame.?.buffer_stride * supported_frame.?.buffer_height;
    const fd = try Utils.allocate_shm_file(frame_bytes);
    defer _ = unistd.close(fd);
    const data = mman.mmap(null, frame_bytes, mman.PROT_READ | mman.PROT_WRITE, mman.MAP_SHARED, fd, 0);
    defer _ = mman.munmap(data, frame_bytes);
    const shm_pool = try zigshot.shm.?.createPool(fd, @bitCast(i32, @truncate(u32, frame_bytes)));
    var buffer = try shm_pool.createBuffer(
        0,
        @bitCast(i32, @truncate(u32, supported_frame.?.buffer_width)),
        @bitCast(i32, @truncate(u32, supported_frame.?.buffer_height)),
        @bitCast(i32, @truncate(u32, supported_frame.?.buffer_stride)),
        supported_frame.?.buffer_format,
    );
    //defer wl.Buffer.Destroy(buffer);

    frame.copy(buffer);
    try Utils.dispatch(&zigshot);

    while (true) {
        if (zigshot.frame_buffer_failed) {
            std.debug.print("Faied to copy frame data into buffer.\n", .{});
            return;
        }
        if (zigshot.frame_buffer_ready) {
            std.debug.print("READY!\n", .{});
            return;
        }
    }
    //TODO: Handle proper logging and debug flags.
    //TODO: Add callback to each wl_output to check for x, y, width, height in global compositor space from xdg_output_manager.
}
