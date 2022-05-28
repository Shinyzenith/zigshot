pub const Zigshot = @This();
const Utils = @import("Utils.zig");
const Listeners = @import("Listeners.zig");

const std = @import("std");
pub const allocator = std.heap.c_allocator;

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

    var supported_format: ?wl.Shm.Format = null;
    for (zigshot.frame_formats.items) |cap| {
        switch (cap.buffer_format) {
            .xbgr8888 => {
                supported_format = wl.Shm.Format.xbgr8888;
                break;
            },
            .argb8888 => {
                supported_format = wl.Shm.Format.argb8888;
                break;
            },
            .xrgb8888 => {
                supported_format = wl.Shm.Format.xrgb8888;
                break;
            },
            else => {},
        }
    }
    if (supported_format == null) {
        std.debug.print("No formats found that we officially support (xbgr8888, argb8888, xrgb8888). File a GitHub issue for feature requests.", .{});
        return;
    }
    //TODO: Handle proper logging and debug flags.
    //TODO: Add callback to each wl_output to check for x, y, width, height in global compositor space from xdg_output_manager.
    std.debug.print("{}", .{try Utils.allocate_shm_file(1920)});
}
