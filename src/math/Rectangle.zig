const std = @import("std");
const Vec2f = @import("Vec2.zig").Vec2f;

pub const Rectangle = struct {
    left: f32,
    top: f32,
    width: f32,
    height: f32,

    const Self = @This();

    pub fn init(left: f32, top: f32, width: f32, height: f32) Self {
        return .{
            .left = left,
            .top = top,
            .width = width,
            .height = height,
        };
    }

    pub inline fn right(self: Self) f32 {
        return self.left + self.width;
    }

    pub inline fn bottom(self: Self) f32 {
        return self.top + self.height;
    }

    pub inline fn getCenter(self: Self) Vec2f {
        return .{ .x = self.right() / 2, .y = self.bottom() / 2 };
    }

    pub inline fn size(self: Self) Vec2f {
        return .{ .x = self.width, .y = self.height };
    }

    pub inline fn contains(self: Self, other: Self) bool {
        return self.left <= other.left 
            and other.right() <= self.right()
            and self.top <= other.top 
            and other.bottom() <= other.bottom();
    }

    pub inline fn intersects(self: Self, other: Self) bool {
        return ! (self.left >= other.right()
            or self.right() <= other.left 
            or self.top >= other.bottom()
            or self.bottom() <= other.top);        
    }

    pub inline fn computeArea(self: Self, quadrant: Quadrant) Self {
        const halfWidth = self.width / 2;
        const halfHeight = self.height / 2;
        return switch(quadrant) {
            .North_West => Self.init(self.left,             self.top,               halfWidth, halfHeight),
            .North_East => Self.init(self.left + halfWidth, self.top,               halfWidth, halfHeight),
            .South_West => Self.init(self.left,             self.top + halfHeight,  halfWidth, halfHeight),
            .South_East => Self.init(self.left + halfWidth, self.top + halfHeight,  halfWidth, halfHeight),
        };
    }

    pub inline fn getQuadrant(self: Self, valueArea: Self) ?Quadrant {
        const middle = self.getCenter();
        
        if (valueArea.right() < middle.x) {
            if (valueArea.bottom() < middle.y) return Quadrant.North_West;
            if (valueArea.top >= middle.y) return Quadrant.South_West;
            return null;
        }
        if (valueArea.left >= middle.x) {
            if (valueArea.bottom() < middle.y) return Quadrant.North_East;
            if (valueArea.top >= middle.y) return Quadrant.South_East;
            return null;
        }
        return null;
    }
};

test "Area" {
    const a = Area.init(0, 0, 100, 100);
    var b = Area.init(10, 10, 10, 10);
    
    try std.testing.expectEqual(a.getQuadrant(b), .North_West);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.left = 50;
    try std.testing.expectEqual(a.getQuadrant(b), .North_East);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.top = 50;
    try std.testing.expectEqual(a.getQuadrant(b), .South_East);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.left = 0;
    try std.testing.expectEqual(a.getQuadrant(b), .South_West);
    try std.testing.expectEqual(b.getQuadrant(a), null);

    b.top = 45;
    b.left = 45;
    try std.testing.expectEqual(a.getQuadrant(b), null);
}

pub const Quadrant = enum(usize) {
    North_West = 0,
    North_East = 1,
    South_West = 2,
    South_East = 3,
};