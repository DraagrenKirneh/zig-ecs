const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const ecs = @import("ecs.zig");
const reflection = @import("reflection.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn World(comptime Context: type, comptime systems: []const type) type {
    const Entites = Context.EntitesType;
    return struct {
        base_allocator: Allocator,
        arena: ArenaAllocator,
        entites: Entites,
        resources: ecs.Resources,

        const Self = @This();
        const Pipeline = ecs.Pipeline(Context, systems);

        pub fn init(allocator: Allocator) !Self {
            return Self{
                .base_allocator = allocator,
                .entites = Entites.init(allocator),
                .arena = ArenaAllocator.init(allocator),
                .resources = ecs.Resources.init(allocator),
            };
        }

        pub fn createResource(self: *Self, comptime T: type, value: T) !void {
            return self.resources.create(T, value);
        }

        pub fn startup(self: *Self, comptime list: []const type) !void {
            inline for (list) |T| {
                if (!@hasDecl(T, "startup")) continue;
                try T.startup(self);
            }
        }

        pub fn shutdown(self: *Self, comptime list: []const type) !void {
            inline for (list) |T| {
                if (!@hasDecl(T, "shutdown")) continue;
                T.shutdown(self);
            }
        }

        pub fn deinit(self: *Self) void {
            self.entites.deinit();
            self.arena.deinit();
            self.resources.deinit();
        }

        fn clearArena(self: *Self) void {
            self.arena.state.end_index = 0;
        }

        pub fn createPipeline(self: *Self) !Pipeline {
            self.clearArena();
            var alloc = self.arena.allocator();
            var ctx = try alloc.create(Context);
            ctx.* = Context.init(
                alloc,
                &self.resources.cache,
                &self.entites,
            );
            return Pipeline.init(ctx);
        }
    };
}

test "example" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
        position: ecs.math.Vec2f,
        velocity: ecs.math.Vec2f,
        stuff: void,
    };

    const GlobalState = struct {
        counter: usize = 0,
    };
    _ = GlobalState;
    const Entities = ecs.Entities(Components);
    const Context = ecs.Context(Entities);

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

    var world = try MyWorld.init(allocator);
    defer world.deinit();

    const EntityTemplate = struct {
        position: ecs.math.Vec2f,
        velocity: ecs.math.Vec2f = .{ .x = 10, .y = 4.2 },
    };

    _ = try world.entites.create(EntityTemplate, .{
        .position = .{ .x = 0, .y = 11 },
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

test "singletons" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
    };

    const Entities = ecs.Entities(Components);
    const Context = ecs.Context(Entities);

    const CounterSingleton = struct { value: usize = 0 };

    const CounterSystem = struct {
        const Self = @This();

        pub fn update(context: *Context) !void {
            const ptr = context.resources.get(CounterSingleton);
            ptr.value += 1;
        }

        pub fn print(context: *Context) !void {
            const ptr = context.resources.get(CounterSingleton);
            std.debug.print("\n-- Counter: {d}\n", .{ptr.value});
        }
    };

    const MyWorld = ecs.World(Context, &.{CounterSystem});

    var world: MyWorld = try MyWorld.init(allocator);
    defer world.deinit();

    const CounterRegistration = struct {
        pub fn startup(w: *MyWorld) !void {
            try w.createResource(CounterSingleton, .{ .value = 10 });
        }

        pub fn shutdown(w: *MyWorld) void {
            _ = w;
            //w.singletons.destroy(CounterSingleton);
        }
    };

    try world.startup(&.{CounterRegistration});

    var pipe: MyWorld.Pipeline = try world.createPipeline();
    try pipe.run(.print);
    try pipe.run(.update);
    try pipe.run(.print);

    try world.shutdown(&.{CounterRegistration});
}
