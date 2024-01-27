const std = @import("std");
const builtin = @import("builtin");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const Animation = j2d.AnimationSystem.Animation;

const Map = @This();

ptr: *anyopaque,
vtable: *const VTable,

pub const VTable = struct {
    init: *const fn (
        self: *anyopaque,
        ctx: jok.Context,
        global_sheet: **j2d.SpriteSheet,
        global_as: **j2d.AnimationSystem,
        global_audio_engine: **zaudio.Engine,
    ) anyerror!void,

    deinit: *const fn (self: *anyopaque, ctx: jok.Context) void,

    windowSize: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) [2]u32,

    updateCamera: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void,

    nextLevel: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void,
    prevLevel: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void,
    initLevel: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void,

    event: *const fn (self: *anyopaque, ctx: jok.Context, e: sdl.Event) anyerror!void,

    update: *const fn (self: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void,

    draw: *const fn (self: *anyopaque, ctx: jok.Context) anyerror!void,
};

pub fn init(
    self: Map,
    ctx: jok.Context,
    global_sheet: **j2d.SpriteSheet,
    global_as: **j2d.AnimationSystem,
    global_audio_engine: **zaudio.Engine,
) anyerror!void {
    try self.vtable.init(self.ptr, ctx, global_sheet, global_as, global_audio_engine);
}

pub fn deinit(self: Map, ctx: jok.Context) void {
    self.vtable.deinit(self.ptr, ctx);
}

pub fn windowSize(self: Map, ctx: jok.Context, full_view: bool) [2]u32 {
    return self.vtable.windowSize(self.ptr, ctx, full_view);
}

pub fn updateCamera(self: Map, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.vtable.updateCamera(self.ptr, ctx, full_view);
}

pub fn nextLevel(self: Map, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.vtable.nextLevel(self.ptr, ctx, full_view);
}
pub fn prevLevel(self: Map, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.vtable.prevLevel(self.ptr, ctx, full_view);
}
pub fn initLevel(self: Map, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.vtable.initLevel(self.ptr, ctx, full_view);
}

pub fn event(self: Map, ctx: jok.Context, e: sdl.Event) anyerror!void {
    try self.vtable.event(self.ptr, ctx, e);
}

pub fn update(self: Map, ctx: jok.Context, full_view: bool) anyerror!void {
    try self.vtable.update(self.ptr, ctx, full_view);
}

pub fn draw(self: Map, ctx: jok.Context) anyerror!void {
    try self.vtable.draw(self.ptr, ctx);
}
