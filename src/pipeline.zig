const std = @import("std");
const storage = @import("storage.zig");
const reflection = @import("reflection.zig");
const ecs = @import("ecs.zig");
const testing = std.testing;
const Cache = @import("cache.zig").PointerCache;

const DeferOption = enum {
    // submit the defer queue at the end of the run
    once,

    // submit the defer queue after each system on the same run
    always,

    // skip the queue
    skip,
};

pub fn ResourceContainer(comptime types: []const type) type {
    _ = types;
    return struct {};
}

pub fn Pipeline(comptime Context: type, comptime systems: []const type) type {
    return struct {
        context: *Context,

        const Operation = reflection.ToEnumFromMethods(Context, systems);
        const Self = @This();

        pub fn init(context: *Context) Self {
            return .{ .context = context };
        }

        fn fillResourceArg(self: *const Self, comptime T: type) T {
            var params: T = undefined;
            inline for (std.meta.fields(T)) |p_field| {
                const sub_type = @typeInfo(p_field.type).Pointer.child;
                @field(params, p_field.name) = self.context.getResource(sub_type);
            }
            return params;
        }

        pub fn runWithDefferment(self: *Self, comptime tag: Operation, comptime defferment: DeferOption) !void {
            const declName = @tagName(tag);
            inline for (systems) |system| {
                // @NOTE may want to have an option to submit commands per system that is run.
                if (!@hasDecl(system, declName)) continue;

                const field = @field(system, declName);
                const field_type = @TypeOf(field);
                const type_info = @typeInfo(field_type);
                if (type_info != .Fn) continue;
                const fn_field = type_info.Fn;
                const argType = comptime reflection.argumentType(Context, system, fn_field);
                switch (argType) {
                    .self => {
                        var iter = self.context.getIterator(system);
                        while (iter.next()) |value| {
                            try @call(.auto, field, .{value});
                        }
                    },
                    .context => {
                        try @call(.auto, field, .{self.context});
                    },
                    .resources => {
                        const arg = self.fillResourceArg(type_info.Fn.params[0].type.?);
                        try @call(.auto, field, .{arg});
                    },
                    .self_context => {
                        var iter = self.context.getIterator(system);
                        while (iter.next()) |value| {
                            try @call(.auto, field, .{ value, self.context });
                        }
                    },
                    .self_resources => {
                        const arg = self.fillResourceArg(type_info.Fn.params[1].type.?);
                        var iter = self.context.getIterator(system);
                        while (iter.next()) |value| {
                            try @call(.auto, field, .{ value, arg });
                        }
                    },
                    .context_resources => {
                        const arg = self.fillResourceArg(type_info.Fn.params[1].type.?);
                        try @call(.auto, field, .{ self.context, arg });
                    },
                    .self_context_resources => {
                        const arg = self.fillResourceArg(type_info.Fn.params[2].type.?);
                        var iter = self.context.getIterator(system);
                        while (iter.next()) |value| {
                            try @call(.auto, field, .{ value, self.context, arg });
                        }
                    },
                    .invalid => unreachable,
                }
                if (defferment == .always) {
                    try self.context.submitCommands();
                }
            }

            if (defferment == .once) {
                try self.context.submitCommands();
            }
        }

        pub fn run(self: *Self, comptime tag: Operation) !void {
            return self.runWithDefferment(tag, .once);
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
    const MyContext = ecs.Context(MyEntities);

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

    //var state: i32 = 43;,
    var cache = ecs.Resources.init(allocator);
    var ctx = MyContext.init(allocator, &cache.cache, &entities);
    const Pipe = Pipeline(MyContext, &.{RotationSystem});

    var pipeline = Pipe.init(&ctx);
    std.debug.print("\n---- Test Pipeline ---- \n\n", .{});
    try pipeline.run(.print);
    try pipeline.run(.update);

    std.debug.print("\n", .{});
    try pipeline.run(.print);
    std.debug.print("\n---- Test Pipeline ---- \n", .{});
}

test "deferment" {
    const allocator = std.testing.allocator;

    const Components = struct {
        id: ecs.EntityID,
        dead: void,
        counter: i32,
        step: i32,
    };

    const MyEntities = ecs.Entities(Components);
    const MyContext = ecs.Context(MyEntities);

    const RemoveDeadSystem = struct {
        id: ecs.EntityID,
        dead: void,

        const Self = @This();

        pub fn frameEnd(self: Self, context: *MyContext) !void {
            try context.deferCommand(self.id, .{ .remove_entity = {} });
        }
    };

    const StepCounterSystem = struct {
        id: ecs.EntityID,
        counter: *i32,
        step: i32,

        const Self = @This();

        pub fn update(self: Self, context: *MyContext) !void {
            self.counter.* = self.counter.* - self.step;
            if (self.counter.* < 0) {
                try context.deferCommand(self.id, .{ .add_component = .{ .dead = {} } });
            }
        }
    };

    var entities = MyEntities.init(allocator);
    defer entities.deinit();

    var id = try entities.new();
    try entities.setComponent(id, .counter, 10);
    try entities.setComponent(id, .step, 11);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var resources = ecs.Resources.init(allocator);
    var ctx = MyContext.init(
        arena.allocator(),
        &resources.cache,
        &entities,
    );
    const Pipe = Pipeline(MyContext, &.{
        StepCounterSystem,
        RemoveDeadSystem,
    });

    var pipeline = Pipe.init(&ctx);

    try pipeline.run(.update);
    try pipeline.run(.frameEnd);

    const Query = struct { id: ecs.EntityID };

    var it = entities.getIterator(Query);
    try std.testing.expect(it.next() == null);
}
