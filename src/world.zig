const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const ecs = @import("ecs.zig");
const reflection = @import("reflection.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn World(comptime Context: type, comptime systems: []const type) type {
    const Resources = Context.ResourcesType;
    const Entites = Context.EntitesType;
    return struct {
        baseAllocator: Allocator,
        arena: ArenaAllocator,
        entites: Entites,
        resources: Resources,

        const Self = @This();
        const Pipeline = ecs.Pipeline(Context, systems);

        pub fn init(allocator: Allocator, resources: Resources) !Self {
            return Self{
                .resources = resources,
                .baseAllocator = allocator,
                .entites = Entites.init(allocator),
                .arena = ArenaAllocator.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entites.deinit();
            self.arena.deinit();
        }

        fn clearArena(self: *Self) void {
            self.arena.state.end_index = 0;
        }

        pub fn createPipeline(self: *Self) !Pipeline {
            self.clearArena();
            var alloc = self.arena.allocator();
            var ctx = try alloc.create(Context);
            ctx.* = Context.init(alloc, self.resources, &self.entites);
            return Pipeline.init(ctx);
        }
    };
}

// pub fn dump(self: *Self) void {
//   const cnt = self.entites.archetypes.count();
//   std.debug.print("\n dump --- {}\n", .{ cnt });
// }

test "example" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
        position: ecs.math.Vec2f,
        velocity: ecs.math.Vec2f,
        stuff: void,
    };

    const GlobalState = void;
    const Entities = ecs.Entities(Components);
    const Context = ecs.Context(GlobalState, Entities);

    const MoveSystem = struct {
        position: *ecs.math.Vec2f,
        velocity: ecs.math.Vec2f,

        const Self = @This();

        pub fn update(self: Self, context: *Context) !void {
            _ = context;
            self.position.* = self.position.add(self.velocity);
        }
    };

    const MyWorld = ecs.World(Context, &.{MoveSystem});

    var world = try MyWorld.init(allocator, {});
    defer world.deinit();

    const EntityTemplate = struct {
        position: ecs.math.Vec2f,
        velocity: ecs.math.Vec2f = .{ .x = 10, .y = 4.2 },
    };

    _ = try world.entites.create(EntityTemplate, .{
        .position = .{ .x = 0, .y = 10 },
    });
    _ = try world.entites.create(EntityTemplate, .{
        .position = .{ .x = 0, .y = 20 },
        .velocity = .{ .x = 1, .y = 2 },
    });

    const entityId = try world.entites.new();
    try world.entites.setComponent(entityId, .position, .{ .x = 10, .y = 22 });
    try world.entites.setComponent(entityId, .velocity, .{ .x = 0, .y = -1 });
    try world.entites.setComponent(entityId, .stuff, {});

    var pipeline = try world.createPipeline();
    try pipeline.run(.update);

    const Query = struct {
        id: ecs.EntityID,
        stuff: void,
        position: ecs.math.Vec2f,
    };

    var iterator = world.entites.getIterator(Query);
    const query_result = iterator.next().?;

    try std.testing.expect(query_result.id == entityId);
    try std.testing.expect(query_result.position.x == 10);
    try std.testing.expect(query_result.position.y == 21);

    try std.testing.expect(iterator.next() == null);
}
