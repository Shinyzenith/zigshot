const Zigshot = @import("Zigshot.zig");
const Utils = @import("Utils.zig");

const std = @import("std");
const wl = @import("wayland").client.wl;
const zwlr = @import("wayland").client.zwlr;
const zxdg = @import("wayland").client.zxdg;

pub fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, app: *Zigshot) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, zwlr.ScreencopyManagerV1.getInterface().name) == 0) {
                app.*.screencopy_manager = registry.bind(global.name, zwlr.ScreencopyManagerV1, 3) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Output.getInterface().name) == 0) {
                app.*.output_global = registry.bind(global.name, wl.Output, 4) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Shm.getInterface().name) == 0) {
                app.*.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.cstr.cmp(global.interface, zxdg.OutputManagerV1.getInterface().name) == 0) {
                app.*.output_manager = registry.bind(global.name, zxdg.OutputManagerV1, 3) catch return;
            }
        },
        .global_remove => {},
    }
}

pub fn output_listener(output: *wl.Output, event: wl.Output.Event, output_list: *std.ArrayListUnmanaged(Zigshot.OutputInfo)) void {
    switch (event) {
        .name => |ev| {
            const ptr = Utils.findOutputItemByPointer(output_list, output);
            ptr.name = ev.name;
        },
        .scale => |ev| {
            const ptr = Utils.findOutputItemByPointer(output_list, output);
            ptr.scale = ev.factor;
        },
        .geometry => |ev| {
            const ptr = Utils.findOutputItemByPointer(output_list, output);
            ptr.transform = ev.transform;
        },
        else => {},
    }
}

pub fn frame_listener(_: *zwlr.ScreencopyFrameV1, event: zwlr.ScreencopyFrameV1.Event, app: *Zigshot) void {
    switch (event) {
        .buffer_done => {
            app.*.frame_buffer_done = true;
        },
        .ready => {
            app.*.frame_buffer_ready = true;
        },
        .buffer => |ev| {
            app.*.frame_formats.append(Zigshot.allocator, Zigshot.FrameData{
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
