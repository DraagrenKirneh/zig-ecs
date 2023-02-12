const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const ecs = @import("ecs.zig");
const reflection = @import("reflection.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn World(comptime Context: type, comptime systems: []const type) type {
  const State = Context.StateType;
  const Entites = Context.EntitesType;
  return struct {
    baseAllocator: Allocator,
    arena: ArenaAllocator,
    entites: Entites,
    state: State,

    const Self = @This();
    const Pipeline = ecs.Pipeline(Context, systems);

    pub fn init(allocator: Allocator, state: State) !Self {
      return Self{
        .baseAllocator = allocator,
        .arena = ArenaAllocator.init(allocator),
        .state = state,
        .entites = try Entites.init(allocator),        
      };
    }

    pub fn dump(self: *Self) void {
      const cnt = self.entites.archetypes.count();
      std.debug.print("\n dump --- {}\n", .{ cnt });
    }

    pub fn deinit(self: *Self) void {
      self.entites.deinit();
      self.arena.deinit();
    }

    pub fn createPipeline(self: *Self) !Pipeline {
      self.arena.state.end_index = 0;
      var alloc = self.arena.allocator();
      var ctx = try alloc.create(Context);
      ctx.* = Context.init(alloc, &self.state, &self.entites);
      return Pipeline.init(ctx);
    }
  };
}
