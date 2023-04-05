const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const ecs = @import("ecs.zig");
const reflection = @import("reflection.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn World(comptime Context: type, comptime systems: []const type) type {
    const Resources = Context.ResourcesType;
    const Entites = Context.EntitesType;
    return struct {
        baseAllocator: Allocator,
        arena: ArenaAllocator,
        entites: Entites,
        resources: Resources,

        const Self = @This();
        const Pipeline = ecs.Pipeline(Context, systems);

        pub fn init(allocator: Allocator, resources: Resources) !Self {
            return Self{
                .resources = resources,
                .baseAllocator = allocator,
                .entites = Entites.init(allocator),
                .arena = ArenaAllocator.init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            self.entites.deinit();
            self.arena.deinit();
        }

        fn clearArena(self: *Self) void {
            self.arena.state.end_index = 0;
        }

        pub fn createPipeline(self: *Self) !Pipeline {
            self.clearArena();
            var alloc = self.arena.allocator();
            var ctx = try alloc.create(Context);
            ctx.* = Context.init(alloc, &self.resources, &self.entites);
            return Pipeline.init(ctx);
        }
    };
}

// pub fn dump(self: *Self) void {
//   const cnt = self.entites.archetypes.count();
//   std.debug.print("\n dump --- {}\n", .{ cnt });
// }
