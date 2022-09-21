const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;

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

        pub fn getIterator(self: Self, comptime T: type) Entities.TypedIter(T) {
            return Entities.TypedIter(T).init(self.entities);
        }

        pub fn getQuery(self: *Self, comptime Query: type, comptime Result: type) !*Result {
            if (self.cache.get(Result)) | result | {
                return result;
            }
            var result = try Query.setup(Self, self);
            try self.cache.set(Query, Result, result);
            return result;
        }
    };
}
