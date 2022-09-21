const std = @import("std");
const testing = std.testing;
const rectangle = @import("Rectangle.zig");
const Vec2f = @import("Vec2.zig").Vec2f;
const Area = rectangle.Rectangle;
const Quadrant = rectangle.Quadrant;

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

        pub fn add(self: *Self, value: T, area: Area) !void {
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

        fn split(self: *Self, node: *Node, area: Area) !void {
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
    const QTree = QuadTree(usize, 8, 30);
    var tree = try QTree.init(alloc, Area.initBasic(0, 0, 900, 900));
    
    var ix: usize = 1;
    while (ix <= 50) : ( ix += 1) {
        const nextArea = Area.initBasic(10 * @intToFloat(f32,ix), 10 * @intToFloat(f32,ix), 10, 10);
        try tree.add(ix, nextArea);
    }    

    var result = try tree.query(Area.initBasic(5, 5, 20, 20), 10);
    for (result) | each | {
        std.debug.print("found: {}\n", .{ each });
    }
    try std.testing.expect(result.len > 0);
   // defer tree.deinit();
}
