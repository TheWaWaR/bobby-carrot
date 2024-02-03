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
    viewOffset: *const fn (self: *anyopaque) [2]f32,
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
pub fn viewOffset(self: Map) [2]f32 {
    return self.vtable.viewOffset(self.ptr);
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

pub fn interface(impl_self: anytype) Map {
    const Ptr = @TypeOf(impl_self);
    const ptr_info = @typeInfo(Ptr);
    if (ptr_info != .Pointer) @compileError("ptr must be a pointer");
    if (ptr_info.Pointer.size != .One) @compileError("ptr must be a single item pointer");

    const Impl = struct {
        pub fn init(
            ptr: *anyopaque,
            ctx: jok.Context,
            global_sheet: **j2d.SpriteSheet,
            global_as: **j2d.AnimationSystem,
            global_audio_engine: **zaudio.Engine,
        ) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.init(ctx, global_sheet, global_as, global_audio_engine);
        }

        pub fn deinit(ptr: *anyopaque, ctx: jok.Context) void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            self.deinit(ctx);
        }

        pub fn windowSize(ptr: *anyopaque, ctx: jok.Context, full_view: bool) [2]u32 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.windowSize(ctx, full_view);
        }
        pub fn viewOffset(ptr: *anyopaque) [2]f32 {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            return self.viewOffset();
        }
        pub fn updateCamera(ptr: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.updateCamera(ctx, full_view);
        }

        pub fn nextLevel(ptr: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.nextLevel(ctx, full_view);
        }
        pub fn prevLevel(ptr: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.prevLevel(ctx, full_view);
        }
        pub fn initLevel(ptr: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.initLevel(ctx, full_view);
        }

        pub fn event(ptr: *anyopaque, ctx: jok.Context, e: sdl.Event) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.event(ctx, e);
        }

        pub fn update(ptr: *anyopaque, ctx: jok.Context, full_view: bool) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.update(ctx, full_view);
        }

        pub fn draw(ptr: *anyopaque, ctx: jok.Context) anyerror!void {
            const self: Ptr = @ptrCast(@alignCast(ptr));
            try self.draw(ctx);
        }
    };

    return .{
        .ptr = impl_self,
        .vtable = &.{
            .init = Impl.init,
            .deinit = Impl.deinit,
            .windowSize = Impl.windowSize,
            .viewOffset = Impl.viewOffset,
            .updateCamera = Impl.updateCamera,
            .nextLevel = Impl.nextLevel,
            .prevLevel = Impl.prevLevel,
            .initLevel = Impl.initLevel,
            .event = Impl.event,
            .update = Impl.update,
            .draw = Impl.draw,
        },
    };
}
