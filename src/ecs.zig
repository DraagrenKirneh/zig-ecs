
// An entity ID uniquely identifies an entity globally within an Entities set.
pub const EntityID = u64;
pub const void_archetype_hash = @import("std").math.maxInt(EntityID);

pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Entities = @import("entities.zig").Entities;
pub const ArchetypeStorage = @import("storage.zig").ArchetypeStorage;
pub const Context = @import("context.zig").Context;
pub const World = @import("world.zig").World;
pub const typeId = @import("storage.zig").typeId;
pub const EventHandler = @import("events.zig").EventHandler;

pub const math = @import("math/math.zig");

const reflection = @import("reflection.zig");

test {
  @import("std").testing.refAllDecls(@This());
}
