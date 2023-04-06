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
            return .{ .context = context };
        }

        pub fn run(self: *Self, comptime tag: Operation) !void {
            const declName = @tagName(tag);
            inline for (systems) |system| {
                if (!@hasDecl(system, declName)) continue;
                const field = @field(system, declName);
                const argCount = functionArgCount(field);
                if (argCount == 1) {
                    // @Maybe context or value depending on param?
                    try @call(.auto, field, .{self.context});
                } else if (argCount == 2) {
                    var iter = self.context.getIterator(system);
                    while (iter.next()) |value| {
                        try @call(.auto, field, .{ value, self.context });
                    }
                }
            }

            try self.context.submitCommands();
        }
    };
}

inline fn functionArgCount(comptime fn_field: anytype) usize {
    const field_type = @TypeOf(fn_field);
    const type_info = @typeInfo(field_type);
    return type_info.Fn.params.len;
}

test "Pipeline" {
    const allocator = std.testing.allocator;

    const Game = struct {
        id: ecs.EntityID,
        location: f32,
        name: []const u8,
        rotation: u32,
    };

    const MyEntities = ecs.Entities(Game);
    const MyContext = ecs.Context(void, MyEntities);

    const Entry = struct {
        rotation: u32,
    };

    const RotationSystem = struct {
        id: ecs.EntityID,
        rotation: *u32,

        const Self = @This();
        pub fn update(self: Self, context: *MyContext) !void {
            _ = context;
            self.rotation.* += 4;
        }

        pub fn print(self: Self, context: *MyContext) !void {
            _ = context;
            std.debug.print("---- rotation for: {d} is: {}\n", .{ self.id, self.rotation.* });
        }
    };

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    _ = try entities.create(Entry, .{ .rotation = 75 });

    const e = try entities.new();
    try entities.setComponent(e, .rotation, 42);

    //var state: i32 = 43;
    var ctx = MyContext.init(allocator, {}, &entities);
    const Pipe = Pipeline(MyContext, &.{RotationSystem});

    var pipeline = Pipe.init(&ctx);
    std.debug.print("\n---- Test Pipeline ---- \n\n", .{});
    try pipeline.run(.print);
    try pipeline.run(.update);

    std.debug.print("\n", .{});
    try pipeline.run(.print);
    std.debug.print("\n---- Test Pipeline ---- \n", .{});
}
