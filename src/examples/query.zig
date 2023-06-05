const std = @import("std");
const ecs = @import("ecs");
const math = ecs.math;
const Rectangle = math.Rectangle;

const QuadTree = ecs.math.QuadTree(ecs.EntityID, 30, 8);

pub const GameState = struct { done: bool = false, width: f32, height: f32 };

const Components = struct {
    id: ecs.EntityID,
    position: math.Vec2f,
    size: math.Vec2f,
    range: f32,
};

pub const Entities = ecs.Entities(Components);
pub const Context = ecs.Context(GameState, Entities);

const SpatialQueryIndex = struct {
    pub fn generate(context: *Context) !*QuadTree {
        const view = Rectangle.initBasic(0, 0, 1200, 800);
        var tree = try context.allocator.create(QuadTree);
        tree.* = QuadTree.init(context.allocator, view);

        var iterator = context.getIterator(Query);
        while (iterator.next()) |each| {
            var item_area = Rectangle.init(each.position, each.size);
            try tree.add(each.id, item_area);
        }

        return tree;
    }

    const Query = struct {
        id: ecs.EntityID,
        position: math.Vec2f,
        size: math.Vec2f,
    };
};

const ExampleQuerySystem = struct {
    range: f32,
    position: math.Vec2f,

    const Self = @This();

    pub fn step(self: Self, context: *Context) !void {
        const tree: *QuadTree = try context.getPerFrameCachedPtr(SpatialQueryIndex, QuadTree, SpatialQueryIndex.generate);
        const area = math.Rectangle.initBasic(self.position.x, self.position.y, self.range, self.range);
        const entries = try tree.query(area, 10);
        std.debug.print("\nstep: {}\n", .{entries.len});
    }
};

const BoxTemplate = struct {
    position: math.Vec2f,
    size: math.Vec2f = .{ .x = 100, .y = 100 },
};

const World = ecs.World(Context, &.{ExampleQuerySystem});

test "test spatial query" {
    std.testing.log_level = .debug;
    var allocator = std.testing.allocator;

    var globalState = try allocator.create(GameState);
    defer allocator.destroy(globalState);

    globalState.* = GameState{ .width = 1200, .height = 800, .done = false };

    var world = try World.init(allocator, globalState);
    defer world.deinit();

    _ = try world.entites.create(BoxTemplate, .{
        .position = .{ .x = 0, .y = 0 },
    });
    _ = try world.entites.create(BoxTemplate, .{
        .position = .{ .x = 100, .y = 100 },
    });
    _ = try world.entites.create(BoxTemplate, .{
        .position = .{ .x = 200, .y = 0 },
    });
    _ = try world.entites.create(BoxTemplate, .{
        .position = .{ .x = 0, .y = 200 },
    });

    const entity = try world.entites.new();
    try world.entites.setComponent(entity, .position, .{ .x = 0, .y = 0 });
    try world.entites.setComponent(entity, .range, 20);

    var pipeline = try world.createPipeline();

    try pipeline.run(.step);

    var pipeline2 = try world.createPipeline();
    try pipeline2.run(.step);
}

const Op = enum(u2) {
    mix,
    shift,
    mul,

    inline fn do(comptime op: Op, data: *Data, value: usize) {
        return @call(.auto, @field(Data, @tagName(op)), if (op == .mix) .{value} else .{});
    }
};

inline fn eval(comptime ops: []const Op, data: *Data, value: usize) void {
   ;
}

const Algorithm = enum {
    a,
    b,

    inline fn operations(comptime self: Algorithm) []const Op {
        return switch (self) { 
            .a => .{ .mix, .shift, .mul },
            .b => .{ .shift, .mix, .mul },
        };
    }

    fn eval(self: Algorithm, data: *Data, value: usize) void {
        inline for (std.meta.tags(Algorithm)) | tag | {
            if (tag == self) {
                inline for (tag.toperations()) |op| op.do(data, value);
        }
    }
};
