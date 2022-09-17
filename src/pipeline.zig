const std = @import("std");
const storage = @import("storage.zig");
const reflection = @import("reflection.zig");
const ecs = @import("entityContainer.zig");

const testing = std.testing;

pub fn Pipeline(comptime Context: type, comptime systems: []const type) type {
 
  return struct {
    context: *Context,

    const Tags = reflection.ToEnumFromMethods(Context, systems);
    const Self = @This();

    pub fn init(context: *Context) Self {
      return .{
        .context = context
      };
    }

    pub fn run(self: Self, tag: Tags) !void {
      const declName = @tagName(tag);
      inline for (systems) | system | {
        if(!@hasDecl(system, declName)) continue;
        const field = @field(system, declName);
        const Iter = Context.Entities.TypedIter(system);
        var iter = Iter.init(self.context.entities);
        while (iter.next()) | value | {          
          @call(.{}, field, .{ value, self.context });
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

  const TestContext = struct {
    pub const Entities = MyStorage;
    entities: *MyStorage
  };

  const TestMethod = struct {
    rotation: *u32,

    const Self = @This();
    pub fn update(self: Self, context: *TestContext) void {
      _ = context;
      std.debug.print("\n\n ---- value is: {}\n", .{ self.rotation.* });
      self.rotation.* += 4;
    }
  };

  
  var b = try MyStorage.init(allocator);
  defer b.deinit();
  var e2 = try b.create(Entry, .{ .rotation = 75 });  
  _ = e2;
  var e = try b.new();
  try b.setComponent(e, .rotation, 42);

  var ctx = TestContext{ .entities = &b };
  const Pipe = Pipeline(TestContext, &.{ TestMethod });
  
  var pipeline = Pipe.init(&ctx);

  try pipeline.run(.update);
  try pipeline.run(.update);
}