const std = @import("std");
const builtin = @import("builtin");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const font = jok.font;
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
var show_help = false;
var audio_volume: f32 = 0.0;

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

    const init_full: bool = if (builtin.os.tag == .linux) true else false;
    try updateWindowSize(ctx, init_full);
    try map.initLevel(ctx, init_full);
}

fn updateWindowSize(ctx: jok.Context, full: bool) !void {
    const size = map.windowSize(ctx, full);
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
    if (builtin.os.tag == .linux and !past_first_frame) {
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
            .m => {
                if (audio_volume > 0.0) {
                    audio_volume = 0.0;
                } else {
                    audio_volume = 1.0;
                }
                try audio_engine.setVolume(audio_volume);
            },
            .f1, .h => show_help = !show_help,
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
    if (show_help) {
        const rect_color = sdl.Color.rgba(0xaa, 0xaa, 0xaa, 200);
        const atlas: *font.Atlas = try font.DebugFont.getAtlas(ctx, 20);
        const offset = map.viewOffset();
        const x_offset = 10;
        const y_offset = 35;
        var area: sdl.RectangleF = undefined;
        var max_width: f32 = 0.0;
        const msgs = .{
            "F: Toggle full view",
            "P: Previous level",
            "N: Next level",
            "R: Restart level",
            "Q: Quit the game",
            "H/F1: Toggle this help",
        };
        inline for (msgs, 0..) |msg, i| {
            const x = offset[0] + x_offset;
            const y = offset[1] + y_offset + i * 18;
            const opt = .{
                .atlas = atlas,
                .pos = .{ .x = x, .y = y },
                .ypos_type = .top,
                .tint_color = sdl.Color.rgb(12, 43, 54),
                .depth = 0,
            };
            try j2d.text(opt, msg, .{});
            area = try atlas.getBoundingBox(msg, .{ .x = x, .y = y }, .top, .aligned);
            max_width = @max(max_width, area.width);
        }

        const margin = 4.0;
        try j2d.rectFilled(
            .{
                .x = offset[0] + x_offset - margin,
                .y = offset[1] + y_offset - margin,
                .width = max_width + 2 * margin,
                .height = area.y + area.height - (offset[1] + y_offset) + 2 * margin,
            },
            rect_color,
            .{ .depth = 0.1 },
        );
    }
    try j2d.end();
}

pub fn quit(ctx: jok.Context) void {
    std.log.info("game quit", .{});
    map.deinit(ctx);
    audio_engine.destroy();
    as.destroy();
    sheet.destroy();
}
