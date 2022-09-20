const std = @import("std");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;

fn returnType(comptime T: type) std.builtin.Type {
    const field = @field(T, "setup");
    return @typeInfo(@TypeOf(field));
}

pub fn Context(comptime State: type, comptime Entities: type) type {
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
            };
        }

        pub fn getIterator(self: Self, comptime T: type) Entities.TypedIter(T) {
            return Entities.TypedIter(T).init(self.entities);
        }

        pub fn getQuery(self: Self, comptime Query: type) !*@field(Query, "Return") {
            //const ReturnType = @field(Query, "Return");
            if (self.cache.get(Query)) | result | {
                return result;
            }
            var result = try Query.setup(Self, &self);
            try self.cache.set(Query, result);
            return result;
        }
    };
}

const TFN = struct {
    pub fn setup(comptime T: type, ctx: *T) Entry {
        _ = ctx;
        return .{ .x = 42 };
    }

    const Entry = struct {
        x: 43
    };
};

test "retval" {
    const res = returnType(TFN);
    std.debug.print("\n{}\n", .{ res.Fn.return_type });
    //.Fn.return_type.?;
}