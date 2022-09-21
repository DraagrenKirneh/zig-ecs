const ecs = @import("ecs");
const math = ecs.math;

pub const Game = struct {
  done: bool = false,
  width: f32,
  height: f32
};

const Components = struct {
  id: ecs.EntityID,
  position: math.Vec2f,
  size: math.Vec2f,
  velocity: f32,
};

pub const Entities = ecs.Entities(Components);
pub const Context = ecs.Context(Game, Entities);