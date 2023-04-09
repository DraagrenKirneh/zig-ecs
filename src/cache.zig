const std = @import("std");
const testing = std.testing;

const TypeId = enum(usize) { _ };

// typeId implementation by Felix "xq" Queißner
fn typeId(comptime T: type) TypeId {
    return @intToEnum(TypeId, typeIdValue(T));
}

fn typeIdValue(comptime T: type) usize {
    _ = T;
    return @ptrToInt(&struct {
        var x: u8 = 0;
    }.x);
}

pub fn FixedCache(comptime types: []const type) type {
    return struct {
        const offset_buffer = [types.len]usize;
        const total_size = blk: {
            var count = 0;
            inline for (types, 0..) |T, i| {
                offset_buffer[i] = count;
                count += @sizeOf(T);
            }
            break :blk count;
        };

        buffer: []u8,

        const Self = @This();

        pub fn get(self: *Self, comptime T: type) *T {
            const index = comptime blk: {
                inline for (types, 0..) |tp, i| {
                    if (tp == T) break :blk i;
                }
                unreachable;
            };

            const offset = offset_buffer[index];

            return @ptrCast(*T, @alignCast(@alignOf(T), &self.buffer[offset..]));
        }
    };
}

pub const PointerCache = struct {
    const Map = std.AutoHashMap(TypeId, usize);
    map: Map,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .map = Map.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn getSingle(self: *const Self, comptime T: type) ?*T {
        return self.get(T, T);
    }

    pub fn createEntry(self: *Self, comptime T: type) !*T {
        const entry = try self.map.allocator.create(T);
        try self.setSingle(T, entry);
        return entry;
    }

    pub fn get(self: *const Self, comptime Key: type, comptime T: type) ?*T {
        var data = self.map.get(typeId(Key));
        if (data) |bytes| {
            return @intToPtr(*T, bytes);
        }
        return null;
    }

    pub fn destroy(self: *Self, comptime T: type) void {
        if (self.remove(T)) |entry| {
            self.map.allocator.destroy(entry);
        }
    }

    pub fn remove(self: *Self, comptime T: type) ?*T {
        if (self.get(T, T)) |entry| {
            _ = self.map.remove(typeId(T));
            return entry;
        }
        return null;
    }

    pub fn setSingle(self: *Self, comptime T: type, value: *T) !void {
        return self.set(T, T, value);
    }

    pub fn set(self: *Self, comptime Key: type, comptime T: type, value: *T) !void {
        try self.map.put(typeId(Key), @ptrToInt(value));
    }
};

pub const ObjectCache = struct {
    const Map = std.AutoArrayHashMap(TypeId, []u8);
    map: Map,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{ .map = Map.init(allocator) };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn get(self: *const Self, comptime T: type) ?*T {
        var data = self.map.get(typeId(T));
        if (data) |bytes| {
            return std.mem.bytesAsValue(T, @alignCast(@alignOf(T), bytes[0..@sizeOf(T)]));
        }
        return null;
    }

    pub fn set(self: *Self, comptime T: type, value: *T) !void {
        var bytes = std.mem.asBytes(value);
        try self.map.put(typeId(T), bytes[0..]);
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
