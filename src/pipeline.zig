const std = @import("std");
const storage = @import("storage.zig");
const reflection = @import("reflection.zig");
const ecs = @import("ecs.zig");
const testing = std.testing;

pub fn Pipeline(comptime Context: type, comptime systems: []const type) type { 
  return struct {
    context: *Context,

    const Operation = reflection.ToEnumFromMethods(Context, systems);
    const Self = @This();

    pub fn init(context: *Context) Self {
      return .{
        .context = context
      };
    }

    pub fn run(self: *Self, comptime tag: Operation) !void {
      const declName = @tagName(tag);
      inline for (systems) | system | {
        if(!@hasDecl(system, declName)) continue;
        const field = @field(system, declName); 

        var iter = self.context.getIterator(system);  
        while (iter.next()) | value | {     
          try @call(.auto, field, .{ value, self.context });          
        }  
      }
    }
  };
}

test "Pipeline" {
  const Game = struct {
    id: ecs.EntityID,
    location: f32,
    name: []const u8,
    rotation: u32,
  };
  const MyStorage = ecs.Entities(Game);
  const allocator = std.testing.allocator;
  const Entry = struct {
    rotation: u32,
  };

  const TestContext = ecs.Context(i32, MyStorage);

  const TestMethod = struct {
    rotation: *u32,

    const Self = @This();
    pub fn update(self: Self, context: *TestContext) !void {
      _ = context;
      std.debug.print("\n\n ---- value is: {}\n", .{ self.rotation.* });
      self.rotation.* += 4;
    }

    pub fn draw(self: Self, context: *TestContext) !void {
      _ = context;
      std.debug.print("\n\n ---- value is: {}\n", .{ self.rotation.* });
    }
  };

  
  var b = try MyStorage.init(allocator);
  defer b.deinit();
  var e2 = try b.create(Entry, .{ .rotation = 75 });  
  _ = e2;
  var e = try b.new();
  try b.setComponent(e, .rotation, 42);

  var state: i32 = 43;
  var ctx = TestContext.init(allocator, &state, &b);
  const Pipe = Pipeline(TestContext, &.{ TestMethod });
  
  var pipeline = Pipe.init(&ctx);
  try pipeline.run(.update);
  try pipeline.run(.draw);
}