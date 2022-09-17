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

    pub fn run(tag: Tags) !void {
      const declName = @tagName(tag);
      inline for (systems) | system | {
        if(!@hasDecl(system, declName)) continue;
        if(std.meta.fields(system).len == 0) {
          var obj = system{};
          obj.onUpdate();
        }
        else {
          const Iter = Entities.TypedIter(system);
          var iter = Iter.init(self.entities);
          while (iter.next()) | value | {
            value.onUpdate();
          }
        }    
      }
    }

    pub fn update() !void {
      inline for (systems) | system | {
        if(!@hasDecl(system, "onUpdate")) continue;
        if(std.meta.fields(system).len == 0) {
          var obj = system{};
          obj.onUpdate();
        }
        else {
          const Iter = Entities.TypedIter(system);
          var iter = Iter.init(self.entities);
          while (iter.next()) | value | {
            value.onUpdate();
          }
        }    
      }
    }
    
  };
}