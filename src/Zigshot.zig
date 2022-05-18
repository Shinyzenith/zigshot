const Listeners = @import("Listeners.zig");

const std = @import("std");
const gpa = std.heap.c_allocator;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;

pub const Zigshot = @This();

pub const OutputInfo = struct {
    name: [*:0]const u8 = undefined,
    pointer: *wl.Output = undefined,
};

pub const FrameData = struct {
    frame_buffer_done: bool,
};

display: *wl.Display,
shm: ?*wl.Shm = null,
screencopy_manager: ?*zwlr.ScreencopyManagerV1 = null,
output_global: ?*wl.Output = null,
valid_outputs: std.ArrayList(OutputInfo),
frame_data: FrameData = FrameData{ .frame_buffer_done = false },

pub fn main() !void {
    var zigshot: Zigshot = .{ .display = try wl.Display.connect(null), .valid_outputs = std.ArrayList(OutputInfo).init(gpa) };
    const registry = try zigshot.display.getRegistry();
    defer {
        registry.destroy();
        zigshot.display.disconnect();
        zigshot.valid_outputs.deinit();
    }

    registry.setListener(*@TypeOf(zigshot), Listeners.registry_listener, &zigshot);
    try roundtrip(&zigshot);

    zigshot.output_global.?.setListener(*@TypeOf(zigshot.valid_outputs), Listeners.output_listener, &zigshot.valid_outputs);
    try dispatch(&zigshot);
    try check_globals(&zigshot);

    const frame = try zigshot.screencopy_manager.?.captureOutput(1, zigshot.valid_outputs.items[0].pointer);
    frame.setListener(*@TypeOf(zigshot.frame_data), Listeners.frame_listener, &zigshot.frame_data);
    while (zigshot.frame_data.frame_buffer_done) {
        try dispatch(&zigshot);
    }
}

fn roundtrip(app: *Zigshot) !void {
    if (app.*.display.roundtrip() != .SUCCESS) return error.WaylandRoundtripFailed;
}

fn dispatch(app: *Zigshot) !void {
    if (app.*.display.dispatch() != .SUCCESS) return error.WaylandDispatchFailed;
}

fn check_globals(app: *Zigshot) !void {
    if (app.*.screencopy_manager == null) {
        return error.ZwlrScreencopyUnstableNotAdvertised;
    }
    if (app.*.output_global == null) {
        return error.FetchingWlOutputFailed;
    }
    if (app.*.valid_outputs.items.len == 0) {
        return error.NoValidOutputFound;
    }
    if (app.*.shm == null) {
        return error.FailedToFetchWlShm;
    }
}
