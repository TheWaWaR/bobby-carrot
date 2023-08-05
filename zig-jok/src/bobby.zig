const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const Animation = j2d.AnimationSystem.Animation;

pub const Bobby = struct {
    state: State,
    next_state: ?State = null,
    start_time: f32,
    last_action_time: f32,
    current_pos: MapPos,
    moving_target: ?MapPos = null,
    as: *j2d.AnimationSystem,
    anim: []const u8,
    anim_stop: bool = true,
    anim_loop: bool = false,

    carrot_count: usize = 0,
    egg_count: usize = 0,
    key_gray: usize = 0,
    key_yellow: usize = 0,
    key_red: usize = 0,
    faded_out: bool = false,
    dead: bool = false,

    const Self = @This();

    pub fn new(start_pos: usize, start_time: f32, as: *j2d.AnimationSystem) Self {
        return Bobby{
            .current_pos = .{ .x = start_pos % 16, .y = start_pos / 16 },
            .start_time = start_time,
            .last_action_time = start_time,
            .state = .down,
            .as = as,
            .anim = "bobby_down",
        };
    }

    pub fn event(self: *Self, ctx: jok.Context, e: sdl.Event) !void {
        _ = ctx;
        const key_down = switch (e) {
            .key_down => |key| blk: {
                break :blk key;
            },
            else => null,
        };
        if (key_down) |key| {
            if (self.state != .death and self.state != .fade_in and self.state != .fade_out and self.next_state != .death and self.next_state != .fade_out) {
                self.next_state = switch (key.scancode) {
                    .left => .left,
                    .right => .right,
                    .up => .up,
                    .down => .down,
                    else => self.next_state,
                };
            }
        }
    }

    pub fn update(self: *Self, ctx: jok.Context) !void {
        if (ctx.seconds() - self.last_action_time >= 4.0 and self.state != .idle) {
            self.state = .idle;
            self.anim = "bobby_idle";
            self.anim_stop = false;
            self.anim_loop = true;
        }
        switch (self.state) {
            .death => {},
            .fade_in => {},
            .fade_out => {},
            else => {},
        }

        if (self.anim_loop and try self.as.isOver(self.anim)) {
            try self.as.reset(self.anim);
        }
        self.as.update(ctx.deltaSeconds());
    }

    pub fn draw(self: *Self, ctx: jok.Context) !void {
        _ = ctx;

        try j2d.sprite(try self.as.getCurrentFrame(self.anim), .{
            .pos = .{
                .x = @floatFromInt(self.current_pos.x * 32 + 16 - 18),
                .y = @floatFromInt(self.current_pos.y * 32 + 16 - (50 - 16)),
            },
            .depth = 0.8,
        });
    }
};

const State = enum {
    idle,
    death,
    fade_in,
    fade_out,
    left,
    right,
    up,
    down,
};

const MapPos = struct {
    x: usize,
    y: usize,
};
