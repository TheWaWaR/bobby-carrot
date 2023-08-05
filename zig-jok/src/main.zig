const std = @import("std");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;

const width_points: u32 = 16;
const height_points: u32 = 16;
const view_width_points: u32 = 10;
const view_height_points: u32 = 12;
const width: u32 = 32 * width_points;
const height: u32 = 32 * height_points;
const view_width: u32 = 32 * view_width_points;
const view_height: u32 = 32 * view_height_points;
const scale: f32 = 2.0;

var sheet: *j2d.SpriteSheet = undefined;
var as: *j2d.AnimationSystem = undefined;
var map_info: MapInfo = undefined;

const MapInfo = struct {
    data: []const u8,
    start_pos: usize,
    end_pos: usize,
    carrot_total: usize,
    egg_total: usize,
};

// ==== Game Engine variables and functions
pub const jok_window_title: [:0]const u8 = "Bobby Carrot";
pub const jok_exit_on_recv_esc = false;
pub const jok_window_size = jok.config.WindowSize{
    .custom = .{
        .width = @intFromFloat(@as(f32, width) * scale),
        .height = @intFromFloat(@as(f32, height) * scale),
    },
};

pub fn init(ctx: jok.Context) !void {
    std.log.info("game init", .{});
    try ctx.renderer().setScale(scale, scale);

    const size = ctx.getFramebufferSize();
    sheet = try j2d.SpriteSheet.fromPicturesInDir(
        ctx,
        "assets/image",
        @intFromFloat(size.x),
        @intFromFloat(size.y),
        1,
        true,
        .{},
    );

    const level_data = try std.fs.cwd().readFileAlloc(
        ctx.allocator(),
        "assets/level/normal01.blm",
        512,
    );
    const data = level_data[4..];
    var start_pos: usize = 0;
    var end_pos: usize = 0;
    var carrot_total: usize = 0;
    var egg_total: usize = 0;
    for (data, 0..) |byte, idx| {
        switch (byte) {
            19 => carrot_total += 1,
            21 => start_pos = idx,
            44 => end_pos = idx,
            45 => egg_total += 1,
            else => {},
        }
    }
    map_info = MapInfo{
        .data = data,
        .start_pos = start_pos,
        .end_pos = end_pos,
        .carrot_total = carrot_total,
        .egg_total = egg_total,
    };
    std.log.info("map_info: {any}", .{map_info});
}

pub fn event(ctx: jok.Context, e: sdl.Event) !void {
    _ = e;
    if (ctx.isKeyPressed(.q)) {
        ctx.kill();
    }
}

pub fn update(ctx: jok.Context) !void {
    _ = ctx;
    // your game state updating code
}

pub fn draw(ctx: jok.Context) !void {
    _ = ctx;
    const tileset = sheet.getSpriteByName("tileset").?;

    // your 2d drawing
    try j2d.begin(.{});

    for (map_info.data, 0..) |byte, idx| {
        const offset_x: f32 = @floatFromInt((byte % 8) * 32);
        const offset_y: f32 = @floatFromInt((byte / 8) * 32);
        const pos_x: f32 = @floatFromInt((idx % 16) * 32);
        const pos_y: f32 = @floatFromInt((idx / 16) * 32);
        try j2d.sprite(tileset.getSubSprite(offset_x, offset_y, 32, 32), .{
            .pos = .{ .x = pos_x, .y = pos_y },
        });
    }

    // ......
    try j2d.end();
}

pub fn quit(ctx: jok.Context) void {
    std.log.info("game quit", .{});
    ctx.allocator().free(map_info.data);
    sheet.destroy();
}
