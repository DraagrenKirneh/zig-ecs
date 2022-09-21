const std= @import("std");
const ecs = @import("ecs");
const math = ecs.math;
const Rectangle = math.Rectangle;
const core = @import("core.zig");

const QuadTree = ecs.math.QuadTree(ecs.EntityID, 30, 8);

const EnemySpatialQuery = struct {
  pub fn setup(comptime Context: type, context: *Context) !*QuadTree {
    var allocator = context.allocator;
    const view = Rectangle.initBasic(0, 0, context.state.width, context.state.height);
    var tree = try allocator.create(QuadTree);
    tree.* = try QuadTree.init(allocator, view);
    var iterator = context.getIterator(Entry);
    while (iterator.next()) | each | {
      var item_area = Rectangle.init(each.position, each.size);
      try tree.add(each.id, item_area);
    }

    return tree;
  }

  const Entry = struct {
    id: ecs.EntityID,
    position: math.Vec2f,
    size: math.Vec2f,
  };
};

const Move = struct {
  position: math.Vec2f,
  size: math.Vec2f,

  const Self = @This();

  pub fn step(self: Self, context: *core.Context) !void {
    var tree = try context.getQuery(EnemySpatialQuery, QuadTree);
    _ = tree;
    _ = context;
    _ = self;
    //tree.query();
    //self.rotation.* = self.rotation.* + 5;
    //std.debug.print("\nMOVE: {} -> {}\n", .{ self.location, self.rotation.* });
  }
};

// World(comptime State: type, comptime Entities: type, comptime Context: type, comptime systems: []const type);
const World = ecs.World(core.Context, &.{ Move });

test "test" {
  var gameState = core.Game{ .width = 1200, .height = 800, .done = false }; 
  var alloc = std.testing.allocator;
  var world = try World.init(alloc, gameState);

  var pipeline = world.startFrame();
  try pipeline.run(.step);
  world.endFrame();
}


// test "world" {
//   const myGame = .{
//     .location = f32,
//     .name = []const u8,
//     .rotation = u32,
//   };
//   const allocator = std.testing.allocator;

//   const MyWorld = World(myGame);
//   var ec = try MyWorld.Entities.init(allocator);
//   //defer ec.deinit();
//   var e2 = try ec.create(MoveData, .{ .rotation = 75, .location = 27 });
//   _ = e2;
//   var a = MyWorld.Stepper(&.{ Move }).init(&ec);
//   a.step();
//   a.step();
//   a.step();
// }
