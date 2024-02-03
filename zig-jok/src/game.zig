const std = @import("std");
const builtin = @import("builtin");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const Animation = j2d.AnimationSystem.Animation;
const Map = @import("Map.zig");
const MapV1 = @import("versions/v1/Map.zig");
const MapV2 = @import("versions/v2/Map.zig");

// Constants
const scale: f32 = if (builtin.os.tag == .linux) 2.0 else 1.0;
// Game assets
var sheet: *j2d.SpriteSheet = undefined;
var as: *j2d.AnimationSystem = undefined;
var audio_engine: *zaudio.Engine = undefined;
var map: Map = undefined;

// local variables
var full_view = false;
var past_first_frame = false;

// ==== Game Engine variables and functions
pub const jok_window_title: [:0]const u8 = "Bobby Carrot";
pub const jok_exit_on_recv_esc = false;

pub fn init(ctx: jok.Context) !void {
    std.log.info("game init", .{});

    const ratio = ctx.getAspectRatio();
    std.log.info("ratio: {}, scale: {}", .{ ratio, scale });
    try ctx.renderer().setScale(scale * ratio, scale * ratio);

    var args = std.process.args();
    _ = args.skip();
    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "v1")) {
            const map_impl = try ctx.allocator().create(MapV1);
            map_impl.* = .{};
            map = Map.interface(map_impl);
        } else if (std.mem.eql(u8, arg, "v2")) {
            const map_impl = try ctx.allocator().create(MapV2);
            map_impl.* = .{};
            map = Map.interface(map_impl);
        } else {
            std.log.err("invalid arg: {s}", .{arg});
            return error.InvalidArg;
        }
    } else {
        const map_impl = try ctx.allocator().create(MapV1);
        map_impl.* = .{};
        map = Map.interface(map_impl);
    }
    try map.init(ctx, &sheet, &as, &audio_engine);

    try updateWindowSize(ctx, true);
    try map.initLevel(ctx, true);
}

fn updateWindowSize(ctx: jok.Context, full: bool) !void {
    const size = map.windowSize(ctx, full);
    std.log.info("window size: width={}, height={}", .{ size[0], size[1] });
    const width: f32 = @floatFromInt(size[0]);
    const height: f32 = @floatFromInt(size[1]);
    sdl.c.SDL_SetWindowSize(
        ctx.window().ptr,
        @intFromFloat(width * scale),
        @intFromFloat(height * scale),
    );
    try ctx.renderer().setLogicalSize(@intFromFloat(width), @intFromFloat(height));
}

pub fn event(ctx: jok.Context, e: sdl.Event) !void {
    // FIXME: must set window size with full view in init() function
    if (!past_first_frame) {
        past_first_frame = true;
        try updateWindowSize(ctx, full_view);
        try map.updateCamera(ctx, full_view);
    }
    switch (e) {
        .key_up => |key| switch (key.scancode) {
            .q => ctx.kill(),
            .n => try map.nextLevel(ctx, full_view),
            .p => try map.prevLevel(ctx, full_view),
            .f => {
                full_view = !full_view;
                try updateWindowSize(ctx, full_view);
                try map.updateCamera(ctx, full_view);
            },
            .r => try map.initLevel(ctx, full_view),
            else => {},
        },
        else => {},
    }
    try map.event(ctx, e);
}

pub fn update(ctx: jok.Context) !void {
    try map.update(ctx, full_view);
}

pub fn draw(ctx: jok.Context) !void {
    // your 2d drawing
    try j2d.begin(.{ .depth_sort = .back_to_forth });
    try map.draw(ctx);
    try j2d.end();
}

pub fn quit(ctx: jok.Context) void {
    std.log.info("game quit", .{});
    map.deinit(ctx);
    audio_engine.destroy();
    as.destroy();
    sheet.destroy();
}
