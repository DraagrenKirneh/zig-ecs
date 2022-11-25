const ecs = @import("ecs");
const math = ecs.math;

pub const Game = struct {
  done: bool = false,
  width: f32,
  height: f32
};

pub const Id = ecs.EntityID;

const Components = struct {
  id: Id,
  position: math.Vec2f,
  size: math.Vec2f,
  velocity: f32,
  health: f32,
  target: Id,
};

pub const Entities = ecs.Entities(Components);
pub const Context = ecs.Context(Game, Entities);

