
const std = @import("std");
const testing = std.testing;
const reflection = @import("reflection.zig");

pub const PointerCache = struct {
    const Map = std.AutoArrayHashMap(reflection.TypeId, usize);
    map: Map,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = Map.init(allocator)
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: *const Self, comptime Key: type, comptime T: type) ?*T {
        var data = self.map.get(reflection.typeId(Key));
        if (data) | bytes | {            
            return @intToPtr(*T, bytes);
        }
        return null;
    }

    pub fn set(self: *Self, comptime Key: type, comptime T: type, value: *T) !void {
        try self.map.put(reflection.typeId(Key), @ptrToInt(value));
    }
};

pub const ObjectCache = struct {
     const Map = std.AutoArrayHashMap(reflection.TypeId, []u8);
     map: Map,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .map = Map.init(allocator)
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: * const Self, comptime T: type) ?*T {
        var data = self.map.get(reflection.typeId(T));
        if (data) | bytes | {            
            return std.mem.bytesAsValue(T, @alignCast(@alignOf(T), bytes[0..@sizeOf(T)]));
        }
        return null;
    }

    pub fn set(self: *Self, comptime T: type, value: *T) !void {
        var bytes = std.mem.asBytes(value);
        try self.map.put(reflection.typeId(T), bytes[0..]);
    }
};

const TestKey = struct {};
const TestData = struct {
    f: f32,
    d: i32,
    b: u8,
};

test "ObjectCache" {
    var allocator = std.testing.allocator;
    var cache = ObjectCache.init(allocator);
    try cache.map.ensureUnusedCapacity(200);
    defer cache.deinit();

    var data = try allocator.create(TestData);
    defer allocator.destroy(data);
    data.d = 42;
    data.f = 32.2;
    
    try cache.set(TestData, data);
    var result = cache.get(TestData);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(data.d, result.?.d);
    try std.testing.expectEqual(data, result.?);
    try std.testing.expectEqual(data.f, result.?.f);
}

test "PtrCache" {
    std.testing.log_level = .debug;
    var allocator = std.testing.allocator;
    var cache = PointerCache.init(allocator);
    try cache.map.ensureUnusedCapacity(200);
    defer cache.deinit();

    var data = try allocator.create(TestData);
    defer allocator.destroy(data);
    data.d = 42;
    data.f = 32.2;

    try cache.set(TestKey, TestData, data);
    var result = cache.get(TestKey, TestData);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(data.d, result.?.d);
    try std.testing.expectEqual(data, result.?);
    try std.testing.expectEqual(data.f, result.?.f);
}