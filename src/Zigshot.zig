pub const Zigshot = @This();

const std = @import("std");
const gpa = std.heap.c_allocator;

const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;

pub const OutputInfo = struct {
    name: [*:0]const u8 = undefined,
    pointer: *wl.Output = undefined,
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

output_global: ?*wl.Output = null,
valid_outputs: std.ArrayList(OutputInfo),

frame_buffer_done: bool = false,
frame_buffer_ready: bool = false,
frame_buffer_failed: bool = false,
frame_formats: std.ArrayList(FrameData),

pub fn main() !void {
    var zigshot: Zigshot = .{ .display = try wl.Display.connect(null), .valid_outputs = std.ArrayList(OutputInfo).init(gpa), .frame_formats = std.ArrayList(FrameData).init(gpa) };
    const registry = try zigshot.display.getRegistry();
    defer {
        registry.destroy();
        zigshot.display.disconnect();

        zigshot.valid_outputs.deinit();
        zigshot.frame_formats.deinit();
    }

    registry.setListener(*@TypeOf(zigshot), registry_listener, &zigshot);
    try roundtrip(&zigshot);

    zigshot.output_global.?.setListener(*@TypeOf(zigshot.valid_outputs), output_listener, &zigshot.valid_outputs);
    try dispatch(&zigshot);
    try check_globals(&zigshot);

    const frame = try zigshot.screencopy_manager.?.captureOutput(1, zigshot.valid_outputs.items[0].pointer);
    frame.setListener(*@TypeOf(zigshot), frame_listener, &zigshot);
    while (!zigshot.frame_buffer_done) {
        try dispatch(&zigshot);
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
        std.os.exit(1);
    }
    //TODO: Handle proper logging and debug flags.
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

fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, app: *Zigshot) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, zwlr.ScreencopyManagerV1.getInterface().name) == 0) {
                app.*.screencopy_manager = registry.bind(global.name, zwlr.ScreencopyManagerV1, 3) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Output.getInterface().name) == 0) {
                app.*.output_global = registry.bind(global.name, wl.Output, 4) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Shm.getInterface().name) == 0) {
                app.*.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn output_listener(output: *wl.Output, event: wl.Output.Event, output_list: *std.ArrayList(OutputInfo)) void {
    switch (event) {
        .name => |ev| {
            output_list.append(OutputInfo{
                .name = ev.name,
                .pointer = output,
            }) catch {
                @panic("Failed to allocate memory.");
            };
        },
        else => {},
    }
}

fn frame_listener(_: *zwlr.ScreencopyFrameV1, event: zwlr.ScreencopyFrameV1.Event, app: *Zigshot) void {
    switch (event) {
        .buffer_done => {
            app.*.frame_buffer_done = true;
        },
        .ready => {
            app.*.frame_buffer_ready = true;
        },
        .buffer => |ev| {
            app.*.frame_formats.append(FrameData{
                .buffer_format = ev.format,
                .buffer_height = ev.height,
                .buffer_width = ev.width,
                .buffer_stride = ev.stride,
            }) catch {
                @panic("Failed to allocate memory.");
            };
        },
        .failed => {
            app.*.frame_buffer_failed = true;
        },
        else => {},
    }
}
