
const std = @import("std");
const testing = std.testing;
const reflection = @import("reflection.zig");

const PointerCache = struct {
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

    pub fn get(self: * const Self, comptime T: type) ?*T {
        var data = self.map.get(reflection.typeId(T));
        if (data) | bytes | {            
            return @intToPtr(*T, bytes);
        }
        return null;
    }

    pub fn set(self: *Self, comptime T: type, value: *T) !void {
        try self.map.put(reflection.typeId(T), @ptrToInt(value));
    }
};

const ObjectCache = struct {
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

const TestData = struct {
    f: f32,
    d: i32,
    b: u8,
};

test "X" {
    var allocator = std.testing.allocator;
    var data = try allocator.create(TestData);
    defer allocator.destroy(data);
    data.d = 42;
    data.f = 32.2;
    data.b = 7;

    std.testing.log_level = .debug;
    var x = std.mem.asBytes(data);
    var result = std.mem.bytesAsValue(TestData, x[0..@sizeOf(TestData)]);
    std.debug.print("\n LLV: {} {}\n", .{ @TypeOf(x), x.len });
    //try std.testing.expect(result != null);
    try std.testing.expectEqual(data, result);
    try std.testing.expectEqual(@ptrToInt(data), @ptrToInt(result));
    try std.testing.expectEqual(data.d, result.d);
    try std.testing.expectEqual(data.f, result.f);
    try std.testing.expectEqual(data.b, result.b);
}

const MyType = struct {
    item: void,
    player: void
};

test "aa" {
    const fields = std.meta.fields(MyType);
    try std.testing.expectEqual(fields[0].field_type, void);
    var ti_item = reflection.typeId(fields[0].field_type);
    var ti_player = reflection.typeId(fields[1].field_type);
    try std.testing.expectEqual(ti_item, ti_player);
}

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

    try cache.set(TestData, data);
    var result = cache.get(TestData);

    try std.testing.expect(result != null);
    try std.testing.expectEqual(data.d, result.?.d);
    try std.testing.expectEqual(data, result.?);
    try std.testing.expectEqual(data.f, result.?.f);
}

const MyStruct = struct {

    const Self = @This();
    pub fn make(self: Self, i: *i32) !void {
        _ = self;
        _ = i;
    }
};

test "Finfo" {
    //var info = @field(MyStruct, "make");
    //const fun = @typeInfo(@TypeOf(info)).Fn;
    const res = reflection.getDeclEnumNames(i32, &.{ MyStruct });
    std.debug.print("\n Info: {s} \n type: \n", .{ res[0] });
}