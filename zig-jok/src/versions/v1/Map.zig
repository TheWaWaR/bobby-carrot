const std = @import("std");
const builtin = @import("builtin");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const Bobby = @import("./Bobby.zig");
const Animation = j2d.AnimationSystem.Animation;
const Map = @import("../../Map.zig");

// Constants
const width_points: u32 = 16;
const height_points: u32 = 16;
const view_width_points: u32 = 10;
const view_height_points: u32 = 12;
const width: u32 = 32 * width_points;
const height: u32 = 32 * height_points;
const view_width: u32 = 32 * view_width_points;
const view_height: u32 = 32 * view_height_points;

// Game assets
as: *j2d.AnimationSystem = undefined,
tileset: j2d.Sprite = undefined,
tile_hud: j2d.Sprite = undefined,
tile_numbers: j2d.Sprite = undefined,
sfx_end: *zaudio.Sound = undefined,

// local variables
bobby: Bobby = undefined,
info: MapInfo = undefined,
currentLevel: usize = 0,
x_offset: f32 = 0,
x_right_offset: f32 = 0,
y_offset: f32 = 0,

const Self = @This();

pub fn init(
    self: *Self,
    ctx: jok.Context,
    global_sheet: **j2d.SpriteSheet,
    global_as: **j2d.AnimationSystem,
    global_audio_engine: **zaudio.Engine,
) anyerror!void {
    std.log.info("map init", .{});
    var audio_engine = try zaudio.Engine.create(null);
    self.sfx_end = try audio_engine.createSoundFromFile("assets/v1/audio/cleared.mp3", .{});
    self.sfx_end.setLooping(false);

    // Setup animations
    var sheet = try j2d.SpriteSheet.fromPicturesInDir(ctx, "assets/v1/image", 800, 800, 1, true, .{});
    self.tileset = sheet.getSpriteByName("tileset").?;
    self.tile_hud = sheet.getSpriteByName("hud").?;
    self.tile_numbers = sheet.getSpriteByName("numbers").?;
    self.as = try j2d.AnimationSystem.create(ctx.allocator());
    const bobby_idle = sheet.getSpriteByName("bobby_idle").?;
    const bobby_fade = sheet.getSpriteByName("bobby_fade").?;
    const bobby_death = sheet.getSpriteByName("bobby_death").?;
    try self.as.add(
        "bobby_idle",
        &[_]j2d.Sprite{
            bobby_idle.getSubSprite(0 * 36, 0, 36, 50),
            bobby_idle.getSubSprite(1 * 36, 0, 36, 50),
            bobby_idle.getSubSprite(2 * 36, 0, 36, 50),
        },
        120.0 / 8,
        true,
    );
    try self.as.add(
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
    try self.as.add(
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
    try self.as.add(
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
        try self.as.add(name, &sprites, 30.0, true);
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
        try self.as.add(name, &sprites, 16.0, true);
    }

    self.info = MapInfo.new();
    global_sheet.* = sheet;
    global_as.* = self.as;
    global_audio_engine.* = audio_engine;
}

pub fn deinit(self: *Self, ctx: jok.Context) void {
    ctx.allocator().free(self.info.data_origin);
    self.sfx_end.destroy();
    ctx.allocator().destroy(self);
}

pub fn windowSize(_: *Self, _: jok.Context, full_view: bool) [2]u32 {
    var size: [2]u32 = undefined;
    size[0] = if (full_view) width else view_width;
    size[1] = if (full_view) height else view_height;
    return size;
}

pub fn viewOffset(self: *Self) [2]f32 {
    return .{ self.x_offset, self.y_offset };
}

pub fn updateCamera(self: *Self, ctx: jok.Context, full_view: bool) anyerror!void {
    if (full_view) {
        try ctx.renderer().setViewport(.{
            .x = 0,
            .y = 0,
            .width = @as(c_int, width),
            .height = @as(c_int, height),
        });
        self.x_offset = 0;
        self.x_right_offset = 0;
        self.y_offset = 0;
    } else {
        var x: c_int = @intFromFloat(self.bobby.current_pos.x);
        var y: c_int = @intFromFloat(self.bobby.current_pos.y);
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
        self.x_offset = @floatFromInt(x);
        self.x_right_offset = @floatFromInt(x_max - x);
        self.y_offset = @floatFromInt(y);
    }
}

pub fn nextLevel(self: *Self, ctx: jok.Context, full_view: bool) anyerror!void {
    self.currentLevel = (self.currentLevel + 1) % 50;
    try self.initLevel(ctx, full_view);
}

pub fn prevLevel(self: *Self, ctx: jok.Context, full_view: bool) anyerror!void {
    self.currentLevel = (self.currentLevel + 49) % 50;
    try self.initLevel(ctx, full_view);
}

pub fn initLevel(self: *Self, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.info.load(ctx, self.currentLevel);
    self.bobby = Bobby.new(ctx.seconds(), self.info, self.as, self.sfx_end);
    try self.updateCamera(ctx, full_view);
}

pub fn event(self: *Self, ctx: jok.Context, e: sdl.Event) anyerror!void {
    try self.bobby.event(ctx, e);
}

pub fn update(self: *Self, ctx: jok.Context, full_view: bool) anyerror!void {
    if (self.bobby.dead) {
        try self.initLevel(ctx, full_view);
    } else if (self.bobby.faded_out) {
        self.currentLevel = (self.currentLevel + 1) % 50;
        try self.initLevel(ctx, full_view);
    }
    if (try self.bobby.update(ctx)) {
        try self.updateCamera(ctx, full_view);
    }
}

pub fn draw(self: *Self, ctx: jok.Context) anyerror!void {
    // Draw Map
    var anim_list: [5]?*Animation = .{ null, null, null, null, null };
    for (self.info.data(), 0..) |byte, idx| {
        const anim_opt: ?[:0]const u8 = switch (byte) {
            40 => "tile_conveyor_left",
            41 => "tile_conveyor_right",
            42 => "tile_conveyor_up",
            43 => "tile_conveyor_down",
            44 => if (self.bobby.isFinished()) "tile_finish" else null,
            else => null,
        };
        const pos_x: f32 = @floatFromInt((idx % 16) * 32);
        const pos_y: f32 = @floatFromInt((idx / 16) * 32);
        if (anim_opt) |name| {
            var anim = self.as.animations.getPtr(name).?;
            try j2d.sprite(
                anim.getCurrentFrame(),
                .{ .pos = .{ .x = pos_x, .y = pos_y }, .depth = 0.8 },
            );
            anim_list[@as(usize, byte) - 40] = anim;
        } else {
            const offset_x: f32 = @floatFromInt((byte % 8) * 32);
            const offset_y: f32 = @floatFromInt((byte / 8) * 32);
            try j2d.sprite(
                self.tileset.getSubSprite(offset_x, offset_y, 32, 32),
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
    if (self.bobby.carrot_total > 0) {
        count = self.bobby.carrot_total - self.bobby.carrot_count;
        icon_sprite = self.tile_hud.getSubSprite(0, 0, 46, 44);
        icon_width = 46;
    } else {
        count = self.bobby.egg_total - self.bobby.egg_count;
        icon_sprite = self.tile_hud.getSubSprite(46, 0, 34, 44);
        icon_width = 34;
    }
    const icon_x: u32 = width - icon_width - 4;
    try j2d.sprite(icon_sprite, .{ .pos = .{
        .x = @as(f32, @floatFromInt(icon_x)) - self.x_right_offset,
        .y = 4 + self.y_offset,
    } });
    inline for (.{
        count / 10,
        count % 10,
    }, 0..) |n, idx| {
        try j2d.sprite(
            self.tile_numbers.getSubSprite(@floatFromInt(n * 12), 0, 12, 18),
            .{ .pos = .{
                .x = @as(f32, @floatFromInt(icon_x - 2 - 12 * (2 - idx) - 1)) - self.x_right_offset,
                .y = 4 + 14 + self.y_offset,
            } },
        );
    }
    // draw keys
    var key_count: u32 = 0;
    inline for (.{
        self.bobby.key_gray,
        self.bobby.key_yellow,
        self.bobby.key_red,
    }, 0..) |key, idx| {
        if (key > 0) {
            try j2d.sprite(
                self.tile_hud.getSubSprite(@floatFromInt(122 + idx * 22), 0, 22, 44),
                .{ .pos = .{
                    .x = @as(f32, @floatFromInt(width - 22 - 4 - key_count * 22)) - self.x_right_offset,
                    .y = 4 + 44 + 2 + self.y_offset,
                } },
            );
            key_count += 1;
        }
    }
    // draw time
    const seconds: u32 = @intFromFloat(ctx.seconds() - self.bobby.start_time);
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
            self.tile_numbers.getSubSprite(@floatFromInt(tile_idx * 12), 0, 12, 18),
            .{ .pos = .{
                .x = @as(f32, @floatFromInt(4 + 12 * idx)) + self.x_offset,
                .y = 4 + self.y_offset,
            } },
        );
    }

    try self.bobby.draw(ctx);
}

pub const MapInfo = struct {
    data_origin: []const u8,
    start_idx: usize,
    end_idx: usize,
    carrot_total: usize,
    egg_total: usize,

    pub fn new() MapInfo {
        return .{
            .data_origin = undefined,
            .start_idx = 0,
            .end_idx = 0,
            .carrot_total = 0,
            .egg_total = 0,
        };
    }

    pub fn data(self: *const MapInfo) []const u8 {
        return self.data_origin[4..];
    }

    pub fn load(self: *MapInfo, ctx: jok.Context, current_level: usize) !void {
        var buf: [64]u8 = undefined;

        const title = if (current_level < 30) blk: {
            break :blk try std.fmt.bufPrintZ(&buf, "Bobby Carrot (v1, Normal {})", .{current_level + 1});
        } else blk: {
            break :blk try std.fmt.bufPrintZ(&buf, "Bobby Carrot (v1, Egg {})", .{current_level - 30 + 1});
        };
        sdl.c.SDL_SetWindowTitle(ctx.window().ptr, title);

        const filename = if (current_level < 30) blk: {
            break :blk try std.fmt.bufPrint(&buf, "assets/v1/level/normal{d:0>2}.blm", .{current_level + 1});
        } else blk: {
            break :blk try std.fmt.bufPrint(&buf, "assets/v1/level/egg{d:0>2}.blm", .{current_level - 30 + 1});
        };
        std.log.info("level file name: {s}", .{filename});

        ctx.allocator().free(self.data_origin);

        // Load level data
        self.data_origin = try std.fs.cwd().readFileAlloc(ctx.allocator(), filename, 512);
        self.carrot_total = 0;
        self.egg_total = 0;
        for (self.data(), 0..) |byte, idx| {
            switch (byte) {
                19 => self.carrot_total += 1,
                21 => self.start_idx = idx,
                44 => self.end_idx = idx,
                45 => self.egg_total += 1,
                else => {},
            }
        }
    }
};
