const std = @import("std");
const builtin = @import("builtin");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const Bobby = @import("Bobby.zig");
const Animation = j2d.AnimationSystem.Animation;

// Constants
const width_points: u32 = 16;
const height_points: u32 = 16;
const view_width_points: u32 = 10;
const view_height_points: u32 = 12;
const width: u32 = 32 * width_points;
const height: u32 = 32 * height_points;
const view_width: u32 = 32 * view_width_points;
const view_height: u32 = 32 * view_height_points;
const scale: f32 = if (builtin.os.tag == .linux) 2.0 else 1.0;

// Game assets
var sheet: *j2d.SpriteSheet = undefined;
var as: *j2d.AnimationSystem = undefined;
var tileset: j2d.Sprite = undefined;
var tile_hud: j2d.Sprite = undefined;
var tile_numbers: j2d.Sprite = undefined;
var audio_engine: *zaudio.Engine = undefined;
var sfx_end: *zaudio.Sound = undefined;
// local variables
var bobby: Bobby = undefined;
var map_info: ?MapInfo = null;
var currentLevel: usize = 0;
var full_view = false;
var x_offset: f32 = 0;
var x_right_offset: f32 = 0;
var y_offset: f32 = 0;

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

    const ratio = ctx.getAspectRatio();
    try ctx.renderer().setScale(scale * ratio, scale * ratio);

    audio_engine = try zaudio.Engine.create(null);
    sfx_end = try audio_engine.createSoundFromFile("assets/audio/cleared.mp3", .{});
    sfx_end.setLooping(false);

    // Setup animations
    sheet = try j2d.SpriteSheet.fromPicturesInDir(ctx, "assets/image", 800, 800, 1, true, .{});
    tileset = sheet.getSpriteByName("tileset").?;
    tile_hud = sheet.getSpriteByName("hud").?;
    tile_numbers = sheet.getSpriteByName("numbers").?;
    as = try j2d.AnimationSystem.create(ctx.allocator());
    const bobby_idle = sheet.getSpriteByName("bobby_idle").?;
    const bobby_fade = sheet.getSpriteByName("bobby_fade").?;
    const bobby_death = sheet.getSpriteByName("bobby_death").?;
    try as.add(
        "bobby_idle",
        &[_]j2d.Sprite{
            bobby_idle.getSubSprite(0 * 36, 0, 36, 50),
            bobby_idle.getSubSprite(1 * 36, 0, 36, 50),
            bobby_idle.getSubSprite(2 * 36, 0, 36, 50),
        },
        120.0 / 8,
        true,
    );
    try as.add(
        "fade_in",
        &[_]j2d.Sprite{
            bobby_fade.getSubSprite(8 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(7 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(6 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(5 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(4 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(3 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(2 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(1 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(0 * 36, 0, 36, 50),
        },
        180.0 / 8.0,
        false,
    );
    try as.add(
        "fade_out",
        &[_]j2d.Sprite{
            bobby_fade.getSubSprite(0 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(1 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(2 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(3 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(4 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(5 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(6 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(7 * 36, 0, 36, 50),
            bobby_fade.getSubSprite(8 * 36, 0, 36, 50),
        },
        180.0 / 8.0,
        false,
    );
    try as.add(
        "bobby_death",
        &[_]j2d.Sprite{
            bobby_death.getSubSprite(0 * 44, 0, 44, 54),
            bobby_death.getSubSprite(1 * 44, 0, 44, 54),
            bobby_death.getSubSprite(2 * 44, 0, 44, 54),
            bobby_death.getSubSprite(3 * 44, 0, 44, 54),
            bobby_death.getSubSprite(4 * 44, 0, 44, 54),
            bobby_death.getSubSprite(5 * 44, 0, 44, 54),
            bobby_death.getSubSprite(6 * 44, 0, 44, 54),
            bobby_death.getSubSprite(7 * 44, 0, 44, 54),
        },
        180.0 / 8.0,
        false,
    );
    inline for (.{
        "bobby_left",
        "bobby_right",
        "bobby_up",
        "bobby_down",
    }) |name| {
        const sprite = sheet.getSpriteByName(name).?;
        var sprites: [8]j2d.Sprite = undefined;
        for (0..sprites.len) |i| {
            const x: f32 = @floatFromInt(i);
            sprites[i] = sprite.getSubSprite(x * 36, 0, 36, 50);
        }
        try as.add(name, &sprites, 30.0, true);
    }
    inline for (.{
        "tile_finish",
        "tile_conveyor_left",
        "tile_conveyor_right",
        "tile_conveyor_up",
        "tile_conveyor_down",
    }) |name| {
        const sprite = sheet.getSpriteByName(name).?;
        var sprites: [4]j2d.Sprite = undefined;
        for (0..sprites.len) |i| {
            const x: f32 = @floatFromInt(i);
            sprites[i] = sprite.getSubSprite(x * 32, 0, 32, 32);
        }
        try as.add(name, &sprites, 16.0, true);
    }

    updateWindowSize(ctx);
    try initLevel(ctx);
}

fn updateCamera(ctx: jok.Context) !void {
    if (full_view) {
        try ctx.renderer().setViewport(.{
            .x = 0,
            .y = 0,
            .width = @as(c_int, width),
            .height = @as(c_int, height),
        });
        x_offset = 0;
        x_right_offset = 0;
        y_offset = 0;
    } else {
        var x: c_int = @intFromFloat(bobby.current_pos.x);
        var y: c_int = @intFromFloat(bobby.current_pos.y);
        const x_max = @as(c_int, width - view_width);
        const y_max = @as(c_int, height - view_height);
        x -= @as(c_int, view_width / 2);
        y -= @as(c_int, view_height / 2);
        if (x < 0) {
            x = 0;
        }
        if (x > x_max) {
            x = x_max;
        }
        if (y < 0) {
            y = 0;
        }
        if (y > y_max) {
            y = y_max;
        }

        try ctx.renderer().setViewport(.{
            .x = -x,
            .y = -y,
            .width = @as(c_int, view_width) + x,
            .height = @as(c_int, view_height) + y,
        });
        x_offset = @floatFromInt(x);
        x_right_offset = @floatFromInt(x_max - x);
        y_offset = @floatFromInt(y);
    }
}

fn initLevel(ctx: jok.Context) !void {
    var buf: [64]u8 = undefined;
    const filename = if (currentLevel < 30) blk: {
        break :blk try std.fmt.bufPrint(&buf, "assets/level/normal{d:0>2}.blm", .{currentLevel + 1});
    } else blk: {
        break :blk try std.fmt.bufPrint(&buf, "assets/level/egg{d:0>2}.blm", .{currentLevel - 30 + 1});
    };
    std.log.info("level file name: {s}", .{filename});

    if (map_info) |info| {
        ctx.allocator().free(info.data_origin);
    }

    // Load level data
    const data = try std.fs.cwd().readFileAlloc(ctx.allocator(), filename, 512);
    var start_idx: usize = 0;
    var end_idx: usize = 0;
    var carrot_total: usize = 0;
    var egg_total: usize = 0;
    for (data[4..], 0..) |byte, idx| {
        switch (byte) {
            19 => carrot_total += 1,
            21 => start_idx = idx,
            44 => end_idx = idx,
            45 => egg_total += 1,
            else => {},
        }
    }
    map_info = MapInfo{
        .data_origin = data,
        .start_idx = start_idx,
        .end_idx = end_idx,
        .carrot_total = carrot_total,
        .egg_total = egg_total,
    };
    // std.log.info("map_info: {any}", .{map_info});

    bobby = Bobby.new(ctx.seconds(), map_info.?, as, sfx_end);
    try updateCamera(ctx);
}

fn updateWindowSize(ctx: jok.Context) void {
    const w = @as(f32, if (full_view) width else view_width);
    const h = @as(f32, if (full_view) height else view_height);
    sdl.c.SDL_SetWindowSize(
        ctx.window().ptr,
        @intFromFloat(w * scale),
        @intFromFloat(h * scale),
    );
}

pub fn event(ctx: jok.Context, e: sdl.Event) !void {
    switch (e) {
        .key_up => |key| switch (key.scancode) {
            .q => ctx.kill(),
            .n => {
                currentLevel = (currentLevel + 1) % 50;
                try initLevel(ctx);
            },
            .p => {
                currentLevel = (currentLevel + 49) % 50;
                try initLevel(ctx);
            },
            .f => {
                full_view = !full_view;
                updateWindowSize(ctx);
                try updateCamera(ctx);
            },
            .r => try initLevel(ctx),
            else => {},
        },
        else => {},
    }
    try bobby.event(ctx, e);
}

pub fn update(ctx: jok.Context) !void {
    if (bobby.dead) {
        try initLevel(ctx);
    } else if (bobby.faded_out) {
        currentLevel = (currentLevel + 1) % 50;
        try initLevel(ctx);
    }
    if (try bobby.update(ctx)) {
        try updateCamera(ctx);
    }
}

pub fn draw(ctx: jok.Context) !void {
    // your 2d drawing
    try j2d.begin(.{ .depth_sort = .back_to_forth });

    // Draw Map
    var anim_list: [5]?*Animation = .{ null, null, null, null, null };
    for (map_info.?.data(), 0..) |byte, idx| {
        const anim_opt: ?[:0]const u8 = switch (byte) {
            40 => "tile_conveyor_left",
            41 => "tile_conveyor_right",
            42 => "tile_conveyor_up",
            43 => "tile_conveyor_down",
            44 => if (bobby.isFinished()) "tile_finish" else null,
            else => null,
        };
        const pos_x: f32 = @floatFromInt((idx % 16) * 32);
        const pos_y: f32 = @floatFromInt((idx / 16) * 32);
        if (anim_opt) |name| {
            var anim = as.animations.getPtr(name).?;
            try j2d.sprite(
                anim.getCurrentFrame(),
                .{ .pos = .{ .x = pos_x, .y = pos_y }, .depth = 0.8 },
            );
            anim_list[@as(usize, byte) - 40] = anim;
        } else {
            const offset_x: f32 = @floatFromInt((byte % 8) * 32);
            const offset_y: f32 = @floatFromInt((byte / 8) * 32);
            try j2d.sprite(
                tileset.getSubSprite(offset_x, offset_y, 32, 32),
                .{ .pos = .{ .x = pos_x, .y = pos_y }, .depth = 1.0 },
            );
        }
    }
    for (anim_list) |anim_opt| {
        if (anim_opt) |anim| {
            anim.update(ctx.deltaSeconds());
        }
    }

    // Draw indicators
    var icon_sprite: j2d.Sprite = undefined;
    var icon_width: u32 = undefined;
    var count: usize = undefined;
    if (bobby.carrot_total > 0) {
        count = bobby.carrot_total - bobby.carrot_count;
        icon_sprite = tile_hud.getSubSprite(0, 0, 46, 44);
        icon_width = 46;
    } else {
        count = bobby.egg_total - bobby.egg_count;
        icon_sprite = tile_hud.getSubSprite(46, 0, 34, 44);
        icon_width = 34;
    }
    const icon_x: u32 = width - icon_width - 4;
    try j2d.sprite(icon_sprite, .{ .pos = .{
        .x = @as(f32, @floatFromInt(icon_x)) - x_right_offset,
        .y = 4 + y_offset,
    } });
    inline for (.{
        count / 10,
        count % 10,
    }, 0..) |n, idx| {
        try j2d.sprite(
            tile_numbers.getSubSprite(@floatFromInt(n * 12), 0, 12, 18),
            .{ .pos = .{
                .x = @as(f32, @floatFromInt(icon_x - 2 - 12 * (2 - idx) - 1)) - x_right_offset,
                .y = 4 + 14 + y_offset,
            } },
        );
    }
    // draw keys
    var key_count: u32 = 0;
    inline for (.{
        bobby.key_gray,
        bobby.key_yellow,
        bobby.key_red,
    }, 0..) |key, idx| {
        if (key > 0) {
            try j2d.sprite(
                tile_hud.getSubSprite(@floatFromInt(122 + idx * 22), 0, 22, 44),
                .{ .pos = .{
                    .x = @as(f32, @floatFromInt(width - 22 - 4 - key_count * 22)) - x_right_offset,
                    .y = 4 + 44 + 2 + y_offset,
                } },
            );
            key_count += 1;
        }
    }
    // draw time
    const seconds: u32 = @intFromFloat(ctx.seconds() - bobby.start_time);
    var m = seconds / 60;
    var s = seconds % 60;
    if (m > 99) {
        m = 99;
        s = 99;
    }
    inline for (.{
        m / 10,
        m % 10,
        10,
        s / 10,
        s % 10,
    }, 0..) |tile_idx, idx| {
        try j2d.sprite(
            tile_numbers.getSubSprite(@floatFromInt(tile_idx * 12), 0, 12, 18),
            .{ .pos = .{
                .x = @as(f32, @floatFromInt(4 + 12 * idx)) + x_offset,
                .y = 4 + y_offset,
            } },
        );
    }

    try bobby.draw(ctx);

    try j2d.end();
}

pub fn quit(ctx: jok.Context) void {
    std.log.info("game quit", .{});
    ctx.allocator().free(map_info.?.data_origin);
    sfx_end.destroy();
    audio_engine.destroy();
    as.destroy();
    sheet.destroy();
}

pub const MapInfo = struct {
    data_origin: []const u8,
    start_idx: usize,
    end_idx: usize,
    carrot_total: usize,
    egg_total: usize,

    pub fn data(info: *const MapInfo) []const u8 {
        return info.data_origin[4..];
    }
};
