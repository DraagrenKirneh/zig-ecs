const std = @import("std");
const testing = std.testing;

const Vec2f = struct {
    x: f32,
    y: f32,
};

const Area = struct {
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

    pub inline fn center(self: Self) Vec2f {
        return .{ self.right() / 2, self.bottom() / 2 };
    }

    pub inline fn size(self: Self) Vec2f {
        return .{ self.width, self.height };
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
            or self.bottom <= other.top);
        
    }

    pub inline computeArea(self: Self, Quadrant quadrant) Self {
        const halfWidth = self.width / 2;
        const halfHeight = self.height / 2;
        return switch(quadrant) {
            .North_West => Self.init(self.left, self.top, halfWidth, halfHeight),
            .North_East => Self.init(self.left + halfWidth, self.top, halfWidth, halfHeight),
            .South_West => Self.init(self.left, self.top + halfHeight, halfWidth, halfHeight),
            .South_East => Self.init(self.left + halfWidht, self.top + halfHeight, halfWidth, halfHeight),
        }
    }

    pub inline fn quadrant(self: Self, other: Self) ?Quadrant {
        const middle = self.center();
        
        if (other.right() < middle.x) {
            if (other.bottom() < middle.y) return Quadrant.North_West;
            if (other.top >= middle.y) return Quadrant.South_West;
            return null;
        }
        if (other.left >= middle.x) {
            if (other.bottom < middle.y) return Quadrant.North_East;
            if (other.top >= middle.y) return Quadrant.South_East;
            return null;
        }
        return null;
    }

};

const Quadrant = enum {
    North_West,
    North_East,
    South_West,
    South_East,
};


pub fn QuadTree(comptime T: type, maxDepth: usize, threshold: usize) type {
    const List = std.ArrayList(T);
    return struct {
        allocator: std.mem.Allocator,
        root: Node,
        area: Area,
        
        const Self = @This();

        const Node = struct {
            values: List,
            children: ?*[4] Node,
        };

        pub fn init(allocator: std.mem.Allocator, area: Area) !Self {
            return .{
                .allocator = allocator,
                .area = area,
                .root = try List.initCapacity(allocator, 20),
            };
        }


        fn add(self: Self, value: T) !void {
            var area = self.area;
            var depth = 0;
            var node: *Node = &self.node; 

            while (depth < maxDepth) : (depth += 1) {
                if(node.children == null) {
                    if (node.values.len < threshold) {
                        try node.values.append(value);
                        return;
                    } else {
                        self.split(node, area);
                    }
                } 
                const quadrant = area.quadrant();
                if (quadrant) | quad | {
                    area = area.computeArea(quad);
                    node = node.children[@enumToInt(usize, quad)];
                } else { 
                    try node.values.append(value);
                    return;
                }
                
            }            
            try node.values.append(value);

        }

        pub fn split(self: Self, node: *Node, area: Area) !void {
            node.children = self.allocator.alloc(Node, 4);
            for (node.children) | each {
                each.values = try List.initCapacity(allocator, threshold);
            }
            var index: usize = 1;
            const end = node.children.len;
            while (index <= end) : (index += 1) {
                const quad = 
            }
        }
    };
}

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test "basic add functionality" {
    const alloc = std.testing.allocator;
    try testing.expect(add(3, 7) == 10);
    const QTree = QuadTree(usize);
    var tree = try QTree.init(alloc, .{ .left = 0, .top = 0, .width = 200, .height = 200 });
    _ = tree;
   // defer tree.deinit();
}
