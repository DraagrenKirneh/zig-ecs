const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const builtin = @import("builtin");
const arch_storage = @import("storage.zig");
const reflection = @import("reflection.zig");
const entities = @import("entityContainer.zig");
const storage = @import("storage.zig");
const Entites = entities.Entities;

pub fn Builder(comptime components: anytype) type {

}

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

const WorldState = struct {
  baseAllocator: Allocator,
  arena: ArenaAllocator,

  const Self = @This();
  pub fn init(allocator: Allocator) Self {
    return .{
      .baseAllocator = allocator,
      .arena = ArenaAllocator.init(allocator),
    };
  }

  pub fn beginFrame(self: *Self) void {
    self.arena.deinit();
  }
};

pub fn World(comptime Context: type) type {
  return struct {    
    pub const Entities = entities.Entities(components);
    pub const ComponentTag = Entities.TagType;
    
    pub fn Stepper(comptime systems: []const type) type {
      return struct {
        entities: *Entities,

        const Self = @This();

        pub fn init(e2: *Entities) Self {
          return .{
            .entities = e2
          };
        }

        pub fn step(self: *Self) void {
          inline for (systems) | system | {
            const Iter = Entities.TypedIter(system);
            var iter = Iter.init(self.entities);
            while (iter.next()) | val | {
              val.step();
            }
          }
        }
                  
      };
    }
  };
}

const Game = {

};

const Components = .{
  .direction = u32,
  .position = [2]f32,
};

const Enemy = .{

};

const quad = @import("quadtree.zig");
const Quadtree = quad.Quadtree(storage.EntityID, 30, 8);


pub fn get(comptime Query: type, comptime Result: type) !Result {
  var bytes = std.mem.asBytes();
}

const EnemySpatialQuery = struct {
  pub const Return = Quadtree;

  pub fn setup(comptime Context: type, context: *Context) !Quadtree {
    var allocator = context.allocator;
    const view = Area.init(0, 0, world.width, world.heigth);
    var tree = Quadtree.init(allocator);
    var iterator = context.getIterator(Entry);
    while (iterator.next()) | each | {
      var item_area = quad.Area.init(each.position[0], each.position[1], each.size[0], each.size[1]);
      try tree.add(each.id, item_area);
    }

    return tree;
  }

  const Entry = struct {
    id: storage.EntityID,
    position: [2]f32,
    size: [2]f32
  };
};

const MyWorld = World(Components);

const SpawnEnemy = struct {

  const interval: f32 = 0;

  pub fn onInterval(game: *Game, ecs: *MyWorld.Entities) !void {
    //try ecs.create()
  }

};

const MoveData = struct {
  location: f32,
  rotation: u32,
};

const Move = struct {
  location: f32,
  rotation: *u32,

  const Self = @This();

  pub fn step(self: Self) void {
    self.rotation.* = self.rotation.* + 5;
    std.debug.print("\nMOVE: {} -> {}\n", .{ self.location, self.rotation.* });
  }
};

test "world" {
  const myGame = .{
    .location = f32,
    .name = []const u8,
    .rotation = u32,
  };
  const allocator = std.testing.allocator;

  const MyWorld = World(myGame);
  var ec = try MyWorld.Entities.init(allocator);
  //defer ec.deinit();
  var e2 = try ec.create(MoveData, .{ .rotation = 75, .location = 27 });
  _ = e2;
  var a = MyWorld.Stepper(&.{ Move }).init(&ec);
  a.step();
  a.step();
  a.step();
}
