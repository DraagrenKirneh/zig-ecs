const std = @import("std");
const ecs = @import("ecs");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;
const EntityID = @import("ecs.zig").EntityID;

pub fn ContextCommands(comptime Entities: type) type {
    return struct {
        commands: List,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .commands = List.init(allocator),
            };
        }

        pub const Command = union(enum) {
            Delete: void,
            RemovePair: struct { key: Entities.TagType, value: Entities.TagType },
            RemoveComponent: struct { tag: Entities.TagType },
            AddComponent: Entities.AnyComponent,
        };

        const Entry = struct {
            id: ecs.EntityID,
            command: Command,
        };

        const List = std.ArrayList(Entry);

        pub fn submit(self: *Self, entities: *Entities) !void {
            for (self.list.items) |entry| {
                switch (entry.command) {
                    .Delete => try entities.remove(entry.id),
                    .RemoveComponent => |cmd| try entities.removeComponent(entry.id, cmd.tag),
                    .RemovePair => |cmd| try entities.removePair(entry.id, cmd.key, cmd.value),
                    .AddComponent => |cmd| try entities.addAnyComponent(entry.id, cmd),
                }
            }
            self.commands.clearRetainingCapacity();
        }
    };
}

pub fn Context(comptime Resources: type, comptime Entities: type) type {
    return struct {
        entities: *Entities,
        resources: ResourcesPtr,
        allocator: Allocator,
        cache: Cache,
        commands: ContextCommands(Entities),

        const CommandBuffer = ContextCommands(Entities);

        const Self = @This();
        pub const ResourcesType = Resources;
        const ResourcesPtr = if (Resources == void) void else *Resources;
        pub const EntitesType = Entities;

        pub fn init(allocator: Allocator, resources: ResourcesPtr, entities: *Entities) Self {
            return .{
                .allocator = allocator,
                .resources = resources,
                .entities = entities,
                .cache = Cache.init(allocator),
                .commands = ContextCommands(Entities).init(allocator),
            };
        }

        fn Iterator(comptime T: type) type {
            return EntitesType.TypedIter(T);
        }

        pub fn deferCommand(self: *Self, command: CommandBuffer.Command) !void {
            return self.commands.commands.append(command);
        }

        pub fn submitCommands(self: *Self) !void {
            return self.commands.submit(self.entities);
        }

        pub fn getIterator(self: *Self, comptime T: type) Iterator(T) {
            return Iterator(T).init(self.entities);
        }

        // return a valid ptr to an object cached only per frame
        pub fn getPerFrameCachedPtr(self: *Self, comptime Key: type, comptime Value: type, comptime generateFn: fn (context: *Self) anyerror!*Value) !*Value {
            if (self.cache.get(Key, Value)) |result| {
                return result;
            }
            var result = try generateFn(self);
            try self.cache.set(Key, Value, result);
            return result;
        }
    };
}
