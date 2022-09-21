const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;
const typeId = @import("ecs.zig").typeId;

pub fn Context(comptime State: type, comptime Entities: type) type {
    return struct {
        entities: *Entities,
        state: *State,
        allocator: Allocator,
        cache: Cache,

        const Self = @This();
        pub const StateType = State;
        pub const EntitesType = Entities;
        
        pub fn init(allocator: Allocator, state: *State, entities: *Entities) Self {
            return .{
                .allocator = allocator,
                .state = state,
                .entities = entities,
                .cache = Cache.init(allocator),
            };
        }

        fn Iterator(comptime T: type) type {
            return EntitesType.TypedIter(T);
        }

        pub fn getIterator(self: *Self, comptime T: type) Iterator(T) {
            return Iterator(T).init(self.entities);
        }

        pub fn getQuery(
            self: *Self, 
            comptime Key: type, 
            comptime Value: type, 
            comptime generateFn: fn (context: *Self) anyerror!*Value) 
        !*Value {
            if (self.cache.get(Key, Value)) | result | {
                 return result;
            }
            var result = try generateFn(self);
            try self.cache.set(Key, Value, result);
            return result;
        }
    };
}
