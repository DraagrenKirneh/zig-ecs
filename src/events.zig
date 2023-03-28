const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

pub fn EventHandler(comptime OwnerId: type, comptime Event: type, comptime Context: type) type {
  return struct {
    const ConditionFn = *const fn (ownerId: OwnerId, event: Event, context: *const Context) bool;
    const ActionFn = *const fn (ownerId: OwnerId, event: Event, context: *Context) anyerror!void;
    
    pub const Trigger = struct {
      ownerId: OwnerId,
      condition: ConditionFn,
      action: ActionFn,
    };

    const TriggerList = std.ArrayList(Trigger);
    const EventList = std.ArrayList(Event);
    const EventTag = std.meta.FieldEnum(Event);
    const TriggerMap = std.AutoHashMap(EventTag, TriggerList);

    events: EventList,
    triggers: TriggerMap,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
      var self = Self{
        .events = EventList.init(allocator),
        .triggers = TriggerMap.init(allocator),
      };

      return self;
    }

    pub fn deinit(self: *Self) void {
      self.events.deinit();
      var valIt = self.triggers.valueIterator();
      while (valIt.next()) | v | {
        v.deinit();
      }
      self.triggers.deinit();
    }
  
    pub fn addTrigger(self: *Self, tag: EventTag, trigger: Trigger) !void {
      var entry =  try self.triggers.getOrPut(tag);
      if (!entry.found_existing) {
        entry.value_ptr.* = TriggerList.init(self.triggers.allocator);
      }
      try entry.value_ptr.append(trigger);
    }

    pub fn addEvent(self: *Self, event: Event) !void {
      try self.events.append(event);
    }

    pub fn step(self: *Self, context: *Context) !void {
      for (self.events.items) | event | {          
        const i = @enumToInt(event);    
        const k = @intToEnum(EventTag, i);      
        if (self.triggers.get(k)) | list | {
          for (list.items) | trigger | {
            const ownerId = trigger.ownerId;
            if (trigger.condition(ownerId, event, context)) {
              try trigger.action(ownerId, event, context);
            }
          }
        }      
      }
      self.events.clearRetainingCapacity();
    }
  };  
}

pub fn TriggerSystem(comptime Context: type) type {
  return struct {
    pub fn step(context: *Context) !void {
      var eventHandler = context.state.eventHandler;
      try eventHandler.step(context.entities);
    }
  };
}

test "engine ctor/dtor" {

  const MyEvent = union(enum) {
    Increment: i32,
    Decrement: i32
  };

  const MyContext = struct {
    counter: i32 = 0
  };

  const S = struct {
    pub fn condition(id: usize, e: MyEvent, ctx: *const MyContext) bool {
      _ = id; _ = e; _ = ctx;
      return true;
    }

    pub fn inc_action(id: usize, e: MyEvent, ctx: *MyContext) !void {
      _ = id;
      ctx.counter += e.Increment;
    }

    pub fn dec_action(id: usize, e: MyEvent, ctx: *MyContext) !void {
      _ = id;
      ctx.counter -= e.Decrement;
    }
  };
  
  const myEventHandler = EventHandler(usize, MyEvent, MyContext);

  //std.testing.log_level = .debug;

  const alloc = std.testing.allocator;
  var ctx = MyContext{ .counter = 4 };

  var eventHandler = myEventHandler.init(alloc);
  defer eventHandler.deinit();

  try eventHandler.addTrigger(.Increment, .{ .condition = S.condition, .action = S.inc_action, .ownerId = 32 });  
  try eventHandler.addTrigger(.Decrement, .{ .condition = S.condition, .action = S.dec_action, .ownerId = 42 });
  try eventHandler.addTrigger(.Decrement, .{ .condition = S.condition, .action = S.dec_action, .ownerId = 32 });

  try eventHandler.addEvent(.{ .Increment = 42 });
  try eventHandler.addEvent(.{ .Decrement = 10 });

  try eventHandler.step(&ctx);

  try std.testing.expectEqual(@intCast(i32, 26), ctx.counter);
}
