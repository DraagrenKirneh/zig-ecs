
// An entity ID uniquely identifies an entity globally within an Entities set.
pub const EntityID = u64;
pub const void_archetype_hash = @import("std").math.maxInt(EntityID);

pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Entities = @import("entities.zig").Entities;
pub const ArchetypeStorage = @import("storage.zig").ArchetypeStorage;
pub const Context = @import("context.zig").Context;
pub const World = @import("world.zig").World;
pub const typeId = @import("storage.zig").typeId;

pub const math = @import("math/math.zig");

const refl = @import("reflection.zig");

test {
  @import("std").testing.refAllDecls(@This());
}

const MyType = struct {
  types: []const type = &[_]type{},
  resources: []const type = &[_]type{},
  systems: []const type = &[_]type{},

  const Self = @This();

  inline fn init() Self {
    return .{};
  }

  inline fn create(comptime items: []const type) Self {
    return .{
      .types = items
    };
  }

  inline fn add(comptime self: Self, comptime entry: type) Self {
    return create(self.types ++ &[_]type{entry});
  }

  inline fn addResource(comptime self: Self, comptime entry: type) Self {
    return create(self.types ++ &[_]type{entry});
  }

  pub fn BuildResources(comptime self: Self) type {
    return refl.typesToHolder(self.resources);
  }

};

test "akka" {

  const len = MyType.init()
    //.create(&[_]type{EntityID})
    .add(*i32)
    .addResource(EntityID)
    .BuildResources();

  try @import("std").testing.expect(@typeInfo(len) == .Struct);
}
