# Experimental Entity Component System for Zig

Experimental derivation/fork of https://github.com/hexops/mach/tree/main/libs/ecs .

## Examples

```zig
test "example" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
        position: ecs.math.Vec2f,
        velocity: ecs.math.Vec2f,
        stuff: void,
    };

    const Entities = ecs.Entities(Components);
    const Context = ecs.Context(Entities);

    const MoveSystem = struct {
        position: *ecs.math.Vec2f,
        velocity: ecs.math.Vec2f,

        const Self = @This();

        pub fn update(self: Self) !void {
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
```

```zig
test "Pairs" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
        position: f32,
        size: i32,
        sun: void,
    };

    const MyEntities = ecs.Entities(Components);

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    const entityId = try entities.new();

    try entities.setPair(entityId, .sun, .size, .{ .value = 44 });
    try entities.setPair(entityId, .sun, .position, .{ .value = 22 });

    const componentValue = entities.getPair(entityId, .sun, .size).?;
    try expectEqual(i32, 44, componentValue.value);

    const Query = struct {
        id: ecs.EntityID,
        pair_a: MyEntities.Pair(.sun, .position),
        pair_b: MyEntities.Pair(.sun, .size),
    };

    var it = entities.getIterator(Query);

    const result = it.next().?;

    try expectEqual(EntityID, entityId, result.id);

    try expectEqual(void, {}, result.pair_a.key);
    try expectEqual(f32, 22, result.pair_a.value);

    try expectEqual(void, {}, result.pair_b.key);
    try expectEqual(i32, 44, result.pair_b.value);

    try std.testing.expect(it.next() == null);
}
```
