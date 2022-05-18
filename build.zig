const std = @import("std");
// This is basically the wayland scanner function.
const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *std.build.Builder) void {
    // Creating the build target and mode.
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // Creating the wayland-scanner.
    const scanner = ScanProtocolsStep.create(b);

    // Generate the bindings we need.
    scanner.addProtocolPath("deps/wlr-protocols/unstable/wlr-screencopy-unstable-v1.xml");
    scanner.generate("zwlr_screencopy_manager_v1", 3);
    scanner.generate("wl_output", 4);
    scanner.generate("wl_shm", 1);

    // Creating the packages we need.
    const wayland = std.build.Pkg{
        .name = "wayland",
        .path = .{ .generated = &scanner.result },
    };
    // Creating the executable.
    const zigshot = b.addExecutable("zigshot", "src/Zigshot.zig");

    // Setting executable target and build mode.
    zigshot.setTarget(target);
    zigshot.setBuildMode(mode);

    // Depend on scanner step.
    zigshot.step.dependOn(&scanner.step);

    scanner.addCSource(zigshot); // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented

    // Add the required packages to our project.
    zigshot.addPackage(wayland);

    // Linking to the system libraries.
    zigshot.linkLibC();
    zigshot.linkSystemLibrary("wayland-client");

    // Install the binary to the mentioned prefix.
    zigshot.install();
}
