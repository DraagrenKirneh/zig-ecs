const std = @import("std");
const testing = std.testing;
const builtin = @import("builtin");
const ecs = @import("ecs.zig");
const reflection = @import("reflection.zig");

const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

pub fn World(comptime Context: type, comptime systems: []const type) type {
  const Pipeline = ecs.Pipeline(Context, systems);
  const State = Context.StateType;
  const Entites = Context.EntitesType;
  return struct {
    baseAllocator: Allocator,
    arena: ArenaAllocator,
    entites: Entites,
    state: State,

    const Self = @This();
    pub fn init(allocator: Allocator, state: State) !Self {
      var entites = try Entites.init(allocator);
      return Self{
        .baseAllocator = allocator,
        .arena = ArenaAllocator.init(allocator),
        .state = state,
        .entites = entites,
      };
    }

    pub fn startFrame(self: *Self) Pipeline {
      var context = Context.init(self.arena.allocator(), &self.state, &self.entites);
      return Pipeline.init(&context);
    }

    pub fn endFrame(self: *Self) void {
      self.arena.deinit();
    }
  };
}
