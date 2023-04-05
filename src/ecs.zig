// An entity ID uniquely identifies an entity globally within an Entities set.

const identifiers = @import("componentId.zig");

pub const EntityID = identifiers.EntityId;
pub const EntityIdProvider = identifiers.EntityIdProvider;
pub const ComponentId = identifiers.ComponentId;

pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Entities = @import("entities.zig").Entities;
pub const ArchetypeStorage = @import("storage.zig").ArchetypeStorage;
pub const Context = @import("context.zig").Context;
pub const World = @import("world.zig").World;

pub const EventHandler = @import("events.zig").EventHandler;

pub const math = @import("math/math.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
