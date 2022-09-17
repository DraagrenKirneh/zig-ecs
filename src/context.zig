const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;

pub fn Context(comptime State: type, comptime Entities: type) Type {
    return struct {
        entities: *Entities,
        state: *State,
        allocator: Allocator,
        cache: Cache,

        const Self = @This();

        pub fn init(allocator: Allocator, state: *State, entities: *Entities) Self {
            return .{
                .allocator = allocator,
                .state = state,
                .entities = entities,
                .cache = Cache.init(allocator),
            }
        }

        pub fn getIterator(self: Self, comptime T: type) Entities.TypedIter(T) {
            return Entities.TypedIter(Entry).init(self.entities);
        }

        pub fn getQuery(self: Self, comptime Query: type) !*@field(Query, "Return") {
            const ReturnType = @field(Query, "Return");
            if (cache.get(ReturnType)) | result | {
                return result;
            }
            var query = try self.allocator.create(Query);
            var result = try query.setup(Self, &self);
            try cache.set(Query, result);
            return result;
        }
    };
}