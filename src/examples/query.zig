const std= @import("std");
const ecs = @import("ecs");
const math = ecs.math;
const Rectangle = math.Rectangle;
const core = @import("core.zig");

const QuadTree = ecs.math.QuadTree(ecs.EntityID, 30, 8);

// tower -> projectile -> attack -> monster

// const Tower = struct {
//   id: core.Id,
//   position: math.Vec2f,
//   size: math.Vec2f,
//   range: f32,
//   damage: f32,
// }

const EntityId = core.Id;

const TextureTag = enum {};

const DrawController = struct {
  position: math.Vec2f,
  size: math.Vec2f,
  texture: TextureTag,

  const Self = @This();

  pub fn draw(self: Self, context: *core.Context) !void {
    _ = self;
    _ = context;  
  }
};

const TowerController = struct {
  id: EntityId,
  position: math.Vec2f,
  range: f32,
  cooldown: *f32,

  const ProjectileEntity = struct {
    position: math.Vec2f,
    velocity: f32,
    targetId: core.Id,
    towerId: core.Id
  };

  const Self = @This();

  pub fn step(self: Self, context: *core.Context) !void {
    if (self.cooldown != 0) return;
    const tree = try context.getQuery(SpatialQuery, QuadTree, SpatialQuery.generate);
    const halfRange = self.range / 2.0;
    const halfVec2f = math.Vec2f.init(halfRange, halfRange);
    const area = math.Rectangle.init(
      self.position.sub(halfVec2f),
      self.position.add(halfVec2f),
    );
    const entries = try tree.query(area, 1);
    if (entries.len > 0) {
      try context.createEntity(ProjectileEntity, .{
        .position = self.position,
        .velocity = 10,
        .targetId = entries[0].id,
        .towerId = self.id,
      });
      self.cooldown = 1000;
    }
    else {
      self.cooldown = std.math.max(0, self.cooldown - 100);
    }
  }
};

const ProjectileController = struct {
  id: core.Id,
  position: *math.Vec2f,
  velocity: f32,
  targetId: core.Id,
  towerId: core.Id,

  const Self = @This();

  const TowerEntity = struct {
    damage: f32,
  };

  const MonsterEntity = struct {
    position: math.Vec2f,
    health: *f32,
  };

  pub fn step(self: Self, context: *core.Context) !void {
    const opt_monster = context.entities.getEntity(self.targetId, MonsterEntity);
    if (opt_monster) | monster | {
      const length = self.position.length(monster.position);
      const distance = self.velocity;
      if (length <= distance) {
        self.position.* = monster.position;
        const opt_tower = context.entites.getEntity(self.towerId, TowerEntity);
        if (opt_tower) | tower | {
          monster.health = monster.health - tower.damage;
        }
        try context.kill(self.id);
      }
      const t = distance / length;
      self.position.* = self.position.lerp(monster.position, t);
    } else {
      try context.kill(self.id);
    }
  }
};

const Move = struct {
  position: math.Vec2f,
  size: math.Vec2f,

  const Self = @This();

  pub fn step(self: Self, context: *core.Context) !void {
    const tree = try context.getQuery(SpatialQuery, QuadTree, SpatialQuery.generate);
    _ = tree;
    _ = self;

    std.debug.print("\nstep: {}\n", .{ context.entities.entities.count() });
  }
};


const Monster = struct {
  position: math.Vec2f,
  size: math.Vec2f,
  velocity: f32,
};

const SpatialQuery = struct {
  pub fn generate(context: *core.Context) !*QuadTree {
    const view = Rectangle.initBasic(0, 0, 1200, 800);
    var tree = try context.allocator.create(QuadTree);
    tree.* = QuadTree.init(context.allocator, view);

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


const World = ecs.World(core.Context, &.{ Move });

test "test" {
  std.testing.log_level = .debug;
  var gameState = core.Game{ .width = 1200, .height = 800, .done = false }; 
  var alloc = std.testing.allocator;

  var world = try World.init(alloc, gameState);
  _ = try world.entites.new();
  _ = try world.entites.create(Monster, .{ .position = .{ .x = 42, .y = 32 }, .size = .{ .x = 100, .y = 100 }, .velocity = 10 });
  var pipeline = try world.createPipeline();
  
  try pipeline.run(.step);
  try pipeline.run(.step);
  try pipeline.run(.step);
  try pipeline.run(.step);
  
  var pipeline2 = try world.createPipeline();
  try pipeline2.run(.step);
  world.deinit();
}

