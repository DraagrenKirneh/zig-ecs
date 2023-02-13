const std = @import("std");
const math = std.math;

pub fn Vec2(comptime T: type) type {
    return struct {
        x: T,
        y: T,
    };
}

pub const Vec2i = Vec2(i32);

pub const Vec2f = struct {
    x: f32,
    y: f32,

    const Self = @This();

    pub fn init(x: f32, y: f32) Self {
        return .{
            .x = x,
            .y = y,
        };
    }

    pub inline isInRadius(self: Self, other: Self, radius: f32) bool {
        return self.distanceSquared(other) < radius * radius;
    }

    pub inline fn sub(self: Self, other: Self) Self {
        return .{
            .x = self.x - other.x,
            .y = self.y - other.y
        };
    }

    pub inline fn add(self: Self, other: Self) Self {
        return .{
            .x = self.x + other.x,
            .y = self.y + other.y
        }; 
    }

    pub fn move(self: Self, target: Self, speed: f32) Self {
        const distx = target.x - self.x;
	    const disty = target.y - self.y;
	    const angle = math.atan2(f32, disty, distx);

        return .{
            .x = self.x + (speed * math.cos(f32, angle)),
            .y = self.y + (speed * math.sin(f32, angle))
        }

	    // check for next point
	    //return (distx < 0 ? -distx : distx) + (disty < 0 ? -disty : disty) < 2;
    }
    
    pub fn at(x: f32, y: f32) Self {
        return .{ .x = x, .y = y };
    }

    pub inline fn length(self: Self) f32 {
        return math.sqrt(self.x * self.x + self.y * self.y);
    }

    pub inline fn theta(self: Self) f32 {
        return math.atan2(f32, self.y, self.x);
    }

    pub inline fn unit(self: Self) Self {
        const b = 1.0 / self.length();
        return .{ 
            .x = self.x * b,
            .y = self.y * b,
        };
    }

    pub inline fn normalize(self: Self) Self {
        const invmag: f32 = 1.0 / self.length();
        return .{
            .x = self.x * invmag,
            .y = self.y * invmag,
        };
    }

    //checkme
    pub inline fn isNear(self: Self, other: Self, radius: f32) bool {
        return radius < self.distance(other);
    }

    pub inline fn lerp(self: Self, other: Self, t: f32) Self {
        return .{
            .x = t * other.x + (1 - t) * self.x,
            .y = t * other.y + (1 - t) * self.y,
        };
    }
    
    pub inline fn manhattan_length(self: Self) f32 {
        return self.x + self.y;
    }

    pub inline fn dot(self: Self, other: Self) f32 {
        return self.x * other.x + self.y * other.y;
    }

    pub inline fn cross(self: Self, other: Self) f32 {
        return self.x * other.y - self.y * other.x;
    }

    pub inline fn angleTo(self: Self, other: Self) f32 {
        const dox = other.x - self.x;
        const doy = other.y - self.y;
        //return math.atan2(f32, doy, dox);
        return math.atan2(f32, dox, doy);
    }

    pub inline fn perp_prod(self: Self, other: Self) f32 {
        return self.x * other.y - other.x * self.y;
    }

    pub inline fn distance(self: Self, other: Self) f32 {
        return math.sqrt(self.distanceSquared(other));
    }

    pub inline fn distanceSquared(self: Self, other: Self) f32 {
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

fn expectEqual(comptime T: type, expected: T, actual: T) !void {
    return std.testing.expectEqual(expected, actual);
}

test "at" {
    var p = Vec2f.at(1, 2);
    try expectEqual(f32, 1, p.x);
    try expectEqual(f32, 2, p.y);
}

test "unit" {
    var p = Vec2f.at(1, 2);
    var unit = p.unit();

    try std.testing.expect(p.x != unit.x);
}

test "length" {
    var p1 = Vec2f.at(10, 10);
    var p2 = Vec2f.at(10, 20);

    var len = p1.distance(p2);
    try std.testing.expect(len == 10);
}
