const std = @import("std");
const jok = @import("jok");
const sdl = jok.sdl;
const j2d = jok.j2d;
const zaudio = jok.zaudio;
const mem = std.mem;
const Animation = j2d.AnimationSystem.Animation;
const MapInfo = @import("./Map.zig").MapInfo;

const Self = @This();

state: State,
next_state: ?State = null,
start_time: f32,
last_action_time: f32,
last_laser_time: ?f32 = null,
current_pos: sdl.PointF,
current_coord: Coordinate,
moving_target: ?Coordinate = null,
ice_block_coord: ?Coordinate = null,
map_data: []u8,
carrot_total: usize,
as: *j2d.AnimationSystem,
anim: *Animation,
sfx_end: *zaudio.Sound,

carrot_count: usize = 0,
key_gray: usize = 0,
key_yellow: usize = 0,
key_red: usize = 0,
faded_out: bool = false,
dead: bool = false,
slip: bool = false,

// TODO: action when melt a ice block
// TODO: move camera smoothly

pub fn new(
    start_time: f32,
    map_info: MapInfo,
    as: *j2d.AnimationSystem,
    sfx_end: *zaudio.Sound,
) Self {
    const current_coord = .{
        .x = map_info.start_idx % 16,
        .y = map_info.start_idx / 16,
    };
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
        .as = as,
        .sfx_end = sfx_end,
        .anim = as.animations.getPtr("fade_in").?,
    };
}

pub fn event(self: *Self, ctx: jok.Context, e: sdl.Event) !void {
    _ = self;
    _ = ctx;
    _ = e;
}

pub fn update(self: *Self, ctx: jok.Context) !bool {
    if (self.moving_target == null and self.ice_block_coord == null and !self.slip) {
        const state_opt: ?State = if (ctx.isKeyPressed(.left) or ctx.isKeyPressed(.a)) .left // left
        else if (ctx.isKeyPressed(.right) or ctx.isKeyPressed(.d)) .right // right
        else if (ctx.isKeyPressed(.up) or ctx.isKeyPressed(.w)) .up // up
        else if (ctx.isKeyPressed(.down) or ctx.isKeyPressed(.s)) .down //down
        else null;
        if (state_opt) |state| {
            if (self.state != .death and self.state != .fade_in and self.state != .fade_out // current state
            and self.next_state != .death and self.next_state != .fade_out // next state
            ) {
                self.next_state = state;
            }
        }
    }

    if (ctx.seconds() - self.last_action_time >= 4.0 and self.state != .idle) {
        self.updateState(.idle);
    }

    const old_ice_block_coord = self.ice_block_coord;
    const old_pos = self.current_pos;
    if (self.next_state) |next_state| {
        self.updateMovingTarget(ctx, next_state);
    }
    if (self.moving_target) |moving_target| {
        try self.handleMoving(moving_target);
    }

    var ice_block_coord_changed = !std.meta.eql(old_ice_block_coord, self.ice_block_coord);
    if (ice_block_coord_changed) {
        if (self.ice_block_coord == null) {
            self.last_laser_time = null;
        } else {
            self.last_laser_time = ctx.seconds();
        }
    }
    if (self.ice_block_coord) |coord| {
        if (self.last_laser_time) |start| {
            const delta = ctx.seconds() - start;
            if (delta > 1.6) {
                self.map_data[coord.index()] = 63;
                self.ice_block_coord = null;
                self.last_laser_time = null;
                ice_block_coord_changed = true;
            } else if (delta > 1.2) {
                self.map_data[coord.index()] = 62;
            } else if (delta > 0.8) {
                self.map_data[coord.index()] = 61;
            } else if (delta > 0.4) {
                self.map_data[coord.index()] = 60;
            }
        }
    }

    // change camera position
    return (ice_block_coord_changed //
    or !std.meta.eql(old_pos, self.current_pos)) //
    and self.state != .death;
}

pub fn draw(self: *Self, ctx: jok.Context) !void {
    const sprite = if (self.state == .left or self.state == .right or self.state == .up or self.state == .down) blk: {
        if (self.slip) {
            break :blk self.anim.frames[1];
        } else if (self.moving_target == null) {
            break :blk self.anim.frames[self.anim.frames.len - 1];
        } else {
            const frame = self.anim.getCurrentFrame();
            self.anim.update(ctx.deltaSeconds());
            break :blk frame;
        }
    } else blk: {
        const frame = self.anim.getCurrentFrame();
        self.anim.update(ctx.deltaSeconds());
        break :blk frame;
    };
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
}

pub fn isFinished(self: *Self) bool {
    return self.carrot_count == self.carrot_total;
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

fn updateMovingTarget(self: *Self, ctx: jok.Context, next_state: State) void {
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
        const old_item = self.map_data[self.current_coord.index()] & 0b0011_1111;
        const new_item = self.map_data[moving_target.index()] & 0b0011_1111;
        const state = self.state;
        if (new_item < 18 // normal block
        or (new_item == 33 and self.key_gray == 0) // lock gray
        or (new_item == 35 and self.key_yellow == 0) // lock yellow
        or (new_item == 37 and self.key_red == 0) // lock red
        or (new_item == 24 and (state == .right or state == .down)) // forbid: right + down
        or (new_item == 25 and (state == .left or state == .down)) // forbid: left + down
        or (new_item == 26 and (state == .left or state == .up)) // forbid: left + up
        or (new_item == 27 and (state == .right or state == .up)) // forbid: right + up
        or ((new_item == 28) and (state == .up or state == .down)) // forbid: up + down
        or ((new_item == 29) and (state == .left or state == .right)) // forbid: left + right
        or (new_item == 59) // ice block
        or (old_item == 24 and (state == .left or state == .up)) // forbid: left + up
        or (old_item == 25 and (state == .right or state == .up)) // forbid: right + up
        or (old_item == 26 and (state == .right or state == .down)) // forbid: right + down
        or (old_item == 27 and (state == .left or state == .down)) // forbid: left + down
        or ((old_item == 28) and (state == .up or state == .down)) // forbid: up + down
        or ((old_item == 29) and (state == .left or state == .right)) // forbid: left + right
        ) {
            self.slip = false;
            self.moving_target = null;
        } else {
            if (new_item == 31) {
                self.next_state = .death;
            }
        }
    }
}

fn handleMoving(self: *Self, moving_target: Coordinate) !void {
    const cx: f32 = @floatFromInt(self.current_coord.x);
    const cy: f32 = @floatFromInt(self.current_coord.y);
    const tx: f32 = @floatFromInt(moving_target.x);
    const ty: f32 = @floatFromInt(moving_target.y);
    if (self.next_state == .death and self.anim.play_index >= 4) {
        self.updateState(.death);
        const x = (tx - cx) / 2.0 + cx;
        const y = (ty - cy) / 2.0 + cy;
        self.current_pos.x = 32.0 * (x + 0.5) - 44.0 / 2.0;
        self.current_pos.y = 32.0 * (y + 0.5) - (48.0 - 32.0 / 2.0);
        self.anim.frame_interval = 1.0 / 10.0;
        self.moving_target = null;
        self.next_state = null;
    } else {
        const dp: f32 = 32.0 / 16.0;
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
            switch (self.map_data[old_idx] & 0b0011_1111) {
                24 => self.map_data[old_idx] = 25,
                25 => self.map_data[old_idx] = 26,
                26 => self.map_data[old_idx] = 27,
                27 => self.map_data[old_idx] = 24,
                28 => self.map_data[old_idx] = 29,
                29 => self.map_data[old_idx] = 28,
                30 => self.map_data[old_idx] = 31,
                // mirrors
                45 => self.map_data[old_idx] = 46,
                46 => self.map_data[old_idx] = 47,
                47 => self.map_data[old_idx] = 48,
                48 => self.map_data[old_idx] = 45,
                // ruby left
                49 => {
                    _ = fillLight(self.map_data, old_coord, .left, true);
                    self.ice_block_coord = null;
                },
                // ruby up
                50 => {
                    _ = fillLight(self.map_data, old_coord, .up, true);
                    self.ice_block_coord = null;
                },
                // ruby right
                51 => {
                    _ = fillLight(self.map_data, old_coord, .right, true);
                    self.ice_block_coord = null;
                },
                // ruby down
                52 => {
                    _ = fillLight(self.map_data, old_coord, .down, true);
                    self.ice_block_coord = null;
                },
                else => {},
            }
            switch (self.map_data[new_idx] & 0b0011_1111) {
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
                // full ice ground
                38 => {
                    self.next_state = self.state;
                    self.slip = true;
                },
                // down ice ground
                // x ice ground
                // up ice ground
                // right ice ground
                // y ice ground
                39, 40, 41, 42, 43 => {
                    self.slip = false;
                },
                // end circle
                44 => {
                    if (self.isFinished()) {
                        self.updateState(.fade_out);
                        self.next_state = null;
                        try self.sfx_end.start();
                    }
                },
                // ruby left
                49 => self.ice_block_coord = fillLight(self.map_data, self.current_coord, .left, false),
                // ruby up
                50 => self.ice_block_coord = fillLight(self.map_data, self.current_coord, .up, false),
                // ruby right
                51 => self.ice_block_coord = fillLight(self.map_data, self.current_coord, .right, false),
                // ruby down
                52 => self.ice_block_coord = fillLight(self.map_data, self.current_coord, .down, false),
                else => {},
            }
        }
    }
}

fn fillLight(map: []u8, start: Coordinate, dir: Direction, clear: bool) ?Coordinate {
    var coord = start;
    var direction = dir;
    while (true) {
        switch (direction) {
            // ruby left
            .left => {
                if (coord.x == 0) {
                    return null;
                }
                coord.x -= 1;
            },
            // ruby up
            .up => {
                if (coord.y == 0) {
                    return null;
                }
                coord.y -= 1;
            },
            // ruby right
            .right => {
                if (coord.x == 15) {
                    return null;
                }
                coord.x += 1;
            },
            // ruby down
            .down => {
                if (coord.y == 15) {
                    return null;
                }
                coord.y += 1;
            },
        }

        const old_direction: Direction = direction;
        switch (map[coord.index()] & 0b0011_1111) {
            // stop or change direction at mirrors
            45 => {
                switch (direction) {
                    .left => direction = .down,
                    .up => direction = .right,
                    else => return null,
                }
            },
            46 => {
                switch (direction) {
                    .right => direction = .down,
                    .up => direction = .left,
                    else => return null,
                }
            },
            47 => {
                switch (direction) {
                    .down => direction = .left,
                    .right => direction = .up,
                    else => return null,
                }
            },
            48 => {
                switch (direction) {
                    .down => direction = .right,
                    .left => direction = .up,
                    else => return null,
                }
            },
            // // TODO: stop at ruby
            // 49, 50, 51, 52 => return null,
            // stop at ice block
            59 => return coord,
            else => {},
        }

        if (clear) {
            map[coord.index()] &= 0b0011_1111;
        } else {
            const mark: u8 = switch (old_direction) {
                .up, .down => 0b0100_0000,
                .left, .right => 0b1000_0000,
            };
            map[coord.index()] |= mark;
        }
    }
}

const Direction = enum {
    left,
    right,
    up,
    down,
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

const Coordinate = struct {
    x: usize,
    y: usize,
    fn index(coord: Coordinate) usize {
        return coord.x + coord.y * 16;
    }
};
