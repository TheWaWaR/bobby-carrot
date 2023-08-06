const std = @import("std");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const mem = std.mem;
const Animation = j2d.AnimationSystem.Animation;
const MapInfo = @import("game.zig").MapInfo;

const Self = @This();

state: State,
next_state: ?State = null,
start_time: f32,
last_action_time: f32,
current_pos: sdl.PointF,
current_coord: Coordinate,
moving_target: ?Coordinate = null,
map_data: []u8,
carrot_total: usize,
egg_total: usize,
as: *j2d.AnimationSystem,
anim: *Animation,

carrot_count: usize = 0,
egg_count: usize = 0,
key_gray: usize = 0,
key_yellow: usize = 0,
key_red: usize = 0,
faded_out: bool = false,
dead: bool = false,

pub fn new(start_time: f32, map_info: MapInfo, as: *j2d.AnimationSystem) Self {
    const current_coord = .{ .x = map_info.start_idx % 16, .y = map_info.start_idx / 16 };
    const pos_x: f32 = @floatFromInt(current_coord.x * 32 + 16 - 18);
    const pos_y: f32 = @floatFromInt(current_coord.y * 32 + 16 - (50 - 16));
    return .{
        .current_pos = .{ .x = pos_x, .y = pos_y },
        .current_coord = current_coord,
        .start_time = start_time,
        .last_action_time = start_time,
        .state = .fade_in,
        .map_data = @constCast(map_info.data()),
        .carrot_total = map_info.carrot_total,
        .egg_total = map_info.egg_total,
        .as = as,
        .anim = as.animations.getPtr("fade_in").?,
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
        if (self.state != .death and self.state != .fade_in and self.state != .fade_out // current state
        and self.next_state != .death and self.next_state != .fade_out // next state
        ) {
            const next_state: ?State = switch (key.scancode) {
                .left => .left,
                .right => .right,
                .up => .up,
                .down => .down,
                else => null,
            };
            if (next_state) |state| {
                self.next_state = state;
            }
        }
    }
}

pub fn update(self: *Self, ctx: jok.Context) !void {
    if (ctx.seconds() - self.last_action_time >= 4.0 and self.state != .idle) {
        self.updateState(.idle);
    }

    const old_pos = self.current_pos;
    self.updateMovingTarget(ctx);
    self.handleMoving();

    // change camera position
    if ((old_pos.x != self.current_pos.x or old_pos.y != self.current_pos.y) and self.state != .death) {
        // TODO
    }
}

pub fn draw(self: *Self, ctx: jok.Context) !void {
    const sprite = if (self.state == .left or self.state == .right or self.state == .up or self.state == .down) blk: {
        if (self.moving_target == null) {
            break :blk self.anim.frames[self.anim.frames.len - 1];
        } else {
            break :blk self.anim.getCurrentFrame();
        }
    } else self.anim.getCurrentFrame();
    std.log.debug(
        "Bobby anim: name={s}, play_index={}, is_over={}",
        .{ self.anim.name, self.anim.play_index, self.anim.is_over },
    );
    switch (self.state) {
        .death => {
            if (self.anim.is_over) {
                self.anim.reset();
                self.dead = true;
            } else if (self.anim.play_index == self.anim.frames.len - 1) {
                self.anim.frame_interval = 1.0 / 2.0;
            }
        },
        .fade_in => {
            if (self.anim.is_over) {
                self.anim.reset();
                self.updateState(.down);
            }
        },
        .fade_out => {
            if (self.anim.is_over) {
                self.anim.reset();
                self.faded_out = true;
            }
        },
        else => {},
    }
    try j2d.sprite(sprite, .{ .pos = self.current_pos, .depth = 0.2 });

    self.anim.update(ctx.deltaSeconds());
}

fn isFinished(self: *Self) bool {
    if (self.carrot_total > 0) {
        return self.carrot_count == self.carrot_total;
    } else {
        return self.egg_count == self.egg_total;
    }
}

fn updateState(self: *Self, state: State) void {
    const name = switch (state) {
        .left => "bobby_left",
        .right => "bobby_right",
        .up => "bobby_up",
        .down => "bobby_down",
        .idle => "bobby_idle",
        .fade_in => "fade_in",
        .fade_out => "fade_out",
        .death => "bobby_death",
    };
    self.state = state;
    self.anim = self.as.animations.getPtr(name).?;
}

fn updateMovingTarget(self: *Self, ctx: jok.Context) void {
    if (self.next_state) |next_state| {
        if (self.moving_target == null) {
            const x = self.current_coord.x;
            const y = self.current_coord.y;
            switch (next_state) {
                .left => {
                    if (x > 0) {
                        self.moving_target = .{ .x = x - 1, .y = y };
                        self.updateState(.left);
                    }
                },
                .right => {
                    if (x < 15) {
                        self.moving_target = .{ .x = x + 1, .y = y };
                        self.updateState(.right);
                    }
                },
                .up => {
                    if (y > 0) {
                        self.moving_target = .{ .x = x, .y = y - 1 };
                        self.updateState(.up);
                    }
                },
                .down => {
                    if (y < 15) {
                        self.moving_target = .{ .x = x, .y = y + 1 };
                        self.updateState(.down);
                    }
                },
                else => {},
            }
            self.next_state = null;
        }

        if (self.moving_target) |moving_target| {
            self.last_action_time = ctx.seconds();
            const old_item = self.map_data[self.current_coord.index()];
            const new_item = self.map_data[moving_target.index()];
            if (new_item < 18 // normal block
            or (new_item == 33 and self.key_gray == 0) // lock gray
            or (new_item == 35 and self.key_yellow == 0) // lock yellow
            or (new_item == 37 and self.key_red == 0) // lock red
            or (new_item == 24 and (self.state == .right or self.state == .down)) // forbid: right + down
            or (new_item == 25 and (self.state == .left or self.state == .down)) // forbid: left + down
            or (new_item == 26 and (self.state == .left or self.state == .up)) // forbid: left + up
            or (new_item == 27 and (self.state == .right or self.state == .up)) // forbid: right + up
            or ((new_item == 28 or new_item == 40 or new_item == 41) and (self.state == .up or self.state == .down)) // forbid: up + down
            or ((new_item == 29 or new_item == 42 or new_item == 43) and (self.state == .left or self.state == .right)) // forbid: left + right
            or (new_item == 40 and self.state == .right) // forbid: right
            or (new_item == 41 and self.state == .left) // forbid: left
            or (new_item == 42 and self.state == .down) // forbid: down
            or (new_item == 43 and self.state == .up) // forbid: up
            or (new_item == 46) // egg
            or (old_item == 24 and (self.state == .left or self.state == .up)) // forbid: left + up
            or (old_item == 25 and (self.state == .right or self.state == .up)) // forbid: right + up
            or (old_item == 26 and (self.state == .right or self.state == .down)) // forbid: right + down
            or (old_item == 27 and (self.state == .left or self.state == .down)) // forbid: left + down
            or ((old_item == 28 or old_item == 40 or old_item == 41) and (self.state == .up or self.state == .down)) // forbid: up + down
            or ((old_item == 29 or old_item == 42 or old_item == 43) and (self.state == .left or self.state == .right)) // forbid: left + right
            or (old_item == 40 and self.state == .right) // forbid: right
            or (old_item == 41 and self.state == .left) // forbid: left
            or (old_item == 42 and self.state == .down) // forbid: down
            or (old_item == 43 and self.state == .up) // forbid: up
            ) {
                self.moving_target = null;
            } else {
                if (new_item == 31) {
                    self.next_state = .death;
                }
            }
        }
    }
}

fn handleMoving(self: *Self) void {
    if (self.moving_target) |moving_target| {
        const cx: f32 = @floatFromInt(self.current_coord.x);
        const cy: f32 = @floatFromInt(self.current_coord.y);
        const tx: f32 = @floatFromInt(moving_target.x);
        const ty: f32 = @floatFromInt(moving_target.y);
        if (self.next_state == .death and self.anim.play_index >= 4) {
            self.updateState(.death);
            const x = (tx - cx) / 2.0 + cx;
            const y = (ty - cy) / 2.0 + cy;
            self.current_pos.x = 32.0 * (x + 0.5) - 44.0 / 2.0;
            self.current_pos.y = 32.0 * (y + 0.5) - (54.0 - 32.0 / 2.0);
            self.anim.frame_interval = 1.0 / 10.0;
            self.moving_target = null;
            self.next_state = null;
        } else {
            const dp: f32 = 32.0 / 12.0;
            const target_x: f32 = 32.0 * (tx + 0.5) - 18.0;
            const target_y: f32 = 32.0 * (ty + 0.5) - (50.0 - 16.0);
            const old_coord = self.current_coord;
            if (moving_target.x > self.current_coord.x) {
                self.current_pos.x += dp;
                if (self.current_pos.x >= target_x) {
                    self.current_pos.x = target_x;
                    self.current_coord.x = moving_target.x;
                    self.moving_target = null;
                }
            } else if (moving_target.x < self.current_coord.x) {
                self.current_pos.x -= dp;
                if (self.current_pos.x <= target_x) {
                    self.current_pos.x = target_x;
                    self.current_coord.x = moving_target.x;
                    self.moving_target = null;
                }
            } else if (moving_target.y > self.current_coord.y) {
                self.current_pos.y += dp;
                if (self.current_pos.y >= target_y) {
                    self.current_pos.y = target_y;
                    self.current_coord.y = moving_target.y;
                    self.moving_target = null;
                }
            } else if (moving_target.y < self.current_coord.y) {
                self.current_pos.y -= dp;
                if (self.current_pos.y <= target_y) {
                    self.current_pos.y = target_y;
                    self.current_coord.y = moving_target.y;
                    self.moving_target = null;
                }
            }

            if (self.moving_target == null) {
                const old_idx = old_coord.index();
                const new_idx = self.current_coord.index();
                switch (self.map_data[old_idx]) {
                    24 => self.map_data[old_idx] = 25,
                    25 => self.map_data[old_idx] = 26,
                    26 => self.map_data[old_idx] = 27,
                    27 => self.map_data[old_idx] = 24,
                    28 => self.map_data[old_idx] = 29,
                    29 => self.map_data[old_idx] = 28,
                    30 => self.map_data[old_idx] = 31,
                    45 => {
                        self.map_data[old_idx] = 46;
                        self.egg_count += 1;
                    },
                    else => {},
                }
                switch (self.map_data[new_idx]) {
                    // get carrot
                    19 => {
                        self.map_data[new_idx] = 20;
                        self.carrot_count += 1;
                    },
                    // red switch
                    22 => {
                        for (self.map_data, 0..) |item, idx| {
                            switch (item) {
                                // switch
                                22 => self.map_data[idx] = 23,
                                23 => self.map_data[idx] = 22,
                                // right angle
                                24 => self.map_data[idx] = 25,
                                25 => self.map_data[idx] = 26,
                                26 => self.map_data[idx] = 27,
                                27 => self.map_data[idx] = 24,
                                // line
                                28 => self.map_data[idx] = 29,
                                29 => self.map_data[idx] = 28,
                                else => {},
                            }
                        }
                    },
                    // TODO: dead
                    31 => {},
                    // gray lock
                    32 => {
                        self.key_gray += 1;
                        self.map_data[new_idx] = 18;
                    },
                    33 => {
                        if (self.key_gray > 0) {
                            self.key_gray -= 1;
                            self.map_data[new_idx] = 18;
                        }
                    },
                    // yellow lock
                    34 => {
                        self.key_yellow += 1;
                        self.map_data[new_idx] = 18;
                    },
                    35 => {
                        if (self.key_yellow > 0) {
                            self.key_yellow -= 1;
                            self.map_data[new_idx] = 18;
                        }
                    },
                    // red lock
                    36 => {
                        self.key_red += 1;
                        self.map_data[new_idx] = 18;
                    },
                    37 => {
                        if (self.key_red > 0) {
                            self.key_red -= 1;
                            self.map_data[new_idx] = 18;
                        }
                    },
                    // yellow switch
                    38 => {
                        for (self.map_data, 0..) |item, idx| {
                            switch (item) {
                                38 => self.map_data[idx] = 39,
                                39 => self.map_data[idx] = 38,
                                40 => self.map_data[idx] = 41,
                                41 => self.map_data[idx] = 40,
                                42 => self.map_data[idx] = 43,
                                43 => self.map_data[idx] = 42,
                                else => {},
                            }
                        }
                    },
                    // flow
                    40 => self.next_state = .left,
                    41 => self.next_state = .right,
                    42 => self.next_state = .up,
                    43 => self.next_state = .down,
                    44 => {
                        if (self.isFinished()) {
                            self.updateState(.fade_out);
                            self.next_state = null;
                            // TODO: play audio
                        }
                    },
                    else => {},
                }
            }
        }
    }
}

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

const Coordinate = struct {
    x: usize,
    y: usize,
    fn index(coord: Coordinate) usize {
        return coord.x + coord.y * 16;
    }
};
