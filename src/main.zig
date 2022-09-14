const std = @import("std");
const testing = std.testing;
const reflection = @import("reflection.zig");


pub fn QueryCache(comptime types: []const type) type {
    const Cache = reflection.typesToHolder(types);
    return struct {
        allocator: std.mem.Allocator,
        cache: Cache = {},
        
        const Self = @This();
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .allocator = allocator
            };
        } 

        pub fn get(self: *Self, T: type) ?T {
            return @field(self.cache, @typeName(T));
        }
    };
}

const ObjectCache = struct {
     const Map = std.AutoArrayHashMap(usize, []u8);
     map: Map,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = Map.init(allocator)
        };
    }

    pub fn get(self: * const Self, T: type) ?T {
        var data = self.map.get(reflection.typeId(T));
        if (data) | bytes | {
            return std.mem.bytesAsValue(T, bytes);
        }
        return null;
    }

    pub fn set(self: *Self, T: type, value: *T) !void {
        var bytes = std.mem.asBytes(value);
        try self.map.put(reflection.typeId(T), bytes);
    }
};

const TestData = struct {
    f: f32,
    d: i32
};

test "ObjectCache" {
    var allocator = std.testing.allocator;
    var cache = ObjectCache.init(allocator);

    var data = try allocator.create(TestData);
    data.d = 42;
    data.f = 32.2;

    try cache.set(TestData, data);

    var result = cache.get(TestData);
    try std.testing.expect(result != null);
}
