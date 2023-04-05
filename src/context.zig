const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;
const EntityID = @import("ecs.zig").EntityID;

pub fn Context(comptime Resources: type, comptime Entities: type) type {
    return struct {
        entities: *Entities,
        resources: ResourcesType,
        allocator: Allocator,
        cache: Cache,
        deadList: std.ArrayList(EntityID),

        const Self = @This();
        pub const ResourcesType = if (Resources == void) void else *Resources;
        pub const EntitesType = Entities;

        pub fn init(allocator: Allocator, resources: ResourcesType, entities: *Entities) Self {
            return .{
                .allocator = allocator,
                .resources = resources,
                .entities = entities,
                .cache = Cache.init(allocator),
                .deadList = std.ArrayList(EntityID).init(allocator),
            };
        }

        fn Iterator(comptime T: type) type {
            return EntitesType.TypedIter(T);
        }

        pub fn deferRemove(self: *Self, id: EntityID) !void {
            try self.deadList.append(id);
        }

        pub fn cleanup(self: *Self) !void {
            for (self.deadList.items) |each| {
                try self.entities.remove(each);
            }
        }

        pub fn getIterator(self: *Self, comptime T: type) Iterator(T) {
            return Iterator(T).init(self.entities);
        }

        // return a valid ptr to an object cached only per frame
        pub fn getPerFrameCachedPtr(self: *Self, comptime Key: type, comptime Value: type, comptime generateFn: fn (context: *Self) anyerror!*Value) !*Value {
            if (self.cache.get(Key, Value)) |result| {
                return result;
            }
            var result = try generateFn(self);
            try self.cache.set(Key, Value, result);
            return result;
        }
    };
}
