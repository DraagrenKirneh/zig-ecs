const std = @import("std");

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

pub const Vec2f = Vec2(f32);
pub const Vec2i = Vec2(i32);
