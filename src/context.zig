const std = @import("std");
const ecs = @import("ecs.zig");
const Allocator = std.mem.Allocator;
const Cache = @import("cache.zig").PointerCache;
const EntityID = @import("ecs.zig").EntityID;

pub fn CommandDeferList(comptime Entities: type) type {
    return struct {
        list: List,

        const Self = @This();

        pub fn init(allocator: Allocator) Self {
            return .{
                .list = List.init(allocator),
            };
        }

        pub fn addCommand(self: *Self, entityId: ecs.EntityID, command: Command) !void {
            return self.list.append(.{ .id = entityId, .command = command });
        }

        pub const Command = union(enum) {
            remove_entity: void,
            remove_pair: struct { key: Entities.Tag, value: Entities.Tag },
            remove_component: struct { tag: Entities.Tag },
            add_component: Entities.AnyComponent,
        };

        const Entry = struct {
            id: ecs.EntityID,
            command: Command,
        };

        const List = std.ArrayList(Entry);

        pub fn submit(self: *Self, entities: *Entities) !void {
            for (self.list.items) |entry| {
                switch (entry.command) {
                    .remove_entity => try entities.remove(entry.id),
                    .remove_component => |cmd| try entities.removeComponent(entry.id, cmd.tag),
                    .remove_pair => |cmd| try entities.removePair(entry.id, cmd.key, cmd.value),
                    .add_component => |cmd| try entities.setAnyComponent(entry.id, cmd),
                }
            }
            self.list.clearRetainingCapacity();
        }
    };
}

pub fn Context(comptime Resources: type, comptime Entities: type) type {
    return struct {
        entities: *Entities,
        resources: ResourcesPtr,
        allocator: Allocator,
        cache: Cache,
        commands: DeferList,
        singletons: Cache,

        const DeferList = CommandDeferList(Entities);

        const Self = @This();
        pub const ResourcesType = Resources;
        const ResourcesPtr = if (Resources == void) void else *Resources;
        pub const EntitesType = Entities;

        pub fn init(
            allocator: Allocator,
            singletons: Cache,
            resources: ResourcesPtr,
            entities: *Entities,
        ) Self {
            return .{
                .allocator = allocator,
                .resources = resources,
                .entities = entities,
                .cache = Cache.init(allocator),
                .commands = DeferList.init(allocator),
                .singletons = singletons,
            };
        }

        fn Iterator(comptime T: type) type {
            return EntitesType.TypedIter(T);
        }

        pub fn deferCommand(self: *Self, entityId: ecs.EntityID, command: DeferList.Command) !void {
            return self.commands.addCommand(entityId, command);
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
