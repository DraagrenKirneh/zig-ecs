const std = @import("std");
const Vec2f = @import("Vec2.zig").Vec2f;

pub const Rectangle = struct {
    position: Vec2f,
    size: Vec2f,
    
    const Self = @This();

    pub fn initBasic(x: f32, y: f32, width: f32, height: f32) Self {
        return init(.{ .x = x, .y = y }, .{ .x = width, .y = height });
    }

    pub fn init(position: Vec2f, size: Vec2f) Self {
        return .{
            .position = position,
            .size = size,
        };
    }

    pub inline fn left(self: Self) f32 {
        return self.position.x;
    }

    pub inline fn top(self: Self) f32 {
        return self.position.y;
    }

    pub inline fn right(self: Self) f32 {
        return self.position.x + self.size.x;
    }

    pub inline fn bottom(self: Self) f32 {
        return self.position.y + self.size.y;
    }

    pub inline fn getCenter(self: Self) Vec2f {
        return .{ .x = self.right() / 2, .y = self.bottom() / 2 };
    }

    pub inline fn contains(self: Self, other: Self) bool {
        return self.left() <= other.left()
            and other.right() <= self.right()
            and self.top() <= other.top() 
            and other.bottom() <= other.bottom();
    }

    pub inline fn intersects(self: Self, other: Self) bool {
        return ! (self.left() >= other.right()
            or self.right() <= other.left() 
            or self.top() >= other.bottom()
            or self.bottom() <= other.top());        
    }

    pub inline fn computeArea(self: Self, quadrant: Quadrant) Self {
        const halfWidth = self.size.x / 2;
        const halfHeight = self.size.y / 2;
        return switch(quadrant) {
            .North_West => Self.initBasic(self.left(),             self.top(),               halfWidth, halfHeight),
            .North_East => Self.initBasic(self.left() + halfWidth, self.top(),               halfWidth, halfHeight),
            .South_West => Self.initBasic(self.left(),             self.top() + halfHeight,  halfWidth, halfHeight),
            .South_East => Self.initBasic(self.left() + halfWidth, self.top() + halfHeight,  halfWidth, halfHeight),
        };
    }

    pub inline fn getQuadrant(self: Self, valueArea: Self) ?Quadrant {
        const middle = self.getCenter();
        
        if (valueArea.right() < middle.x) {
            if (valueArea.bottom() < middle.y) return Quadrant.North_West;
            if (valueArea.top() >= middle.y) return Quadrant.South_West;
            return null;
        }
        if (valueArea.left() >= middle.x) {
            if (valueArea.bottom() < middle.y) return Quadrant.North_East;
            if (valueArea.top() >= middle.y) return Quadrant.South_East;
            return null;
        }
        return null;
    }
};

test "Rectangle" {
    const a = Rectangle.initBasic(0, 0, 100, 100);
    var b = Rectangle.initBasic(10, 10, 10, 10);
    
    try std.testing.expectEqual(a.getQuadrant(b), .North_West);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.position.x = 50;
    try std.testing.expectEqual(a.getQuadrant(b), .North_East);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.position.y = 50;
    try std.testing.expectEqual(a.getQuadrant(b), .South_East);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.position.x = 0;
    try std.testing.expectEqual(a.getQuadrant(b), .South_West);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.position.y = 45;
    b.position.x = 45;
    try std.testing.expectEqual(a.getQuadrant(b), null);
}

pub const Quadrant = enum(usize) {
    North_West = 0,
    North_East = 1,
    South_West = 2,
    South_East = 3,
};