const Zigshot = @import("Zigshot.zig").Zigshot;
const FrameData = Zigshot.FrameData;
const OutputInfo = Zigshot.OutputInfo;
const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const std = @import("std");

pub fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, app: *Zigshot) void {
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

pub fn output_listener(output: *wl.Output, event: wl.Output.Event, output_list: *std.ArrayList(OutputInfo)) void {
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

pub fn frame_listener(_: *zwlr.ScreencopyFrameV1, event: zwlr.ScreencopyFrameV1.Event, frame_data: *FrameData) void {
    switch (event) {
        .buffer_done => {
            frame_data.*.frame_buffer_done = true;
        },
        else => {},
    }
}
