const std = @import("std");
const ecs = @import("ecs.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub const Resources = struct {
    arena: ArenaAllocator,
    cache: ecs.ResourceCache = .{},

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{ .arena = ArenaAllocator.init(allocator) };
    }

    pub fn put(self: *Self, comptime T: type, ptr: *T) !void {
        return self.cache.put(self.arena.allocator(), T, ptr);
    }

    pub fn createWithInit(self: *Self, comptime T: type) !void {
        if (!@hasDecl(T, "init")) {
            @panic("missing init method");
        }
        const allocator = self.arena.allocator();
        const ptr = try allocator.create(T);
        ptr.* = T.init(allocator);
        try self.cache.put(allocator, T, ptr);
    }

    pub fn create(self: *Self, comptime T: type, value: T) !void {
        const allocator = self.arena.allocator();
        const ptr = try allocator.create(T);
        ptr.* = value;
        try self.cache.put(allocator, T, ptr);
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
        self.* = undefined;
    }
};

test "create with init" {
    const allocator = std.testing.allocator;

    var resources = Resources.init(allocator);
    defer resources.deinit();

    const MyResource = struct {
        list: std.ArrayList(u32),

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .list = std.ArrayList(u32).init(alloc) };
        }
    };

    try resources.createWithInit(MyResource);

    const ptr = resources.cache.get(MyResource);
    try ptr.list.ensureTotalCapacity(2000);
}
