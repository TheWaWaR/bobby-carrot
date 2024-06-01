const std = @import("std");
const jok = @import("jok");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = jok.createGame(
        b,
        "bobby-carrot",
        "src/game.zig",
        target,
        optimize,
        .{},
    );
    const install_cmd = b.addInstallArtifact(exe, .{});

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(&install_cmd.step);

    const run_step = b.step("run", "Run game");
    run_step.dependOn(&run_cmd.step);
}
