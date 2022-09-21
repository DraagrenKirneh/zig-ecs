const std= @import("std");
const ecs = @import("ecs");
const math = ecs.math;
const Rectangle = math.Rectangle;
const core = @import("core.zig");

const QuadTree = ecs.math.QuadTree(ecs.EntityID, 30, 8);

const Move = struct {
  position: math.Vec2f,
  size: math.Vec2f,

  const Self = @This();

  pub fn step(self: Self, context: *core.Context) !void {
    const tree = try context.getQuery(EnemySpatialQuery, QuadTree, EnemySpatialQuery.setup);
    _ = tree;
    //_ = context;
    _ = self;
    //tree.query();
    //self.rotation.* = self.rotation.* + 5;
    std.debug.print("\nstep: {}\n", .{ context.entities.entities.count() });
  }
};

const Monster = struct {
  position: math.Vec2f,
  size: math.Vec2f,
  velocity: f32,
};

const EnemySpatialQuery = struct {
  pub fn setup(context: *core.Context) !*QuadTree {
    const view = Rectangle.initBasic(0, 0, 1200, 800);
    var tree2 = try context.allocator.create(QuadTree);
    tree2.* = QuadTree.init(context.allocator, view);

    var iterator = core.Context.Iterator(Entry).init(context.entities);
    while (iterator.next()) | each | {
      var item_area = Rectangle.init(each.position, each.size);
      try tree2.add(each.id, item_area);
    }
    return tree2;
  }

  const Entry = struct {
    id: ecs.EntityID,
    position: math.Vec2f,
    size: math.Vec2f,
  };
};

const Friend = struct {
  pub fn nn(context: *core.Context) !*QuadTree {
    const view = Rectangle.initBasic(0, 0, 1200, 800);
    var tree2 = try context.allocator.create(QuadTree);
    tree2.* = QuadTree.init(context.allocator, view);

    var iterator = core.Context.Iterator(Entry).init(context.entities);
    while (iterator.next()) | each | {
      var item_area = Rectangle.init(each.position, each.size);
      try tree2.add(each.id, item_area);
    }
    return tree2;
  }

  const Entry = struct {
    id: ecs.EntityID,
    position: math.Vec2f,
    size: math.Vec2f,
  };
};


const World = ecs.World(core.Context, &.{ Move });

test "test" {
  std.testing.log_level = .debug;
  var gameState = core.Game{ .width = 1200, .height = 800, .done = false }; 
  var alloc = std.testing.allocator;

  var world = try World.init(alloc, gameState);
  _ = try world.entites.new();
  _ = try world.entites.create(Monster, .{ .position = .{ .x = 42, .y = 32 }, .size = .{ .x = 100, .y = 100 }, .velocity = 10 });
  var pipeline = try world.createPipeline();
  pipeline.dump();  
  try pipeline.run(.step);
  std.debug.print("\n dd {} \n", .{ pipeline.context.cache.map.count() });
  try pipeline.run(.step);
  try pipeline.run(.step);
  try pipeline.run(.step);
  std.debug.print("\n dd {} \n", .{ pipeline.context.cache.map.count() });
  //world.dump();

  //world.endFrame();
  var pipeline2 = try world.createPipeline();
  pipeline2.dump();
  try pipeline2.run(.step);
  //world.endFrame();
  world.deinit();
}

