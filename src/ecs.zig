// An entity ID uniquely identifies an entity globally within an Entities set.
pub const EntityID = u64;
pub const ComponentId = @import("componentId.zig").ComponentId;

pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Entities = @import("entities.zig").Entities;
pub const ArchetypeStorage = @import("storage.zig").ArchetypeStorage;
pub const Context = @import("context.zig").Context;
pub const World = @import("world.zig").World;

pub const EventHandler = @import("events.zig").EventHandler;

pub const math = @import("math/math.zig");

const reflection = @import("reflection.zig");
//pub const TypeId = reflection.TypeId;
//pub const typeId = reflection.typeId;

test {
    @import("std").testing.refAllDecls(@This());
}
