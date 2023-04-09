// An entity ID uniquely identifies an entity globally within an Entities set.

const identifier = @import("identifier.zig");

pub const EntityID = identifier.EntityId;
pub const IdentityGenerator = identifier.EntityIdProvider;
pub const ComponentId = identifier.ComponentId;

pub const Pipeline = @import("pipeline.zig").Pipeline;
pub const Entities = @import("entities.zig").Entities;
pub const ArchetypeStorage = @import("storage.zig").ArchetypeStorage;
pub const Context = @import("context.zig").Context;
pub const World = @import("world.zig").World;
pub const PointerCache = @import("cache.zig").PointerCache;

pub const EventHandler = @import("events.zig").EventHandler;

pub const math = @import("math/math.zig");

test {
    @import("std").testing.refAllDecls(@This());
}
