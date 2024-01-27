const std = @import("std");
const jok = @import("jok");
const sdl = jok.sdl;

// pub fn Version(M: anytype) type {
//     pub const Version = struct {
//         audio_dir: [:0]const u8,
//         image_dir: [:0]const u8,
//         level_dir: [:0]const u8,
//         current_level: usize,
//         map_info: M,

//         pub fn loadLevel(self: *Self, idx: usize) !void {
//             std.log.info("load level: {}", .{idx});
//         }

//         pub fn loadSprites(self: *Self) !void {
//             std.log.info("load sprites", .{});
//         }
//     };
// }

pub const V1MapInfo = struct {
    data_origin: []const u8,
    start_idx: usize,
    end_idx: usize,
    carrot_total: usize,
    egg_total: usize,

    const Self = @This();

    pub fn new() Self {
        return .{
            .data_origin = undefined,
            .start_idx = 0,
            .end_idx = 0,
            .carrot_total = 0,
            .egg_total = 0,
        };
    }

    pub fn data(self: *const Self) []const u8 {
        return self.data_origin[4..];
    }

    pub fn load(self: *Self, ctx: jok.Context, current_level: usize) !void {
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
