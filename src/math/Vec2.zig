const std = @import("std");
const math = std.math;

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

//pub const Vec2f = Vec2(f32);
pub const Vec2i = Vec2(i32);

pub const Vec2f = struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub inline fn length(self: Self) f32 {
        return math.sqrt(f32, self.x * self.x + self.y * self.y);
    }

    pub inline fn theta(self: Self) f32 {
        return math.atan2(f32, y, x);
    }

    pub inline fn unit(self: Self) Self {
        const b = 1.0 / self.length();
        return .{ 
            .x = self.x * b,
            .y = self.y * b,
        };
    }

    pub inline fn dot(self: Self, other: Self) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub inline fn cross(self: Self, other: Self) f32 {
        return self.x * other.y - self.y * other.x;
    }

    pub inline fn angleTo(self: Self, other: Self) f32 {
        const dx = other.x - self.x;
        const dy = other.y - self.y;
        return math.atan2(f32, dy, dx);
    }

    pub inline fn distance(self: Self, other: Self) f32 {
        return math.sqrt(f32, self.distanceSquearedTo(other));
    }

    pub inline fn distanceSqueared(self: Self, other: Self) f32 {
        const dx = self.x - other.x;
        const dy = self.y - other.y;
        return dx * dx + dy * dy;
    }

    pub inline fn compareTo(self: Self, other: Self) math.Order {
        if (self.y < other.y) return .lt;
        if (self.y > other.y) return .gt;
        if (self.x < other.x) return .lt;
        if (self.x > other.x) return .gt;
        return .eq;
    }



};
