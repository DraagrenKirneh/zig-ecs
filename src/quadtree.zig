const std = @import("std");
const testing = std.testing;

const Vec2f = struct {
    x: f32,
    y: f32,
};

pub const Area = struct {
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

const Quadrant = enum(usize) {
    North_West = 0,
    North_East = 1,
    South_West = 2,
    South_East = 3,
};


pub fn QuadTree(comptime T: type, comptime maxDepth: usize, comptime threshold: usize) type {
    const List = std.ArrayList(T);
    const Map = std.AutoHashMap(T, Area);
    const Allocator = std.mem.Allocator;
    return struct {
        allocator: Allocator,
        map: Map,
        root: *Node,
        area: Area,
        
        const Self = @This();

        const Node = struct {
            values: List,
            children: ?[4] *Node = null,
        };

        pub fn init(allocator: std.mem.Allocator, area: Area) !Self {
            var node = try allocator.create(Node);
            node.values = try List.initCapacity(allocator, threshold);
            node.children = null;
            return Self{
                .area = area,
                .allocator = allocator,                
                .map = Map.init(allocator),
                .root = node,
            };
        }

        fn add(self: *Self, value: T, area: Area) !void {
            var current_area = self.area;
            var depth: usize = 0;
            var node: *Node = self.root; 

            while (depth < maxDepth) : (depth += 1) {
                if(node.children == null) {
                    if (node.values.items.len < threshold) {
                        break;
                    } else {
                        try self.split(node, current_area);
                    }
                } 
                const quadrant = current_area.getQuadrant(area);
                if (quadrant) | quad | {
                    current_area = current_area.computeArea(quad);
                    const quadIndex = @enumToInt(quad);                    
                    node = node.children.?[quadIndex];
                } else { 
                    break;                    
                }                
            }            
            try node.values.append(value);
            try self.map.put(value, area);
        }

        pub fn query(self: *Self, area: Area, count: usize) ![]T {
            var values: List = try List.initCapacity(self.allocator, count);

            self.queryNode(self.root, self.area, area, &values);
            return values.toOwnedSlice();
        }

        fn queryNode(self: *Self, node: *Node, scanArea: Area, queryArea: Area, list: *List) void {
            for (node.values.items) | each | {
                const value_area = self.map.get(each).?;
                if(queryArea.intersects(value_area)) {
                    list.appendAssumeCapacity(each);
                    if (list.items.len == list.capacity) return;
                }
            }
            if (node.children) | children | {
                for (children) | child, index | {
                    var new_area = scanArea.computeArea(@intToEnum(Quadrant, index));
                    if (queryArea.intersects(new_area)) {
                        self.queryNode(child, new_area, queryArea, list);
                    }
                }
            }            
        }

        pub fn split(self: *Self, node: *Node, area: Area) !void {
            var children: [4]*Node = undefined;
            for (children) | _, index | {
                var new_node = try self.allocator.create(Node);
                new_node.values = try List.initCapacity(self.allocator, threshold);
                new_node.children = null;
                children[index] = new_node;
            }
            node.children = children;
            var index: usize = 1;
            const end = node.values.items.len;
            while (index <= end) : (index += 1) {
                const value = node.values.items[end - index];
                const value_area = self.map.get(value).?;
                std.debug.assert(area.contains(value_area));
                if (value_area.getQuadrant(area)) | quad | {
                    const quadIndex = @enumToInt(quad);
                    node.children.?[quadIndex].values.appendAssumeCapacity(value);
                    _ = node.values.swapRemove(end - index);
                }
            }
            std.debug.assert(node.children != null);
        }
    };
}

test "basic add functionality" {
    std.testing.log_level = .debug;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    std.debug.print("\n", .{ });
    try testing.expect(add(3, 7) == 10);
    const QTree = QuadTree(usize, 8, 30);
    var tree = try QTree.init(alloc, .{ .left = 0, .top = 0, .width = 900, .height = 900 });
    
    var ix: usize = 1;
    while (ix <= 50) : ( ix += 1) {
        try tree.add(ix, .{ .left = 10 * @intToFloat(f32,ix), .top = 10 * @intToFloat(f32,ix), .width = 10, .height = 10});
    }    

    var result = try tree.query(Area.init(5, 5, 20, 20), 10);
    for (result) | each | {
        std.debug.print("found: {}\n", .{ each });
    }
    try std.testing.expect(result.len > 0);
   // defer tree.deinit();
}
